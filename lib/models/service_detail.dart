import 'package:flutter/foundation.dart';
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
  final String? stockBranding;

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
    this.stockBranding,
  });

  factory ServiceDetail.fromJson(Map<String, dynamic> rawJson) {
    final serviceObj = (rawJson['service'] as Map<String, dynamic>?) ?? {};
    final json = serviceObj.isNotEmpty ? serviceObj : rawJson;

    final schedule = (json['scheduleMetadata'] as Map<String, dynamic>?) ??
        (rawJson['scheduleMetadata'] as Map<String, dynamic>?) ??
        {};
    final metadata = (json['metadata'] as Map<String, dynamic>?) ??
        (rawJson['metadata'] as Map<String, dynamic>?) ??
        {};
    final serviceMetadata = (json['serviceMetadata'] as Map<String, dynamic>?) ??
        (rawJson['serviceMetadata'] as Map<String, dynamic>?) ??
        {};
    final operator = schedule['operator'] ?? json['operator'] ?? metadata['operator'];

    final originsData = json['origin'] ?? json['origins'] ?? metadata['origin'] ?? schedule['origin'] ?? rawJson['origin'];
    final destinationsData = json['destination'] ?? json['destinations'] ?? metadata['destination'] ?? schedule['destination'] ?? rawJson['destination'];

    var locationsList = json['locations'] as List? ??
        json['callingPoints'] as List? ??
        json['stops'] as List? ??
        rawJson['locations'] as List? ??
        [];
    List<CallingPoint> locations = locationsList
        .whereType<Map<String, dynamic>>()
        .map((i) => CallingPoint.fromJson(i))
        .toList();

    var originStr = parseLocationDescription(originsData);
    var destinationStr = parseLocationDescription(destinationsData);

    if (originStr == 'Unknown' && locations.isNotEmpty) {
      originStr = locations.first.locationName ?? 'Unknown Origin';
    }
    if (destinationStr == 'Unknown' && locations.isNotEmpty) {
      destinationStr = locations.last.locationName ?? 'Unknown Destination';
    }

    final serviceUidStr = parseServiceUid(json, schedule, metadata);

    debugPrint('[ServiceDetail.fromJson] Parsing ServiceDetail JSON...');
    debugPrint('[ServiceDetail.fromJson] rawJson top-level keys: ${rawJson.keys.toList()}');
    if (serviceObj.isNotEmpty) {
      debugPrint('[ServiceDetail.fromJson] serviceObj keys: ${serviceObj.keys.toList()}');
    }
    debugPrint('[ServiceDetail.fromJson] parsed serviceUidStr: "$serviceUidStr"');

    final trainIdentityStr = parseTrainReportingIdentity(
      rawJson: rawJson,
      serviceObj: serviceObj,
      schedule: schedule,
      metadata: metadata,
      serviceMetadata: serviceMetadata,
      serviceUidStr: serviceUidStr,
    );

    if (trainIdentityStr.isNotEmpty) {
      debugPrint('[ServiceDetail.fromJson] -> ACCEPTED trainIdentity (Head Code): "$trainIdentityStr"');
    } else {
      debugPrint('[ServiceDetail.fromJson] No valid Head Code (trainReportingIdentity) found.');
    }

    final coachCountVal = parseCoachCountFromService(
      json: json,
      schedule: schedule,
      metadata: metadata,
      locationsList: locationsList,
    ) ?? (locations.isNotEmpty
        ? locations.firstWhere((l) => l.coachCount != null, orElse: () => locations.first).coachCount
        : null);

    final stockBrandingVal = parseStockBrandingFromService(
      json: json,
      schedule: schedule,
      metadata: metadata,
      serviceMetadata: serviceMetadata,
      locationsList: locationsList,
    ) ?? (locations.isNotEmpty
        ? locations.firstWhere((l) => l.stockBranding != null && l.stockBranding!.isNotEmpty, orElse: () => locations.first).stockBranding
        : null);

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
      stockBranding: stockBrandingVal,
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
  final bool platformChanged;
  final String? serviceLocation;
  final int departureLateness;
  final bool hasActualReport;
  final int? coachCount;
  final String? stockBranding;

  CallingPoint({
    required this.locationName,
    required this.crs,
    required this.gbttBookedArrival,
    required this.realtimeArrival,
    required this.gbttBookedDeparture,
    required this.realtimeDeparture,
    required this.platform,
    this.platformChanged = false,
    required this.serviceLocation,
    required this.departureLateness,
    this.hasActualReport = false,
    this.coachCount,
    this.stockBranding,
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
    final platformChanged = parsePlatformChanged(
      platformRaw,
      locationDetail['platformChanged'] ?? locationMetadata['platform']?['changed'] ?? json['platformChanged'],
    );

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
      json['status'] ??
      temporal['status'] ??
      locationDetail['status'] ??
      locationMetadata['status'] ??
      temporal['displayAs'] ??
      temporal['serviceLocation'] ??
      locationDetail['serviceLocation'] ??
      json['displayAs'] ??
      json['serviceLocation']
    );

    final callingPointCoachCount = parseCoachCount(
      json['numberOfVehicles'] ?? json['length'] ?? json['coaches'] ?? json['formation'],
      locationMetadata['numberOfVehicles'] ?? locationMetadata['length'] ?? locationMetadata['coaches'],
      locationDetail['numberOfVehicles'] ?? temporal['numberOfVehicles'] ?? geo['numberOfVehicles'],
    );

    final callingPointStockBranding = parseStockBranding(
      json['stockBranding'] ?? json['stock'] ?? json['formation'],
      locationMetadata['stockBranding'] ?? locationMetadata['stock'] ?? locationMetadata['formation'],
      locationDetail['stockBranding'] ?? locationDetail['stock'] ?? locationDetail['formation'],
      temporal['stockBranding'] ?? temporal['stock'] ?? temporal['formation'],
    );

    return CallingPoint(
      locationName: locationDesc != 'Unknown' ? locationDesc : null,
      crs: crsCode,
      gbttBookedArrival: formatToHHmm(schedArr),
      realtimeArrival: formatToHHmm(realArr),
      gbttBookedDeparture: formatToHHmm(schedDep),
      realtimeDeparture: formatToHHmm(realDep),
      platform: platformStr,
      platformChanged: platformChanged,
      serviceLocation: isPassPoint ? 'PASS' : displayAsStr,
      departureLateness: int.tryParse(asString(lateness) ?? '0') ?? 0,
      hasActualReport: hasActual,
      coachCount: callingPointCoachCount,
      stockBranding: callingPointStockBranding,
    );
  }
}


