// Represents a single calling point in a train's journey
class CallingPoint {
  final String stationName;
  final String crsCode;
  final bool isCancelled;
  final String? serviceLocation;
  final String platform;
  // **REVISED**: Using specific, nullable time fields for clarity and robustness
  final String? scheduledArrival;
  final String? realtimeArrival;
  final String? scheduledDeparture;
  final String? realtimeDeparture;


  CallingPoint({
    required this.stationName,
    required this.crsCode,
    this.isCancelled = false,
    this.serviceLocation,
    this.platform = 'N/A',
    this.scheduledArrival,
    this.realtimeArrival,
    this.scheduledDeparture,
    this.realtimeDeparture,
  });

  factory CallingPoint.fromJson(Map<String, dynamic> json) {
    return CallingPoint(
      stationName: json['description'] ?? 'N/A',
      crsCode: json['crs'] ?? 'N/A',
      isCancelled: json['isCancelled'] ?? false,
      serviceLocation: json['serviceLocation'],
      platform: json['platform'] ?? 'TBC',
      // **REVISED**: Parsing specific time fields directly from the JSON
      scheduledArrival: json['gbttBookedArrival'],
      realtimeArrival: json['realtimeArrival'],
      scheduledDeparture: json['gbttBookedDeparture'],
      realtimeDeparture: json['realtimeDeparture'],
    );
  }
}

// Represents the full details of a selected service
class ServiceDetail {
  final String trainIdentity;
  final String runDate;
  final List<CallingPoint> locations;
  final String atocName;
  final String origin;
  final String destination;

  ServiceDetail({
    required this.trainIdentity,
    required this.runDate,
    required this.locations,
    required this.atocName,
    required this.origin,
    required this.destination,
  });

  factory ServiceDetail.fromJson(Map<String, dynamic> json) {
    final List<CallingPoint> validLocations = [];
    if (json['locations'] is List) {
      for (final loc in json['locations']) {
        if (loc is Map<String, dynamic>) {
          validLocations.add(CallingPoint.fromJson(loc));
        }
      }
    }

    String originName = "N/A";
    if (validLocations.isNotEmpty) {
      originName = validLocations.first.stationName;
    }

    String destinationName = "N/A";
    if (validLocations.isNotEmpty) {
      destinationName = validLocations.last.stationName;
    }

    return ServiceDetail(
      trainIdentity: json['trainIdentity'] ?? 'N/A',
      runDate: json['runDate'] ?? '',
      locations: validLocations,
      atocName: json['atocName'] ?? 'Unknown Operator',
      origin: originName,
      destination: destinationName,
    );
  }
}
