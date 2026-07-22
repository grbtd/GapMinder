String parseLocationDescription(dynamic locationData) {
  if (locationData == null) return 'Unknown';
  if (locationData is String && locationData.trim().isNotEmpty) {
    return locationData.trim();
  }
  if (locationData is List && locationData.isNotEmpty) {
    for (final item in locationData) {
      final parsed = parseLocationDescription(item);
      if (parsed != 'Unknown') return parsed;
    }
  }
  if (locationData is Map) {
    final desc = locationData['description'] ??
        locationData['name'] ??
        locationData['locationName'] ??
        locationData['title'] ??
        locationData['location']?['description'] ??
        locationData['location']?['name'] ??
        locationData['geographicLocation']?['description'];
    if (desc != null && desc.toString().trim().isNotEmpty) {
      return desc.toString().trim();
    }
  }
  return 'Unknown';
}

String? parseOperatorName(dynamic operatorData, [dynamic fallbackData]) {
  if (operatorData is String && operatorData.trim().isNotEmpty) return operatorData.trim();
  if (operatorData is Map) {
    final name = operatorData['name'] ?? operatorData['description'] ?? operatorData['title'];
    if (name != null && name.toString().trim().isNotEmpty) return name.toString().trim();
  }
  if (fallbackData != null) {
    return parseOperatorName(fallbackData, null);
  }
  return null;
}

String? asString(dynamic value) {
  if (value == null) return null;
  final str = value.toString().trim();
  return str.isEmpty ? null : str;
}

String parseServiceUid(Map<String, dynamic> json, Map<String, dynamic> schedule, Map<String, dynamic> metadata) {
  final serviceObj = (json['service'] as Map<String, dynamic>?) ?? {};
  final serviceSchedule = (serviceObj['scheduleMetadata'] as Map<String, dynamic>?) ?? schedule;

  final candidate = json['uniqueIdentity'] ??
      json['serviceCode'] ??
      json['serviceKey'] ??
      json['serviceUid'] ??
      json['code'] ??
      json['uid'] ??
      serviceSchedule['uniqueIdentity'] ??
      serviceSchedule['serviceCode'] ??
      serviceSchedule['identity'] ??
      serviceSchedule['code'] ??
      schedule['uniqueIdentity'] ??
      schedule['serviceCode'] ??
      schedule['identity'] ??
      schedule['code'] ??
      metadata['uniqueIdentity'] ??
      metadata['serviceCode'] ??
      metadata['code'];
  return candidate?.toString().trim() ?? '';
}

String? formatToHHmm(dynamic timeVal) {
  if (timeVal == null) return null;
  final timeStr = timeVal.toString().trim();
  if (timeStr.isEmpty) return null;

  final parts = timeStr.split('T');
  final timePart = parts.length > 1 ? parts[1] : parts[0];
  final clean = timePart.replaceAll(':', '').replaceAll('Z', '');
  if (clean.length < 4) return null;
  return clean.substring(0, 4);
}

String? parsePlatform(dynamic platformData) {
  if (platformData == null) return null;
  if (platformData is String && platformData.trim().isNotEmpty) {
    return platformData.trim();
  }
  if (platformData is Map) {
    final val = platformData['actual'] ?? platformData['planned'] ?? platformData['name'] ?? platformData['number'];
    if (val != null && val.toString().trim().isNotEmpty) {
      return val.toString().trim();
    }
  }
  return null;
}

bool parsePlatformChanged(dynamic platformData, dynamic platformChangedFallback) {
  if (platformChangedFallback is bool) return platformChangedFallback;
  if (platformData is Map) {
    if (platformData['changed'] is bool) return platformData['changed'] as bool;
  }
  return false;
}

int? parseCoachCount(dynamic rawData, [dynamic secondaryData, dynamic tertiaryData]) {
  for (final data in [rawData, secondaryData, tertiaryData]) {
    if (data == null) continue;
    if (data is num && data > 0) {
      return data.toInt();
    }
    if (data is String) {
      final match = RegExp(r'\b(\d{1,2})\b').firstMatch(data);
      if (match != null) {
        final val = int.tryParse(match.group(1)!);
        if (val != null && val > 0 && val <= 16) return val;
      }
    }
    if (data is Map) {
      final val = data['length'] ?? data['coaches'] ?? data['coachCount'] ?? data['carriages'] ?? data['count'];
      final parsed = parseCoachCount(val);
      if (parsed != null) return parsed;
    }
    if (data is List && data.isNotEmpty) {
      final val = data.length;
      if (val > 0 && val <= 16) return val;
    }
  }
  return null;
}
