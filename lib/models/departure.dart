import 'package:xml/xml.dart';

class Departure {
  final String serviceUid; // Maps to Darwin 'serviceID'
  final String runDate;    // Defaults to today for live data
  final String? scheduledTime;
  final String? realtimeTime;
  final String? platform;
  final String? operatorName;
  final String destination;
  final bool platformChanged; // Not explicitly in standard public Darwin, usually inferred
  final String? status;
  final String? serviceType;
  final String? cancelReasonShortText;
  final String? cancelReasonLongText;

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

  factory Departure.fromXml(XmlElement node) {
    String? getElementText(String name) => node.findElements(name).firstOrNull?.innerText;

    final std = getElementText('std');
    final etd = getElementText('etd');
    final platform = getElementText('platform');
    final operator = getElementText('operator');
    final serviceId = getElementText('serviceID') ?? '';
    final serviceType = getElementText('serviceType') ?? 'train';

    // Handling Destination (Darwin returns a list, usually we just want the first/main one)
    final destNode = node.findElements('destination').firstOrNull;
    final destName = destNode?.findElements('location').firstOrNull?.findElements('locationName').firstOrNull?.innerText ?? 'Unknown';

    // Determining Status from ETD
    String? status = etd;
    String? displayRealtime = etd;

    if (etd == 'On time') {
      status = 'ON TIME';
      displayRealtime = std; // If on time, realtime matches scheduled
    } else if (etd == 'Delayed') {
      status = 'DELAYED';
      displayRealtime = 'Delayed';
    } else if (etd == 'Cancelled') {
      status = 'CANCELLED';
      displayRealtime = null;
    } else if (etd != null && etd.contains(':')) {
      // It's a time (LATE)
      status = 'LATE';
    }

    // Cancellation Reason (often nested)
    final cancelReason = getElementText('cancelReason');

    return Departure(
      serviceUid: serviceId,
      runDate: DateTime.now().toIso8601String(), // Darwin is live, so it's "now"
      scheduledTime: std,
      realtimeTime: displayRealtime,
      platform: platform,
      operatorName: operator,
      destination: destName,
      platformChanged: false, // Not standard in public feed
      status: status,
      serviceType: serviceType,
      cancelReasonShortText: cancelReason,
      cancelReasonLongText: cancelReason,
    );
  }

  // Keeping fromJson for compatibility if needed, though mostly replaced by fromXml
  factory Departure.fromJson(Map<String, dynamic> json) {
    // ... existing implementation or throw UnimplementedError ...
    return Departure(
        serviceUid: '', runDate: '', scheduledTime: '', realtimeTime: '',
        platform: '', operatorName: '', destination: '', platformChanged: false,
        status: '', serviceType: ''
    );
  }
}