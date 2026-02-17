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

  factory Departure.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> locationDetail =
        json['locationDetail'] ?? <String, dynamic>{};

    String? getStatus() {
      if (locationDetail['displayAs'] == 'CANCELLED_CALL') {
        return 'CANCELLED';
      }

      // Prioritise serviceLocation as it contains specific statuses like AT_PLAT
      final serviceLocation = locationDetail['serviceLocation'];
      if (serviceLocation != null && (serviceLocation as String).isNotEmpty) {
        return serviceLocation;
      }

      final realtime = locationDetail['realtimeDeparture'];
      final scheduled = locationDetail['gbttBookedDeparture'];

      if (realtime != null && scheduled != null) {
        if (realtime != scheduled) {
          return 'LATE';
        } else {
          return 'ON TIME';
        }
      }

      if (json['trainStatus'] == 'LATE') {
        return 'LATE';
      }

      return null;
    }

    return Departure(
      serviceUid: json['serviceUid'] ?? '',
      runDate: json['runDate'] ?? '',
      scheduledTime: locationDetail['gbttBookedDeparture'],
      realtimeTime: locationDetail['realtimeDeparture'],
      platform: locationDetail['platform'],
      operatorName: json['atocName'],
      destination: locationDetail['destination']?[0]?['description'] ?? 'Unknown',
      platformChanged: locationDetail['platformChanged'] ?? false,
      status: getStatus(),
      serviceType: json['serviceType'],
      cancelReasonShortText: locationDetail['cancelReasonShortText'],
      cancelReasonLongText: locationDetail['cancelReasonLongText'],
    );
  }
}
