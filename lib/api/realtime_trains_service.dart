import 'dart:convert';
import 'package:http/http.dart' as http;
import 'secrets_loader.dart';
import '../models/departure.dart';
import '../models/service_detail.dart';

class RealtimeTrainsService {
  late final String _username;
  late final String _password;
  bool _isInitialized = false;

  Future<void> _initialize() async {
    if (_isInitialized) return;
    final secrets = await loadSecrets();
    _username = secrets.username;
    _password = secrets.password;
    _isInitialized = true;
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    await _initialize();
    return {
      'Authorization': 'Basic ${base64Encode(utf8.encode('$_username:$_password'))}'
    };
  }

  Future<List<Departure>> fetchDepartures(String crsCode) async {
    final authority = 'api.rtt.io';
    final path = '/api/v1/json/search/$crsCode';
    final url = Uri.https(authority, path);

    final response = await http.get(
      url,
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> services = data['services'] ?? [];
      return services
          .map((json) => Departure.fromJson(json as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('Failed to load departures: ${response.statusCode}');
    }
  }

  Future<ServiceDetail> fetchServiceDetails(String serviceUid, String runDate) async {
    final formattedDate = runDate.replaceAll('-', '/');
    final authority = 'api.rtt.io';
    final path = '/api/v1/json/service/$serviceUid/$formattedDate';
    final url = Uri.https(authority, path);

    final response = await http.get(
      url,
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return ServiceDetail.fromJson(data);
    } else {
      throw Exception('Failed to load service details: ${response.statusCode}');
    }
  }
}
