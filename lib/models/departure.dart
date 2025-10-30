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
  });

  factory Departure.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> locationDetail =
        json['locationDetail'] ?? <String, dynamic>{};

    return Departure(
      serviceUid: json['serviceUid'] ?? '',
      runDate: json['runDate'] ?? '',
      // --- UPDATED KEY ---
      scheduledTime: locationDetail['gbttBookedDeparture'],
      // --- END UPDATED KEY ---
      realtimeTime: locationDetail['realtimeDeparture'],
      platform: locationDetail['platform'],
      operatorName: json['atocName'],
      destination: locationDetail['destination']?[0]?['description'] ?? 'Unknown',
      platformChanged: locationDetail['platformChanged'] ?? false,
      status: locationDetail['serviceLocation'] ?? (json['trainStatus'] == 'LATE' ? 'LATE' : ''),
      serviceType: json['serviceType'],
    );
  }
}

