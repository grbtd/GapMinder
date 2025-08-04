// Represents a single train station
class Station {
  final String name;
  final String crsCode;
  final double latitude;
  final double longitude;
  double distance;

  Station({
    required this.name,
    required this.crsCode,
    required this.latitude,
    required this.longitude,
    this.distance = 0.0,
  });

  factory Station.fromJson(Map<String, dynamic> json) {
    return Station(
      name: json['station_name'] ?? 'Unknown Station',
      crsCode: json['3alpha'] ?? 'N/A',
      latitude: double.tryParse(json['latitude']?.toString() ?? '') ?? 0.0,
      longitude: double.tryParse(json['longitude']?.toString() ?? '') ?? 0.0,
    );
  }
}
