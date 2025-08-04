// Represents a single departing service in the list
class Departure {
  final String serviceUid;
  final String runDate;
  final String destination;
  final String scheduledTime;
  final String expectedTime;
  final String platform;
  final String operatorName;
  final String? serviceLocation;
  final bool platformChanged;
  final String serviceType;

  Departure({
    required this.serviceUid,
    required this.runDate,
    required this.destination,
    required this.scheduledTime,
    required this.expectedTime,
    required this.platform,
    required this.operatorName,
    this.serviceLocation,
    this.platformChanged = false,
    this.serviceType = 'train',
  });

  factory Departure.fromJson(Map<String, dynamic> json) {
    final locationDetail = json['locationDetail'] as Map<String, dynamic>?;
    String dest = "N/A";

    if (locationDetail != null) {
      final destinationList = locationDetail['destination'];
      if (destinationList is List && destinationList.isNotEmpty) {
        final firstDestination = destinationList.first;
        if (firstDestination is Map<String, dynamic>) {
          dest = firstDestination['description'] ?? "N/A";
        }
      }
    }

    return Departure(
      serviceUid: json['serviceUid'] ?? '',
      runDate: json['runDate'] ?? '',
      destination: dest,
      scheduledTime: locationDetail?['gbttBookedDeparture'] ?? 'N/A',
      expectedTime: locationDetail?['realtimeDeparture'] ?? locationDetail?['gbttBookedDeparture'] ?? 'N/A',
      platform: locationDetail?['platform'] ?? 'TBC',
      operatorName: json['atocName'] ?? 'N/A',
      serviceLocation: locationDetail?['serviceLocation'],
      platformChanged: locationDetail?['platformChanged'] ?? false,
      serviceType: json['serviceType'] ?? 'train',
    );
  }
}
