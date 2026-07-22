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
      debugPrint('[RTT API] Error: Bearer token is empty in secrets.json.');
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
      debugPrint('[RTT API] Exchanging refresh token at: $url');
      final response = await _client.get(
        url,
        headers: {'Authorization': 'Bearer $_userToken'},
      );
      debugPrint('[RTT API] Token exchange status: ${response.statusCode}');

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

          debugPrint('[RTT API] Access token cached successfully until $_tokenExpiry.');
          return accessToken;
        }
      } else {
        debugPrint('[RTT API] Token exchange failed with status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[RTT API] Exception during token exchange: $e');
    }

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
      debugPrint('[RTT API] Received 401 Unauthorized. Attempting token refresh...');
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

  bool _isWithinTimeWindow(Departure dep, {required DateTime now, Duration windowDuration = const Duration(minutes: 30)}) {
    final timeStr = dep.realtimeTime ?? dep.scheduledTime;
    if (timeStr == null || timeStr.length < 4) return true;

    try {
      final hour = int.parse(timeStr.substring(0, 2));
      final minute = int.parse(timeStr.substring(2, 4));

      DateTime depDate = DateTime(now.year, now.month, now.day, hour, minute);

      // Handle midnight wrap
      if (now.hour == 23 && hour == 0) {
        depDate = depDate.add(const Duration(days: 1));
      } else if (now.hour == 0 && hour == 23) {
        depDate = depDate.subtract(const Duration(days: 1));
      }

      final diff = depDate.difference(now);
      return diff.inMinutes >= -5 && diff.inMinutes <= windowDuration.inMinutes;
    } catch (_) {
      return true;
    }
  }

  Future<List<Departure>> fetchDepartures(String crsCode, {bool forceRefresh = false}) async {
    final cleanCrs = crsCode.trim().toUpperCase();
    final url = Uri.parse('https://data.rtt.io/rtt/location?code=gb-nr:$cleanCrs');

    List<Departure> departures = await _executeWithRetry((headers) async {
      debugPrint('[RTT API] Fetching departures from: $url');
      final response = await _client.get(url, headers: headers);
      debugPrint('[RTT API] Response status for $url: ${response.statusCode}');

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

    // Filter to departures within the next 30 minutes (-5m to +30m)
    final now = DateTime.now();
    final upcomingDepartures = departures
        .where((dep) => _isWithinTimeWindow(dep, now: now, windowDuration: const Duration(minutes: 30)))
        .toList();

    final targetList = upcomingDepartures.isNotEmpty ? upcomingDepartures : departures.take(15).toList();

    // Process pre-fetching in small controlled batches (3 at a time) to avoid hitting API rate limits
    const batchSize = 3;
    final enrichedDepartures = <Departure>[];

    for (var i = 0; i < targetList.length; i += batchSize) {
      final batch = targetList.sublist(
        i,
        (i + batchSize < targetList.length) ? i + batchSize : targetList.length,
      );

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

          return dep.copyWith(
            serviceUid: dep.serviceUid.isNotEmpty ? dep.serviceUid : detail.serviceUid,
            destination: detail.destination != 'Unknown Destination' ? detail.destination : dep.destination,
            operatorName: detail.atocName != 'Unknown Operator' ? detail.atocName : dep.operatorName,
            platform: (stop?.platform != null && stop!.platform!.isNotEmpty) ? stop.platform : dep.platform,
            scheduledTime: stop?.gbttBookedDeparture ?? stop?.gbttBookedArrival ?? dep.scheduledTime,
            realtimeTime: stop?.realtimeDeparture ?? stop?.realtimeArrival ?? dep.realtimeTime,
            status: stop?.serviceLocation ?? dep.status,
          );
        } catch (e) {
          debugPrint('[RTT API] Pre-fetch details exception for service ${dep.serviceUid}: $e');
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
        debugPrint('[RTT API] Returning cached ServiceDetail for $cacheKey.');
        return _serviceCache[cacheKey]!;
      }
    }

    final candidateUrls = detailed
        ? <Uri>[
            Uri.parse('https://data.rtt.io/gb-nr/service?uniqueIdentity=$identity'),
            Uri.parse('https://data.rtt.io/gb-nr/service?code=$identity'),
            Uri.parse('https://data.rtt.io/rtt/service?uniqueIdentity=$identity&detailed=true'),
          ]
        : <Uri>[
            Uri.parse('https://data.rtt.io/rtt/service?uniqueIdentity=$identity&detailed=false'),
            Uri.parse('https://data.rtt.io/rtt/service?code=$identity&detailed=false'),
          ];

    return _executeWithRetry((headers) async {
      http.Response? lastResponse;

      for (final url in candidateUrls) {
        debugPrint('[RTT API] Fetching service details from: $url');
        try {
          final response = await _client.get(url, headers: headers);
          debugPrint('[RTT API] Response status for $url: ${response.statusCode}');

          lastResponse = response;
          if (response.statusCode == 200) {
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
          debugPrint('[RTT API] Request failed for $url: $e');
        }
      }

      throw Exception('Failed to load service details: status ${lastResponse?.statusCode ?? 404}');
    });
  }
}

