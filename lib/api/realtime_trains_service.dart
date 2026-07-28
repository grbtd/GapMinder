import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'secrets_loader.dart';
import '../models/departure.dart';
import '../models/secrets.dart';
import '../models/service_detail.dart';

class _UnauthorizedException implements Exception {
  final String message;
  _UnauthorizedException(this.message);

  @override
  String toString() => message;
}

class RealtimeTrainsService {
  static RealtimeTrainsService? _instance;

  final http.Client _client;
  final Future<Secrets> Function() _secretsLoader;

  String? _userToken;
  String? _cachedAccessToken;
  DateTime? _tokenExpiry;
  bool _isInitialized = false;

  final Map<String, ServiceDetail> _serviceCache = {};
  final Map<String, DateTime> _serviceCacheTime = {};

  final Map<String, List<Departure>> _locationCache = {};
  final Map<String, DateTime> _locationCacheTime = {};

  factory RealtimeTrainsService({
    http.Client? client,
    Future<Secrets> Function()? secretsLoader,
  }) {
    if (client != null || secretsLoader != null) {
      return RealtimeTrainsService._internal(
        client: client ?? http.Client(),
        secretsLoader: secretsLoader ?? loadSecrets,
      );
    }
    _instance ??= RealtimeTrainsService._internal(
      client: http.Client(),
      secretsLoader: loadSecrets,
    );
    return _instance!;
  }

  RealtimeTrainsService._internal({
    required http.Client client,
    required Future<Secrets> Function() secretsLoader,
  })  : _client = client,
        _secretsLoader = secretsLoader;

  Future<void> _initialize() async {
    if (_isInitialized) return;
    final secrets = await _secretsLoader();
    _userToken = secrets.token.trim();
    _isInitialized = true;
  }

  Future<String> _getValidAccessToken({bool forceRefresh = false}) async {
    await _initialize();
    if (_userToken == null || _userToken!.isEmpty) {
      throw Exception('RTT Bearer token is missing. Please set "token" in assets/secrets.json.');
    }

    if (!forceRefresh &&
        _cachedAccessToken != null &&
        _tokenExpiry != null &&
        _tokenExpiry!.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return _cachedAccessToken!;
    }

    try {
      final url = Uri.parse('https://data.rtt.io/api/get_access_token');
      final response = await _client.get(
        url,
        headers: {'Authorization': 'Bearer $_userToken'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final accessToken = data['accessToken'] ?? data['token'] ?? data['access_token'];
        if (accessToken != null && accessToken is String && accessToken.isNotEmpty) {
          _cachedAccessToken = accessToken;

          final validUntilRaw = data['validUntil'] ?? data['expiresAt'] ?? data['expires_at'];
          final expiresInRaw = data['expiresIn'] ?? data['expires_in'];

          if (validUntilRaw != null) {
            final parsedDate = DateTime.tryParse(validUntilRaw.toString());
            if (parsedDate != null) {
              _tokenExpiry = parsedDate;
            } else if (validUntilRaw is num) {
              final int timestamp = validUntilRaw.toInt();
              if (timestamp > 100000000000) {
                _tokenExpiry = DateTime.fromMillisecondsSinceEpoch(timestamp);
              } else {
                _tokenExpiry = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
              }
            }
          } else if (expiresInRaw != null && expiresInRaw is num) {
            _tokenExpiry = DateTime.now().add(Duration(seconds: expiresInRaw.toInt()));
          } else {
            _tokenExpiry = DateTime.now().add(const Duration(hours: 1));
          }

          return accessToken;
        }
      }
    } catch (_) {}

    if (_cachedAccessToken != null) {
      return _cachedAccessToken!;
    }
    return _userToken!;
  }

  // Use the Bearer token for rtt-ng API
  Future<Map<String, String>> _getAuthHeaders({bool forceRefresh = false}) async {
    final token = await _getValidAccessToken(forceRefresh: forceRefresh);
    return {
      'Authorization': 'Bearer $token',
      'Version': 'latest',
    };
  }

  Future<T> _executeWithRetry<T>(Future<T> Function(Map<String, String> headers) action) async {
    var headers = await _getAuthHeaders();
    try {
      return await action(headers);
    } on _UnauthorizedException {
      headers = await _getAuthHeaders(forceRefresh: true);
      return await action(headers);
    }
  }

  Map<String, String> _parseServiceIdAndDate(String serviceUid, String runDate) {
    String uid = serviceUid.trim();
    if (uid.startsWith('gb-nr:')) {
      uid = uid.substring(6);
    }
    String date = runDate.trim().replaceAll('/', '-');

    if (uid.contains(':')) {
      final parts = uid.split(':');
      uid = parts[0];
      if (date.isEmpty && parts.length > 1) {
        date = parts[1].replaceAll('/', '-');
      }
    } else if (uid.contains('/')) {
      final parts = uid.split('/');
      uid = parts[0];
      if (date.isEmpty && parts.length > 1) {
        date = parts.sublist(1).join('-').replaceAll('/', '-');
      }
    }

    if (date.isEmpty) {
      final now = DateTime.now();
      date = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    }

    return {'uid': uid, 'date': date};
  }

  DateTime? _getDepartureDateTime(Departure dep, DateTime referenceDate) {
    final timeStr = dep.realtimeTime ?? dep.scheduledTime;
    if (timeStr == null || timeStr.length < 4) return null;

    try {
      final hour = int.parse(timeStr.substring(0, 2));
      final minute = int.parse(timeStr.substring(2, 4));

      DateTime depDate = DateTime(referenceDate.year, referenceDate.month, referenceDate.day, hour, minute);

      // Handle midnight wrap relative to referenceDate
      if (referenceDate.hour == 23 && hour == 0) {
        depDate = depDate.add(const Duration(days: 1));
      } else if (referenceDate.hour == 0 && hour == 23) {
        depDate = depDate.subtract(const Duration(days: 1));
      }

      return depDate;
    } catch (_) {
      return null;
    }
  }

  bool _isWithinTimeWindow(Departure dep, {required DateTime now, Duration windowDuration = const Duration(minutes: 30)}) {
    final depDate = _getDepartureDateTime(dep, now);
    if (depDate == null) return true;

    final diff = depDate.difference(now);
    return diff.inMinutes >= -5 && diff.inMinutes <= windowDuration.inMinutes;
  }

  Future<List<Departure>> _fetchLocationFromApi(String cleanCrs, {DateTime? pivotTime}) async {
    Uri url;
    if (pivotTime != null) {
      final year = pivotTime.year;
      final month = pivotTime.month.toString().padLeft(2, '0');
      final day = pivotTime.day.toString().padLeft(2, '0');
      final hour = pivotTime.hour.toString().padLeft(2, '0');
      final minute = pivotTime.minute.toString().padLeft(2, '0');
      url = Uri.parse('https://data.rtt.io/rtt/location?code=gb-nr:$cleanCrs&date=$year-$month-$day&time=$hour$minute');
    } else {
      url = Uri.parse('https://data.rtt.io/rtt/location?code=gb-nr:$cleanCrs');
    }

    return _executeWithRetry((headers) async {
      debugPrint('[RealtimeTrainsService] HTTP GET $url');
      final response = await _client.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> services = data['services'] ?? [];
        return services
            .map((json) => Departure.fromJson(json as Map<String, dynamic>))
            .toList();
      } else if (response.statusCode == 401) {
        String detail = 'Invalid or expired token';
        try {
          final data = json.decode(response.body);
          if (data['error'] != null) detail = data['error'].toString();
        } catch (_) {}
        throw _UnauthorizedException('401 Unauthorized: $detail');
      } else {
        throw Exception('Failed to load departures: status ${response.statusCode}');
      }
    });
  }

  Future<List<Departure>> fetchDepartures(
    String crsCode, {
    bool forceRefresh = false,
    DateTime? pivotTime,
    void Function(String statusMessage)? onProgress,
  }) async {
    onProgress?.call('Fetching departure board...');
    final cleanCrs = crsCode.trim().toUpperCase();
    final referenceTime = pivotTime ?? DateTime.now();

    final dateStr = "${referenceTime.year}-${referenceTime.month.toString().padLeft(2, '0')}-${referenceTime.day.toString().padLeft(2, '0')}";
    final timeStr = "${referenceTime.hour.toString().padLeft(2, '0')}${referenceTime.minute.toString().padLeft(2, '0')}";
    final cacheKey = '$cleanCrs:${pivotTime != null ? "${dateStr}_$timeStr" : "live"}';

    List<Departure> departures;

    if (!forceRefresh && _locationCache.containsKey(cacheKey)) {
      final cacheTime = _locationCacheTime[cacheKey];
      if (cacheTime != null && cacheTime.isAfter(DateTime.now().subtract(const Duration(minutes: 5)))) {
        debugPrint('[RealtimeTrainsService] Using cached location board for $cacheKey');
        departures = _locationCache[cacheKey]!;
      } else {
        departures = await _fetchLocationFromApi(cleanCrs, pivotTime: pivotTime);
        _locationCache[cacheKey] = departures;
        _locationCacheTime[cacheKey] = DateTime.now();
      }
    } else {
      departures = await _fetchLocationFromApi(cleanCrs, pivotTime: pivotTime);
      _locationCache[cacheKey] = departures;
      _locationCacheTime[cacheKey] = DateTime.now();
    }

    debugPrint('[RealtimeTrainsService] fetchDepartures for $cleanCrs (pivotTime: $pivotTime)');

    // Filter out departures with missing time info if possible
    List<Departure> validDepartures = departures.where((dep) {
      return _getDepartureDateTime(dep, referenceTime) != null;
    }).toList();

    if (validDepartures.isEmpty) {
      validDepartures = List.from(departures);
    }

    // Sort departures chronologically relative to referenceTime
    validDepartures.sort((a, b) {
      final aTime = _getDepartureDateTime(a, referenceTime);
      final bTime = _getDepartureDateTime(b, referenceTime);
      if (aTime == null || bTime == null) return 0;
      return aTime.compareTo(bTime);
    });

    // Find the starting index in validDepartures closest to referenceTime
    int startIndex = 0;
    if (pivotTime != null) {
      int closestIdx = -1;
      for (int i = 0; i < validDepartures.length; i++) {
        final depTime = _getDepartureDateTime(validDepartures[i], referenceTime);
        if (depTime != null && depTime.isAfter(referenceTime.subtract(const Duration(minutes: 5)))) {
          closestIdx = i;
          break;
        }
      }
      if (closestIdx != -1) {
        final shift = referenceTime.isBefore(DateTime.now()) ? 2 : 0;
        startIndex = (closestIdx - shift).clamp(0, validDepartures.length - 1);
      } else {
        startIndex = (validDepartures.length - 12).clamp(0, validDepartures.length - 1);
      }
    } else {
      final now = DateTime.now();
      for (int i = 0; i < validDepartures.length; i++) {
        final depTime = _getDepartureDateTime(validDepartures[i], now);
        if (depTime != null && depTime.difference(now).inMinutes >= -5) {
          startIndex = i;
          break;
        }
      }
    }

    final targetList = validDepartures.sublist(
      startIndex,
      (startIndex + 12 < validDepartures.length) ? startIndex + 12 : validDepartures.length,
    );
    debugPrint('[RealtimeTrainsService] selected targetList count: ${targetList.length} (startIndex: $startIndex)');

    if (targetList.isEmpty) {
      onProgress?.call('No departures found.');
      return [];
    }

    // Process pre-fetching in small controlled batches (3 at a time) to avoid hitting API rate limits
    const batchSize = 3;
    final enrichedDepartures = <Departure>[];

    for (var i = 0; i < targetList.length; i += batchSize) {
      final end = (i + batchSize < targetList.length) ? i + batchSize : targetList.length;
      final batch = targetList.sublist(i, end);

      final destinations = batch
          .map((d) => d.destination)
          .where((d) => d.isNotEmpty && d != 'Unknown Destination')
          .toSet()
          .join(', ');

      final statusText = destinations.isNotEmpty
          ? 'Processing services ($end of ${targetList.length}): $destinations'
          : 'Processing services ($end of ${targetList.length})...';
      onProgress?.call(statusText);

      final batchResults = await Future.wait(batch.map((dep) async {
        if (dep.serviceUid.isEmpty) return dep;
        try {
          final detail = await fetchServiceDetails(
            dep.serviceUid,
            dep.runDate,
            detailed: false, // Non-detailed query for station board
          );

          // Find calling point matching current station (cleanCrs)
          CallingPoint? stop;
          for (final loc in detail.locations) {
            if (loc.crs != null && loc.crs!.toUpperCase() == cleanCrs) {
              stop = loc;
              break;
            }
          }

          String? updatedStatus = dep.status;
          if (stop?.serviceLocation != null) {
            final locUpper = stop!.serviceLocation!.toUpperCase();
            if (locUpper == 'AT_PLAT' || locUpper == 'APPR_PLAT' || locUpper == 'APPR_STAT') {
              updatedStatus = locUpper;
            }
          }

          return dep.copyWith(
            serviceUid: dep.serviceUid.isNotEmpty ? dep.serviceUid : detail.serviceUid,
            destination: detail.destination != 'Unknown Destination' ? detail.destination : dep.destination,
            operatorName: detail.atocName != 'Unknown Operator' ? detail.atocName : dep.operatorName,
            platform: (stop?.platform != null && stop!.platform!.isNotEmpty) ? stop.platform : dep.platform,
            scheduledTime: stop?.gbttBookedDeparture ?? stop?.gbttBookedArrival ?? dep.scheduledTime,
            realtimeTime: stop?.realtimeDeparture ?? stop?.realtimeArrival ?? dep.realtimeTime,
            status: updatedStatus,
            coachCount: detail.coachCount ?? stop?.coachCount ?? dep.coachCount,
            stockBranding: detail.stockBranding ?? stop?.stockBranding ?? dep.stockBranding,
          );
        } catch (_) {
          return dep;
        }
      }));

      enrichedDepartures.addAll(batchResults);
    }

    return enrichedDepartures;
  }

  Future<ServiceDetail> fetchServiceDetails(
    String serviceUid,
    String runDate, {
    bool detailed = false,
    bool forceRefresh = false,
  }) async {
    final parsed = _parseServiceIdAndDate(serviceUid, runDate);
    final uid = parsed['uid']!;
    final date = parsed['date']!;
    final identity = serviceUid.startsWith('gb-nr:') ? serviceUid : 'gb-nr:$uid:$date';
    final cacheKey = '$identity:${detailed ? 'detailed' : 'summary'}';

    if (!forceRefresh && _serviceCache.containsKey(cacheKey)) {
      final cacheTime = _serviceCacheTime[cacheKey];
      if (cacheTime != null && cacheTime.isAfter(DateTime.now().subtract(const Duration(minutes: 5)))) {
        return _serviceCache[cacheKey]!;
      }
    }

    final cleanIdentity = '$uid:$date';
    final fullIdentity = 'gb-nr:$cleanIdentity';

    final candidateUrls = detailed
        ? <Uri>[
            Uri.parse('https://data.rtt.io/gb-nr/service?uniqueIdentity=$cleanIdentity&detailed=true'),
            Uri.parse('https://data.rtt.io/gb-nr/service?uniqueIdentity=$fullIdentity&detailed=true'),
            Uri.parse('https://data.rtt.io/rtt/service?uniqueIdentity=$fullIdentity&detailed=true'),
            Uri.parse('https://data.rtt.io/rtt/service?uniqueIdentity=$cleanIdentity&detailed=true'),
          ]
        : <Uri>[
            Uri.parse('https://data.rtt.io/rtt/service?uniqueIdentity=$fullIdentity&detailed=false'),
            Uri.parse('https://data.rtt.io/rtt/service?uniqueIdentity=$cleanIdentity&detailed=false'),
          ];

    return _executeWithRetry((headers) async {
      http.Response? lastResponse;

      for (final url in candidateUrls) {
        try {
          debugPrint('[RealtimeTrainsService] Fetching service detail from: $url');
          final response = await _client.get(url, headers: headers);
          debugPrint('[RealtimeTrainsService] HTTP ${response.statusCode} from $url');

          lastResponse = response;
          if (response.statusCode == 200) {
            debugPrint('[RealtimeTrainsService] Raw Response Body: ${response.body}');
            final data = json.decode(response.body);
            final detail = ServiceDetail.fromJson(data);
            _serviceCache[cacheKey] = detail;
            _serviceCacheTime[cacheKey] = DateTime.now();
            return detail;
          } else if (response.statusCode == 401) {
            String detail = 'Invalid or expired token';
            try {
              final data = json.decode(response.body);
              if (data['error'] != null) detail = data['error'].toString();
            } catch (_) {}
            throw _UnauthorizedException('401 Unauthorized: $detail');
          }
        } catch (e) {
          if (e is _UnauthorizedException) rethrow;
        }
      }

      throw Exception('Failed to load service details: status ${lastResponse?.statusCode ?? 404}');
    });
  }
}

