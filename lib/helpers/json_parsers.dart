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
  if (platformChangedFallback == true ||
      platformChangedFallback == 'true' ||
      platformChangedFallback == '1' ||
      platformChangedFallback == 1) {
    return true;
  }
  if (platformData is Map) {
    final changedVal = platformData['changed'];
    if (changedVal == true || changedVal == 'true' || changedVal == '1' || changedVal == 1) {
      return true;
    }
    final planned = platformData['planned']?.toString().trim().toLowerCase();
    final actual = platformData['actual']?.toString().trim().toLowerCase();
    if (planned != null && planned.isNotEmpty &&
        actual != null && actual.isNotEmpty &&
        planned != actual) {
      return true;
    }
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
      final val = data['numberOfVehicles'] ?? data['length'] ?? data['coaches'] ?? data['coachCount'] ?? data['carriages'] ?? data['count'];
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

String parseTrainReportingIdentity({
  required Map<String, dynamic> rawJson,
  required Map<String, dynamic> serviceObj,
  required Map<String, dynamic> schedule,
  required Map<String, dynamic> metadata,
  required Map<String, dynamic> serviceMetadata,
  required String serviceUidStr,
}) {
  final candidates = [
    // 1. Explicit trainReportingIdentity
    schedule['trainReportingIdentity'],
    serviceObj['trainReportingIdentity'],
    rawJson['trainReportingIdentity'],
    metadata['trainReportingIdentity'],
    serviceMetadata['trainReportingIdentity'],
    // 2. Explicit headcode
    schedule['headcode'],
    serviceObj['headcode'],
    rawJson['headcode'],
    metadata['headcode'],
    serviceMetadata['headcode'],
    // 3. trainIdentity
    schedule['trainIdentity'],
    serviceObj['trainIdentity'],
    rawJson['trainIdentity'],
    metadata['trainIdentity'],
    serviceMetadata['trainIdentity'],
    // 4. identity fallback
    schedule['identity'],
    serviceObj['identity'],
    rawJson['identity'],
    metadata['identity'],
    serviceMetadata['identity'],
  ];

  for (final candidate in candidates) {
    final str = asString(candidate);
    if (str == null || str.isEmpty) continue;

    // Reject namespace prefixes or colons
    if (str.startsWith('gb-nr:') || str.contains(':')) continue;

    // Reject any string that is part of the service UID (such as schedule identity UID "L79447" in "gb-nr:L79447:2026-07-22")
    if (serviceUidStr.isNotEmpty && (serviceUidStr == str || serviceUidStr.contains(str))) {
      continue;
    }

    return str;
  }

  return '';
}

int? parseCoachCountFromService({
  required Map<String, dynamic> json,
  required Map<String, dynamic> schedule,
  required Map<String, dynamic> metadata,
  required List<dynamic> locationsList,
}) {
  int? coachCount = parseCoachCount(
    json['numberOfVehicles'] ?? json['length'] ?? json['coaches'] ?? json['formation'] ?? json['trainLength'],
    schedule['numberOfVehicles'] ?? schedule['length'] ?? schedule['coaches'] ?? schedule['formation'] ?? schedule['coachCount'],
    metadata['numberOfVehicles'] ?? metadata['length'] ?? metadata['coaches'] ?? metadata['formation'],
  );

  if (coachCount == null) {
    for (final loc in locationsList) {
      if (loc is Map<String, dynamic>) {
        final temp = (loc['temporalData'] as Map<String, dynamic>?) ?? {};
        final locMeta = (loc['locationMetadata'] as Map<String, dynamic>?) ?? {};
        final locDetail = (loc['locationDetail'] as Map<String, dynamic>?) ?? {};
        final geo = (loc['location'] as Map<String, dynamic>?) ?? {};
        final found = parseCoachCount(
          loc['numberOfVehicles'] ?? loc['length'] ?? loc['coaches'] ?? loc['formation'],
          temp['numberOfVehicles'] ?? temp['length'] ?? temp['coaches'],
          locMeta['numberOfVehicles'] ?? locMeta['length'] ?? locMeta['coaches'] ?? locDetail['numberOfVehicles'] ?? geo['numberOfVehicles'],
        );
        if (found != null) {
          coachCount = found;
          break;
        }
      }
    }
  }
  return coachCount;
}

