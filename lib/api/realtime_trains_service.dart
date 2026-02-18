import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'secrets_loader.dart';
import '../models/departure.dart';
import '../models/service_detail.dart';

class RealtimeTrainsService {
  late final String _apiKey;
  bool _isInitialized = false;

  // --- STABLE CONFIGURATION (DO NOT CHANGE) ---
  // We use ldb11 + 2017-10-01 because 'GetDepBoardWithDetails'
  // is natively defined here. Newer endpoints often fail to map the Action correctly.
  static const String _authority = 'lite.realtime.nationalrail.co.uk';
  static const String _path = '/OpenLDBWS/ldb11.asmx';
  static const String _ldbNamespace = 'http://thalesgroup.com/RTTI/2017-10-01/ldb/';
  static const String _tokenNamespace = 'http://thalesgroup.com/RTTI/2013-11-28/Token/types';
  // --------------------------------------------

  Future<void> _initialize() async {
    if (_isInitialized) return;
    final secrets = await loadSecrets();
    _apiKey = secrets.apiKey;
    _isInitialized = true;
  }

  /// Helper to send a SOAP 1.1 Request (Most Compatible)
  Future<XmlDocument> _sendSoapRequest(String actionName, String bodyContent) async {
    await _initialize();

    // SOAP 1.1 Action: Strictly Namespace + Operation Name
    final soapAction = '$_ldbNamespace$actionName';

    // SOAP 1.1 Envelope
    // uses "http://schemas.xmlsoap.org/soap/envelope/"
    final envelope = '''<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:typ="$_tokenNamespace" xmlns:ldb="$_ldbNamespace">
  <soap:Header>
    <typ:AccessToken>
      <typ:TokenValue>$_apiKey</typ:TokenValue>
    </typ:AccessToken>
  </soap:Header>
  <soap:Body>
    $bodyContent
  </soap:Body>
</soap:Envelope>''';

    final url = Uri.https(_authority, _path);

    try {
      final response = await http.post(
        url,
        headers: {
          // SOAP 1.1 Headers
          'Content-Type': 'text/xml; charset=utf-8',
          'SOAPAction': soapAction,
          'User-Agent': 'Dart/3.0 (Flutter)',
        },
        body: envelope,
      );

      if (response.statusCode == 200) {
        return XmlDocument.parse(response.body);
      } else {
        print('CRITICAL API ERROR: ${response.statusCode}');
        print('Response Body: ${response.body}');
        print('Attempted Action: $soapAction');
        throw Exception('Darwin API Error ${response.statusCode}');
      }
    } catch (e) {
      print('NETWORK ERROR: $e');
      rethrow;
    }
  }

  Future<List<Departure>> fetchDepartures(String crsCode) async {
    // Note: older namespaces use 'numRows' (camelCase)
    final body = '''
    <ldb:GetDepBoardWithDetails>
      <ldb:numRows>10</ldb:numRows>
      <ldb:crs>$crsCode</ldb:crs>
      <ldb:filterType>to</ldb:filterType>
      <ldb:timeOffset>0</ldb:timeOffset>
      <ldb:timeWindow>120</ldb:timeWindow>
    </ldb:GetDepBoardWithDetails>
    ''';

    final document = await _sendSoapRequest('GetDepBoardWithDetails', body);

    // In ldb11/2017, the wrapper is often just <service> inside <GetStationBoardResult>
    final services = document.findAllElements('service');
    return services.map((node) => Departure.fromXml(node)).toList();
  }

  Future<ServiceDetail> fetchServiceDetails(String serviceId, String runDate) async {
    final body = '''
    <ldb:GetServiceDetails>
      <ldb:serviceID>$serviceId</ldb:serviceID>
    </ldb:GetServiceDetails>
    ''';

    final document = await _sendSoapRequest('GetServiceDetails', body);

    final serviceDetailsNode = document.findAllElements('GetServiceDetailsResult').firstOrNull;

    if (serviceDetailsNode == null) {
      // Sometimes Darwin returns 200 OK but with a null result if the ID is expired
      print('WARNING: API returned 200 but GetServiceDetailsResult was empty/null.');
      throw Exception('Service details not found (ID may be expired).');
    }

    return ServiceDetail.fromXml(serviceDetailsNode);
  }
}