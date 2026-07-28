import '../helpers/json_parsers.dart';

class Departure {
  final String serviceUid;
  final String runDate;
  final String? scheduledTime; // Nullable
  final String? realtimeTime; // Nullable
  final String? platform; // Nullable
  final String? operatorName; // Nullable
  final String destination;
  final bool platformChanged;
  final String? status; // Nullable
  final String? serviceType; // Nullable
  final String? cancelReasonShortText; // Nullable
  final String? cancelReasonLongText; // Nullable

  Departure({
    required this.serviceUid,
    required this.runDate,
    required this.scheduledTime,
    required this.realtimeTime,
    required this.platform,
    required this.operatorName,
    required this.destination,
    required this.platformChanged,
    required this.status,
    required this.serviceType,
    this.cancelReasonShortText,
    this.cancelReasonLongText,
  });

  Departure copyWith({
    String? serviceUid,
    String? runDate,
    String? scheduledTime,
    String? realtimeTime,
    String? platform,
    String? operatorName,
    String? destination,
    bool? platformChanged,
    String? status,
    String? serviceType,
    String? cancelReasonShortText,
    String? cancelReasonLongText,
  }) {
    return Departure(
      serviceUid: serviceUid ?? this.serviceUid,
      runDate: runDate ?? this.runDate,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      realtimeTime: realtimeTime ?? this.realtimeTime,
      platform: platform ?? this.platform,
      operatorName: operatorName ?? this.operatorName,
      destination: destination ?? this.destination,
      platformChanged: platformChanged ?? this.platformChanged,
      status: status ?? this.status,
      serviceType: serviceType ?? this.serviceType,
      cancelReasonShortText: cancelReasonShortText ?? this.cancelReasonShortText,
      cancelReasonLongText: cancelReasonLongText ?? this.cancelReasonLongText,
    );
  }

  factory Departure.fromJson(Map<String, dynamic> json) {
    final locationDetail = (json['locationDetail'] as Map<String, dynamic>?) ??
        (json['location'] as Map<String, dynamic>?) ??
        {};
    final metadata = (json['locationMetadata'] as Map<String, dynamic>?) ??
        (json['metadata'] as Map<String, dynamic>?) ??
        {};
    final schedule = (json['scheduleMetadata'] as Map<String, dynamic>?) ?? {};
    final temporal = (json['temporalData'] as Map<String, dynamic>?) ?? {};

    final destinationsData = locationDetail['destination'] ??
        metadata['destination'] ??
        json['destination'] ??
        schedule['destination'] ??
        locationDetail['destinations'] ??
        metadata['destinations'] ??
        json['destinations'] ??
        json['destinationLocation'];

    final destinationStr = parseLocationDescription(destinationsData);

    final operatorData = schedule['operator'] ??
        json['operator'] ??
        locationDetail['operator'] ??
        metadata['operator'];
    final operatorNameStr = parseOperatorName(
      operatorData,
      json['atocName'] ?? locationDetail['atocName'] ?? json['operatorName'],
    );

    final serviceUidStr = parseServiceUid(json, schedule, metadata);
    final runDateStr = asString(
          schedule['departureDate'] ??
          json['runDate'] ??
          json['date'] ??
          schedule['date'] ??
          locationDetail['runDate'],
        ) ??
        '';

    String? getStatus() {
      final displayAs = locationDetail['displayAs']?.toString() ??
          metadata['displayAs']?.toString() ??
          json['displayAs']?.toString();
      if (displayAs != null &&
          (displayAs == 'CANCELLED_CALL' ||
              displayAs == 'CANCELLED_PASS' ||
              displayAs.startsWith('CANCELLED'))) {
        return 'CANCELLED';
      }

      // Prioritize explicit live positioning (AT_PLAT, APPR_PLAT, APPR_STAT)
      final serviceLocation = locationDetail['serviceLocation']?.toString() ??
          metadata['serviceLocation']?.toString() ??
          json['serviceLocation']?.toString();
      if (serviceLocation != null && serviceLocation.isNotEmpty) {
        final locUpper = serviceLocation.toUpperCase();
        if (locUpper == 'AT_PLAT' || locUpper == 'APPR_PLAT' || locUpper == 'APPR_STAT') {
          return locUpper;
        }
      }

      // Fallback to structured lateness information
      final lateness = temporal['realtimeAdvertisedLateness'] ??
          locationDetail['realtimeGbttDepartureLateness'] ??
          json['lateness'];
      if (lateness != null) {
        final latenessNum = num.tryParse(lateness.toString());
        if (latenessNum != null) {
          if (latenessNum > 0) return 'LATE';
          if (latenessNum < 0) return 'EARLY';
          return 'ON TIME';
        }
      }

      return null;
    }

    // Timing logic: check departure first, then arrival, then pass
    final dep = temporal['departure'] ?? json['departure'] ?? {};
    final arr = temporal['arrival'] ?? json['arrival'] ?? {};
    final pass = temporal['pass'] ?? json['pass'] ?? {};

    String? scheduledTimeRaw = locationDetail['gbttBookedDeparture'] ??
        locationDetail['gbttBookedArrival'] ??
        locationDetail['publicTime'] ??
        dep['scheduled'] ??
        arr['scheduled'] ??
        pass['scheduled'] ??
        json['gbttBookedDeparture'] ??
        json['scheduledTime'];

    String? realtimeTimeRaw = locationDetail['realtimeDeparture'] ??
        locationDetail['realtimeArrival'] ??
        dep['realtimeForecast'] ??
        dep['realtimeActual'] ??
        arr['realtimeForecast'] ??
        arr['realtimeActual'] ??
        pass['realtimeForecast'] ??
        pass['realtimeActual'] ??
        json['realtimeDeparture'] ??
        json['realtimeTime'];

    final platformRaw = locationDetail['platform'] ??
        metadata['platform'] ??
        json['platform'];
    final platformStr = parsePlatform(platformRaw);
    final platformChanged = parsePlatformChanged(
      platformRaw,
      locationDetail['platformChanged'] ?? metadata['platform']?['changed'] ?? json['platformChanged'],
    );

    return Departure(
      serviceUid: serviceUidStr,
      runDate: runDateStr,
      scheduledTime: formatToHHmm(scheduledTimeRaw),
      realtimeTime: formatToHHmm(realtimeTimeRaw),
      platform: platformStr,
      operatorName: operatorNameStr,
      destination: destinationStr,
      platformChanged: platformChanged,
      status: getStatus(),
      serviceType: asString(
        schedule['modeType'] ??
        json['modeType'] ??
        json['serviceType'] ??
        locationDetail['serviceType'],
      ),
      cancelReasonShortText: asString(
        locationDetail['cancelReasonShortText'] ??
        metadata['cancelReasonShortText'] ??
        json['cancelReasonShortText'] ??
        locationDetail['cancelReasonText'],
      ),
      cancelReasonLongText: asString(
        locationDetail['cancelReasonLongText'] ??
        metadata['cancelReasonLongText'] ??
        json['cancelReasonLongText'],
      ),
    );
  }
}

