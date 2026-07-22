import '../helpers/json_parsers.dart';

class ServiceDetail {
  final String serviceUid;
  final String? runDate;
  final String trainIdentity;
  final String atocName;
  final String origin;
  final String? originTime;
  final String destination;
  final List<CallingPoint> locations;
  final int? coachCount;

  ServiceDetail({
    required this.serviceUid,
    required this.runDate,
    required this.trainIdentity,
    required this.atocName,
    required this.origin,
    required this.originTime,
    required this.destination,
    required this.locations,
    this.coachCount,
  });

  factory ServiceDetail.fromJson(Map<String, dynamic> rawJson) {
    final json = (rawJson['service'] as Map<String, dynamic>?) ?? rawJson;

    final schedule = (json['scheduleMetadata'] as Map<String, dynamic>?) ?? {};
    final metadata = (json['metadata'] as Map<String, dynamic>?) ?? {};
    final operator = schedule['operator'] ?? json['operator'] ?? metadata['operator'];

    final originsData = json['origin'] ?? json['origins'] ?? metadata['origin'] ?? schedule['origin'];
    final destinationsData = json['destination'] ?? json['destinations'] ?? metadata['destination'] ?? schedule['destination'];

    var locationsList = json['locations'] as List? ?? json['callingPoints'] as List? ?? json['stops'] as List? ?? [];
    List<CallingPoint> locations =
        locationsList.map((i) => CallingPoint.fromJson(i as Map<String, dynamic>)).toList();

    var originStr = parseLocationDescription(originsData);
    var destinationStr = parseLocationDescription(destinationsData);

    if (originStr == 'Unknown' && locations.isNotEmpty) {
      originStr = locations.first.locationName ?? 'Unknown Origin';
    }
    if (destinationStr == 'Unknown' && locations.isNotEmpty) {
      destinationStr = locations.last.locationName ?? 'Unknown Destination';
    }

    final serviceUidStr = parseServiceUid(json, schedule, metadata);

    final headcode = asString(
      schedule['trainReportingIdentity'] ??
      json['trainReportingIdentity'] ??
      metadata['trainReportingIdentity'] ??
      json['headcode']
    );

    final trainIdentityStr = headcode ??
        asString(
          schedule['identity'] ??
          json['trainIdentity'] ??
          json['identity']
        ) ??
        '';

    int? coachCountVal = parseCoachCount(
      json['length'] ?? json['coaches'] ?? json['formation'] ?? json['trainLength'],
      schedule['length'] ?? schedule['coaches'] ?? schedule['formation'] ?? schedule['coachCount'],
      metadata['length'] ?? metadata['coaches'] ?? metadata['formation'],
    );

    if (coachCountVal == null) {
      for (final loc in locationsList) {
        if (loc is Map<String, dynamic>) {
          final temp = (loc['temporalData'] as Map<String, dynamic>?) ?? {};
          final locMeta = (loc['locationMetadata'] as Map<String, dynamic>?) ?? {};
          final found = parseCoachCount(
            loc['length'] ?? loc['coaches'] ?? loc['formation'],
            temp['length'] ?? temp['coaches'],
            locMeta['length'] ?? locMeta['coaches'],
          );
          if (found != null) {
            coachCountVal = found;
            break;
          }
        }
      }
    }

    return ServiceDetail(
      serviceUid: serviceUidStr.isNotEmpty ? serviceUidStr : 'UNKNOWN',
      runDate: asString(schedule['departureDate'] ?? json['runDate'] ?? json['date']),
      trainIdentity: trainIdentityStr,
      atocName: parseOperatorName(operator, json['atocName'] ?? json['operatorName']) ?? 'Unknown Operator',
      origin: originStr,
      originTime: locations.isNotEmpty ? (locations.first.gbttBookedDeparture ?? locations.first.realtimeDeparture) : null,
      destination: destinationStr,
      locations: locations,
      coachCount: coachCountVal,
    );
  }
}

class CallingPoint {
  final String? locationName;
  final String? crs;
  final String? gbttBookedArrival;
  final String? realtimeArrival;
  final String? gbttBookedDeparture;
  final String? realtimeDeparture;
  final String? platform;
  final String? serviceLocation;
  final int departureLateness;
  final bool hasActualReport;

  CallingPoint({
    required this.locationName,
    required this.crs,
    required this.gbttBookedArrival,
    required this.realtimeArrival,
    required this.gbttBookedDeparture,
    required this.realtimeDeparture,
    required this.platform,
    required this.serviceLocation,
    required this.departureLateness,
    this.hasActualReport = false,
  });

  factory CallingPoint.fromJson(Map<String, dynamic> json) {
    final locationMetadata = (json['locationMetadata'] as Map<String, dynamic>?) ??
        (json['metadata'] as Map<String, dynamic>?) ??
        {};
    final temporal = (json['temporalData'] as Map<String, dynamic>?) ?? {};
    final locationDetail = (json['locationDetail'] as Map<String, dynamic>?) ?? {};
    final geo = (json['location'] as Map<String, dynamic>?) ??
        (json['geographicLocation'] as Map<String, dynamic>?) ??
        (json['station'] as Map<String, dynamic>?) ??
        {};
    
    final arr = (temporal['arrival'] as Map<String, dynamic>?) ?? (json['arrival'] as Map<String, dynamic>?) ?? {};
    final dep = (temporal['departure'] as Map<String, dynamic>?) ?? (json['departure'] as Map<String, dynamic>?) ?? {};
    final pass = (temporal['pass'] as Map<String, dynamic>?) ?? (json['pass'] as Map<String, dynamic>?) ?? {};

    final hasActual = dep['realtimeActual'] != null ||
        arr['realtimeActual'] != null ||
        pass['realtimeActual'] != null ||
        locationDetail['realtimeActual'] != null ||
        json['realtimeActual'] != null;

    final platformRaw = locationMetadata['platform'] ?? json['platform'] ?? locationDetail['platform'];
    final platformStr = parsePlatform(platformRaw);

    final locationDesc = parseLocationDescription(geo.isNotEmpty ? geo : json['description'] ?? json['locationName'] ?? json['name']);

    final crsCode = asString(
      geo['shortCodes']?[0] ??
      geo['crs'] ??
      geo['crsCode'] ??
      json['crs'] ??
      json['crsCode'] ??
      locationDetail['crs']
    );

    final isPassPoint = temporal['displayAs'] == 'PASS' ||
        json['displayAs'] == 'PASS' ||
        pass.isNotEmpty;

    final passSched = pass['scheduleInternal'] ?? pass['scheduleAdvertised'] ?? pass['scheduled'];
    final passReal = pass['realtimeActual'] ?? pass['realtimeForecast'] ?? pass['realtime'];

    final schedArr = isPassPoint
        ? passSched
        : (arr['scheduleAdvertised'] ?? arr['scheduleInternal'] ?? arr['scheduled'] ?? locationDetail['gbttBookedArrival'] ?? json['gbttBookedArrival'] ?? arr['gbtt']);
    final realArr = isPassPoint
        ? passReal
        : (arr['realtimeActual'] ?? arr['realtimeForecast'] ?? arr['realtime'] ?? locationDetail['realtimeArrival'] ?? json['realtimeArrival'] ?? arr['actual']);

    final schedDep = isPassPoint
        ? passSched
        : (dep['scheduleAdvertised'] ?? dep['scheduleInternal'] ?? dep['scheduled'] ?? locationDetail['gbttBookedDeparture'] ?? json['gbttBookedDeparture'] ?? dep['gbtt']);
    final realDep = isPassPoint
        ? passReal
        : (dep['realtimeActual'] ?? dep['realtimeForecast'] ?? dep['realtime'] ?? locationDetail['realtimeDeparture'] ?? json['realtimeDeparture'] ?? dep['actual']);

    final lateness = dep['realtimeAdvertisedLateness'] ??
        arr['realtimeAdvertisedLateness'] ??
        pass['realtimeInternalLateness'] ??
        temporal['realtimeAdvertisedLateness'] ??
        locationDetail['realtimeGbttDepartureLateness'] ??
        json['realtimeGbttDepartureLateness'] ??
        dep['lateness'];

    final displayAsStr = asString(
      temporal['displayAs'] ??
      temporal['serviceLocation'] ??
      locationDetail['serviceLocation'] ??
      json['displayAs'] ??
      json['serviceLocation']
    );

    return CallingPoint(
      locationName: locationDesc != 'Unknown' ? locationDesc : null,
      crs: crsCode,
      gbttBookedArrival: formatToHHmm(schedArr),
      realtimeArrival: formatToHHmm(realArr),
      gbttBookedDeparture: formatToHHmm(schedDep),
      realtimeDeparture: formatToHHmm(realDep),
      platform: platformStr,
      serviceLocation: isPassPoint ? 'PASS' : displayAsStr,
      departureLateness: int.tryParse(asString(lateness) ?? '0') ?? 0,
      hasActualReport: hasActual,
    );
  }
}


