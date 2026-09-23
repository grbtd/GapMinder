import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:live_activities/live_activities.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/realtime_trains_service.dart';
import '../models/departure.dart';
import '../models/service_detail.dart';

class LiveActivityService extends ChangeNotifier {
  static final LiveActivityService _instance = LiveActivityService._internal();

  factory LiveActivityService() => _instance;

  LiveActivityService._internal();

  static const String _keyStarredServices = 'starred_services_data';
  static const String _appGroupId = 'group.com.gapminder.app';
  static const MethodChannel _channel = MethodChannel('space.grbtd.gapminder/live_activity_service');

  final LiveActivities _liveActivitiesPlugin = LiveActivities();
  final RealtimeTrainsService _apiService = RealtimeTrainsService();
  SharedPreferences? _prefs;
  
  // Map of serviceKey -> Map<String, dynamic> of starred service data
  // serviceKey format: "${serviceUid}_${runDate}"
  Map<String, Map<String, dynamic>> _starredServices = {};
  bool _isInitialized = false;
  Timer? _pollingTimer;

  Map<String, Map<String, dynamic>> get starredServices => _starredServices;
  bool get isInitialized => _isInitialized;

  bool get _isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      final storedJson = _prefs?.getString(_keyStarredServices);
      if (storedJson != null && storedJson.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(storedJson);
        _starredServices = decoded.map((key, value) => MapEntry(key, Map<String, dynamic>.from(value)));
      }
    } catch (e) {
      debugPrint('[LiveActivityService] Error loading stored starred services: $e');
    }

    if (_isSupportedPlatform) {
      try {
        await _liveActivitiesPlugin.init(appGroupId: _appGroupId);
      } catch (e) {
        debugPrint('[LiveActivityService] LiveActivities plugin init notice: $e');
      }
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onNotificationDismissed') {
          final String? uid = call.arguments['serviceUid'];
          final String? runDate = call.arguments['runDate'];
          if (uid != null && uid.isNotEmpty && runDate != null && runDate.isNotEmpty) {
            debugPrint('[LiveActivityService] Notification dismissed by user for $uid. Unstarring.');
            await unstarService(uid, runDate);
          }
        }
      });
    }

    _isInitialized = true;
    _updatePollingState();
    notifyListeners();
  }

  String _getServiceKey(String serviceUid, String runDate) {
    return '${serviceUid}_$runDate';
  }

  bool isStarred(String serviceUid, String runDate) {
    final key = _getServiceKey(serviceUid, runDate);
    return _starredServices.containsKey(key);
  }

  Map<String, dynamic>? getStarredService(String serviceUid, String runDate) {
    final key = _getServiceKey(serviceUid, runDate);
    return _starredServices[key];
  }

  Future<bool> toggleStar({
    required Departure departure,
    String? stationName,
    String? stationCrs,
  }) async {
    final isCurrentlyStarred = isStarred(departure.serviceUid, departure.runDate);
    if (isCurrentlyStarred) {
      await unstarService(departure.serviceUid, departure.runDate);
      return false;
    } else {
      await starService(
        departure: departure,
        stationName: stationName,
        stationCrs: stationCrs,
      );
      return true;
    }
  }

  Future<void> starService({
    required Departure departure,
    String? stationName,
    String? stationCrs,
  }) async {
    final key = _getServiceKey(departure.serviceUid, departure.runDate);

    final Map<String, dynamic> activityData = {
      'serviceUid': departure.serviceUid,
      'runDate': departure.runDate,
      'destination': departure.destination,
      'origin': departure.origin ?? '',
      'scheduledTime': departure.scheduledTime ?? '',
      'realtimeTime': departure.realtimeTime ?? '',
      'platform': departure.platform ?? '',
      'status': departure.status ?? '',
      'operator': departure.operatorName ?? '',
      'stationName': stationName ?? '',
      'stationCrs': stationCrs ?? '',
      'isTerminating': departure.isTerminating,
      'title': '${departure.scheduledTime ?? ''} to ${departure.destination}',
      'subtitle': (departure.platform != null && departure.platform!.isNotEmpty)
          ? 'Platform ${departure.platform}'
          : 'Platform TBC',
      'updatedAt': DateTime.now().toIso8601String(),
    };

    String? activityId;

    if (_isSupportedPlatform) {
      try {
        final enabled = await _liveActivitiesPlugin.areActivitiesEnabled();
        if (enabled) {
          activityId = await _liveActivitiesPlugin.createActivity(
            key,
            activityData,
          );
          debugPrint('[LiveActivityService] Created Live Activity with ID: $activityId');
        }
      } catch (e) {
        debugPrint('[LiveActivityService] Live Activity create notice: $e');
      }
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod('startForegroundService', activityData);
      } catch (e) {
        debugPrint('[LiveActivityService] Android Foreground Service start notice: $e');
      }
    }

    activityData['activityId'] = activityId ?? key;
    activityData['starredAt'] = DateTime.now().toIso8601String();

    _starredServices[key] = activityData;
    await _saveToPrefs();
    _updatePollingState();
    notifyListeners();
  }

  Future<void> unstarService(String serviceUid, String runDate) async {
    final key = _getServiceKey(serviceUid, runDate);
    final existingData = _starredServices[key];

    if (existingData != null) {
      final String? activityId = existingData['activityId'];
      if (_isSupportedPlatform && activityId != null && activityId.isNotEmpty) {
        try {
          await _liveActivitiesPlugin.endActivity(activityId);
          debugPrint('[LiveActivityService] Ended Live Activity with ID: $activityId');
        } catch (e) {
          debugPrint('[LiveActivityService] Live Activity end notice: $e');
        }
      }
      _starredServices.remove(key);
      await _saveToPrefs();
      _updatePollingState();
      notifyListeners();
    }
  }

  Future<void> updateFromDeparture(Departure departure) async {
    final key = _getServiceKey(departure.serviceUid, departure.runDate);
    final existingData = _starredServices[key];

    if (existingData == null) return;

    existingData['scheduledTime'] = departure.scheduledTime ?? existingData['scheduledTime'];
    existingData['realtimeTime'] = departure.realtimeTime ?? existingData['realtimeTime'];
    existingData['platform'] = departure.platform ?? existingData['platform'];
    existingData['status'] = departure.status ?? existingData['status'];
    existingData['destination'] = departure.destination;
    if (departure.origin != null) existingData['origin'] = departure.origin;
    if (departure.operatorName != null) existingData['operator'] = departure.operatorName;
    existingData['updatedAt'] = DateTime.now().toIso8601String();

    existingData['title'] = '${existingData['scheduledTime']} to ${existingData['destination']}';
    existingData['subtitle'] = (existingData['platform'] != null && existingData['platform'].toString().isNotEmpty)
        ? 'Platform ${existingData['platform']}'
        : 'Platform TBC';

    final String? activityId = existingData['activityId'];
    if (_isSupportedPlatform && activityId != null && activityId.isNotEmpty) {
      try {
        await _liveActivitiesPlugin.updateActivity(activityId, existingData);
        debugPrint('[LiveActivityService] Updated Live Activity ID: $activityId');
      } catch (e) {
        debugPrint('[LiveActivityService] Live Activity update notice: $e');
      }
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod('updateForegroundService', existingData);
      } catch (_) {}
    }

    _starredServices[key] = existingData;
    await _saveToPrefs();
    notifyListeners();
  }

  Future<void> updateFromServiceDetail(ServiceDetail detail) async {
    if (detail.runDate == null) return;
    final key = _getServiceKey(detail.serviceUid, detail.runDate!);
    final existingData = _starredServices[key];

    if (existingData == null) return;

    if (detail.origin.isNotEmpty) {
      existingData['origin'] = detail.origin;
    }
    if (detail.destination.isNotEmpty) {
      existingData['destination'] = detail.destination;
    }
    if (detail.atocName.isNotEmpty) {
      existingData['operator'] = detail.atocName;
    }

    final String stationCrs = (existingData['stationCrs'] ?? '').toString().toUpperCase();
    final String stationName = (existingData['stationName'] ?? '').toString().toLowerCase();

    CallingPoint? targetLoc;
    for (var loc in detail.locations) {
      if (stationCrs.isNotEmpty && loc.crs?.toUpperCase() == stationCrs) {
        targetLoc = loc;
        break;
      }
      if (stationName.isNotEmpty && loc.locationName?.toLowerCase() == stationName) {
        targetLoc = loc;
        break;
      }
    }

    if (targetLoc != null) {
      if (targetLoc.platform != null && targetLoc.platform!.isNotEmpty) {
        existingData['platform'] = targetLoc.platform;
      }
      if (targetLoc.serviceLocation != null && targetLoc.serviceLocation!.isNotEmpty) {
        existingData['status'] = targetLoc.serviceLocation;
      } else if (targetLoc.realtimeDeparture != null && targetLoc.gbttBookedDeparture != null) {
        if (targetLoc.realtimeDeparture == targetLoc.gbttBookedDeparture) {
          existingData['status'] = 'ON TIME';
        } else {
          existingData['status'] = 'Exp ${targetLoc.realtimeDeparture}';
        }
      }
    }

    existingData['title'] = '${existingData['scheduledTime']} to ${existingData['destination']}';
    existingData['subtitle'] = (existingData['platform'] != null && existingData['platform'].toString().isNotEmpty)
        ? 'Platform ${existingData['platform']}'
        : 'Platform TBC';

    existingData['updatedAt'] = DateTime.now().toIso8601String();

    final String? activityId = existingData['activityId'];
    if (_isSupportedPlatform && activityId != null && activityId.isNotEmpty) {
      try {
        await _liveActivitiesPlugin.updateActivity(activityId, existingData);
        debugPrint('[LiveActivityService] Updated Live Activity from ServiceDetail ID: $activityId');
      } catch (e) {
        debugPrint('[LiveActivityService] Live Activity update notice: $e');
      }
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod('updateForegroundService', existingData);
      } catch (_) {}
    }

    _starredServices[key] = existingData;
    await _saveToPrefs();
    notifyListeners();
  }

  Future<void> clearAll() async {
    for (var entry in _starredServices.values) {
      final String? activityId = entry['activityId'];
      if (_isSupportedPlatform && activityId != null && activityId.isNotEmpty) {
        try {
          await _liveActivitiesPlugin.endActivity(activityId);
        } catch (_) {}
      }
    }
    _starredServices.clear();
    await _saveToPrefs();
    _updatePollingState();
    notifyListeners();
  }

  void _updatePollingState() {
    if (_starredServices.isNotEmpty) {
      _startPollingTimer();
    } else {
      _stopPollingTimer();
    }
  }

  void _startPollingTimer() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _pollActiveStarredServices();
    });
  }

  void _stopPollingTimer() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        _channel.invokeMethod('stopForegroundService');
      } catch (_) {}
    }
  }

  Future<void> _pollActiveStarredServices() async {
    if (_starredServices.isEmpty) {
      _stopPollingTimer();
      return;
    }

    final activeKeys = _starredServices.keys.toList();
    for (var key in activeKeys) {
      final item = _starredServices[key];
      if (item == null) continue;

      final String serviceUid = item['serviceUid'] ?? '';
      final String runDate = item['runDate'] ?? '';

      if (serviceUid.isEmpty || runDate.isEmpty) continue;

      try {
        final detail = await _apiService.fetchServiceDetails(
          serviceUid,
          runDate,
          forceRefresh: true,
        );

        if (_checkIfServiceFinished(item, detail)) {
          debugPrint('[LiveActivityService] Service $serviceUid has departed starting station or finished. Ending notification.');
          await unstarService(serviceUid, runDate);
        } else {
          await updateFromServiceDetail(detail);
        }
      } catch (e) {
        debugPrint('[LiveActivityService] Error polling service $serviceUid: $e');
      }
    }
  }

  bool _checkIfServiceFinished(Map<String, dynamic> item, ServiceDetail detail) {
    if (detail.locations.isEmpty) return false;

    final String stationCrs = (item['stationCrs'] ?? '').toString().toUpperCase();
    final String stationName = (item['stationName'] ?? '').toString().toLowerCase();

    // 1. Check if the train has departed the specific station the user starred from!
    int targetIndex = -1;
    if (stationCrs.isNotEmpty || stationName.isNotEmpty) {
      for (int i = 0; i < detail.locations.length; i++) {
        final loc = detail.locations[i];
        if (stationCrs.isNotEmpty && loc.crs?.toUpperCase() == stationCrs) {
          targetIndex = i;
          break;
        }
        if (stationName.isNotEmpty && loc.locationName?.toLowerCase() == stationName) {
          targetIndex = i;
          break;
        }
      }
    }

    if (targetIndex != -1) {
      final targetLoc = detail.locations[targetIndex];
      
      // If the target station report has an actual report (actual arrival/departure report filed)
      if (targetLoc.hasActualReport) {
        // If it's not the final destination in the route, check if actual departure has taken place
        if (targetIndex < detail.locations.length - 1) {
          if (targetLoc.realtimeDeparture != null || targetLoc.gbttBookedDeparture != null) {
            debugPrint('[LiveActivityService] Train has departed starting station (${targetLoc.locationName}). Ending notification.');
            return true;
          }
        } else {
          // It's the final destination and actual report exists
          return true;
        }
      }

      // Check if train has progressed past targetIndex in calling points
      for (int i = targetIndex + 1; i < detail.locations.length; i++) {
        if (detail.locations[i].hasActualReport) {
          debugPrint('[LiveActivityService] Train has progressed past ${targetLoc.locationName} to ${detail.locations[i].locationName}. Ending notification.');
          return true;
        }
      }
    }

    // 2. Check overall service completion / destination reach / cancellation
    final lastLocation = detail.locations.last;
    final statusUpper = (lastLocation.serviceLocation ?? '').toUpperCase();

    if (lastLocation.hasActualReport || statusUpper == 'ARRIVED' || statusUpper == 'TERMINATED') {
      return true;
    }

    // 3. Handle cancelled service after scheduled departure time
    final schedTimeStr = item['scheduledTime'];
    if (schedTimeStr != null && schedTimeStr.length == 4) {
      try {
        final h = int.parse(schedTimeStr.substring(0, 2));
        final m = int.parse(schedTimeStr.substring(2, 4));
        final now = DateTime.now();
        final schedDateTime = DateTime(now.year, now.month, now.day, h, m);
        if (now.isAfter(schedDateTime.add(const Duration(minutes: 15))) &&
            (item['status'] == 'CANCELLED' || item['status'] == 'CANCELLED_CALL')) {
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  Future<void> _saveToPrefs() async {
    try {
      final encoded = jsonEncode(_starredServices);
      await _prefs?.setString(_keyStarredServices, encoded);
    } catch (e) {
      debugPrint('[LiveActivityService] Error saving starred services: $e');
    }
  }
}
