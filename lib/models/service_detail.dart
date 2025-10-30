class ServiceDetail {
  final String serviceUid;
  final String? runDate;
  final String trainIdentity;
  final String atocName;
  final String origin;
  final String? originTime; // <-- ADDED
  final String destination;
  final List<CallingPoint> locations;

  ServiceDetail({
    required this.serviceUid,
    required this.runDate,
    required this.trainIdentity,
    required this.atocName,
    required this.origin,
    required this.originTime, // <-- ADDED
    required this.destination,
    required this.locations,
  });

  // Helper function to safely convert JSON values to String?
  static String? _asString(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }

  factory ServiceDetail.fromJson(Map<String, dynamic> json) {
    var locationsList = json['locations'] as List;
    List<CallingPoint> locations =
    locationsList.map((i) => CallingPoint.fromJson(i)).toList();

    return ServiceDetail(
      serviceUid: _asString(json['serviceUid']) ?? 'UNKNOWN',
      runDate: _asString(json['runDate']),
      trainIdentity: _asString(json['trainIdentity']) ?? '',
      atocName: _asString(json['atocName']) ?? 'Unknown Operator',
      origin: json['origin']?[0]?['description'] ?? 'Unknown Origin',
      // --- ADDED ---
      originTime: locations.isNotEmpty ? locations.first.gbttBookedDeparture : null,
      // --- END ADDED ---
      destination: json['destination']?[0]?['description'] ?? 'Unknown Destination',
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

  // Helper function to safely convert JSON values to String?
  static String? _asString(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }

  factory CallingPoint.fromJson(Map<String, dynamic> json) {
    return CallingPoint(
      locationName: _asString(json['locationName'] ?? json['description']),
      crs: _asString(json['crs']),
      gbttBookedArrival: _asString(json['gbttBookedArrival']),
      realtimeArrival: _asString(json['realtimeArrival']),
      gbttBookedDeparture: _asString(json['gbttBookedDeparture']),
      realtimeDeparture: _asString(json['realtimeDeparture']),
      platform: _asString(json['platform']),
      serviceLocation: _asString(json['serviceLocation']),
      departureLateness: int.tryParse(_asString(json['realtimeGbttDepartureLateness']) ?? '0') ?? 0,
    );
  }
}

