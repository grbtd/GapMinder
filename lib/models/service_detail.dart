import 'package:xml/xml.dart';

class ServiceDetail {
  final String serviceUid;
  final String? runDate;
  final String trainIdentity;
  final String atocName;
  final String origin;
  final String? originTime;
  final String destination;
  final List<CallingPoint> locations;

  ServiceDetail({
    required this.serviceUid,
    required this.runDate,
    required this.trainIdentity,
    required this.atocName,
    required this.origin,
    required this.originTime,
    required this.destination,
    required this.locations,
  });

  factory ServiceDetail.fromXml(XmlElement node) {
    String? getVal(String name) => node.findElements(name).firstOrNull?.innerText;

    final serviceId = getVal('serviceID') ?? 'UNKNOWN';
    final operator = getVal('operator') ?? 'Unknown Operator';

    // Darwin doesn't always provide simple Origin/Dest fields in Details, 
    // usually you infer them from the calling points list.
    // However, they are often wrapped in specific blocks.

    final locations = <CallingPoint>[];

    // Helper to parse calling point lists
    void parsePoints(String listName) {
      final listNode = node.findElements(listName).firstOrNull;
      final points = listNode?.findAllElements('callingPoint') ?? [];

      for (var p in points) {
        locations.add(CallingPoint.fromXml(p));
      }
    }

    parsePoints('previousCallingPoints');
    parsePoints('subsequentCallingPoints');

    final origin = locations.isNotEmpty ? locations.first.locationName : 'Unknown';
    final destination = locations.isNotEmpty ? locations.last.locationName : 'Unknown';
    final originTime = locations.isNotEmpty ? locations.first.gbttBookedDeparture : null;

    return ServiceDetail(
      serviceUid: serviceId,
      runDate: DateTime.now().toIso8601String(),
      trainIdentity: '', // Darwin public often omits Headcode (trainIdentity)
      atocName: operator,
      origin: origin ?? 'Unknown',
      originTime: originTime,
      destination: destination ?? 'Unknown',
      locations: locations,
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
  });

  factory CallingPoint.fromXml(XmlElement node) {
    String? getVal(String name) => node.findElements(name).firstOrNull?.innerText;

    final st = getVal('st'); // Scheduled Time (used for arr or dep depending on context)
    final et = getVal('et'); // Estimated Time
    final at = getVal('at'); // Actual Time

    return CallingPoint(
      locationName: getVal('locationName'),
      crs: getVal('crs'),
      gbttBookedArrival: st, // Simplified mapping
      realtimeArrival: at ?? et,
      gbttBookedDeparture: st,
      realtimeDeparture: at ?? et,
      platform: getVal('platform'),
      serviceLocation: null,
      departureLateness: 0, // Would need calculation comparing st and et
    );
  }
}