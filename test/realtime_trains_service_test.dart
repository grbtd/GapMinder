import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gapminder/api/realtime_trains_service.dart';
import 'package:gapminder/models/secrets.dart';

void main() {
  group('RealtimeTrainsService Token Exchange', () {
    test('fetches and caches access token from /api/get_access_token', () async {
      int getAccessTokenCalls = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/get_access_token') {
          getAccessTokenCalls++;
          expect(request.headers['Authorization'], 'Bearer secret-user-token');
          return http.Response(
            jsonEncode({
              'accessToken': 'new-access-token-123',
              'validUntil': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
            }),
            200,
          );
        } else if (request.url.path.contains('/location')) {
          expect(request.headers['Authorization'], 'Bearer new-access-token-123');
          return http.Response(jsonEncode({'services': []}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final service = RealtimeTrainsService(
        client: mockClient,
        secretsLoader: () async => Secrets(token: 'secret-user-token'),
      );

      final departures1 = await service.fetchDepartures('WAT');
      expect(departures1, isEmpty);
      expect(getAccessTokenCalls, 1);

      // Second call within expiry should use cached token without calling get_access_token again
      final departures2 = await service.fetchDepartures('WAT');
      expect(departures2, isEmpty);
      expect(getAccessTokenCalls, 1);
    });

    test('refreshes access token automatically on 401 Unauthorized', () async {
      int getAccessTokenCalls = 0;
      int locationCalls = 0;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/get_access_token') {
          getAccessTokenCalls++;
          return http.Response(
            jsonEncode({
              'accessToken': 'token-v$getAccessTokenCalls',
              'expiresIn': 3600,
            }),
            200,
          );
        } else if (request.url.path.contains('/location')) {
          locationCalls++;
          if (request.headers['Authorization'] == 'Bearer token-v1') {
            return http.Response(jsonEncode({'error': 'Token expired'}), 401);
          }
          if (request.headers['Authorization'] == 'Bearer token-v2') {
            return http.Response(jsonEncode({'services': []}), 200);
          }
        }
        return http.Response('Not Found', 404);
      });

      final service = RealtimeTrainsService(
        client: mockClient,
        secretsLoader: () async => Secrets(token: 'secret-user-token'),
      );

      final departures = await service.fetchDepartures('WAT');
      expect(departures, isEmpty);
      expect(getAccessTokenCalls, 2);
      expect(locationCalls, 2);
    });

    test('invokes onProgress callback during fetchDepartures', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/get_access_token') {
          return http.Response(
            jsonEncode({'accessToken': 'test-token', 'expiresIn': 3600}),
            200,
          );
        } else if (request.url.path.contains('/location')) {
          return http.Response(
            jsonEncode({
              'services': [
                {
                  'serviceUid': 'W12345',
                  'runDate': '2026-07-27',
                  'locationDetail': {
                    'destination': [{'description': 'Waterloo'}],
                  },
                }
              ]
            }),
            200,
          );
        } else if (request.url.path.contains('/service')) {
          return http.Response(
            jsonEncode({
              'service': {
                'serviceUid': 'W12345',
                'runDate': '2026-07-27',
                'locations': [
                  {'crs': 'WAT', 'gbttBookedDeparture': '12:00'}
                ]
              }
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = RealtimeTrainsService(
        client: mockClient,
        secretsLoader: () async => Secrets(token: 'secret-user-token'),
      );

      final List<String> progressLogs = [];
      await service.fetchDepartures('WAT', onProgress: (msg) {
        progressLogs.add(msg);
      });

      expect(progressLogs, isNotEmpty);
      expect(progressLogs.first, equals('Fetching departure board...'));
      expect(progressLogs.any((log) => log.contains('Processing services')), isTrue);
    });

    test('selects earlier services when pivotTime is earlier than current time', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/get_access_token') {
          return http.Response(jsonEncode({'accessToken': 'test-token', 'expiresIn': 3600}), 200);
        } else if (request.url.path.contains('/location')) {
          return http.Response(
            jsonEncode({
              'services': [
                {
                  'serviceUid': 'EARLY1',
                  'runDate': '2026-07-27',
                  'locationDetail': {
                    'gbttBookedDeparture': '08:00',
                    'destination': [{'description': 'Waterloo'}],
                  },
                },
                {
                  'serviceUid': 'LATE1',
                  'runDate': '2026-07-27',
                  'locationDetail': {
                    'gbttBookedDeparture': '22:00',
                    'destination': [{'description': 'Portsmouth'}],
                  },
                }
              ]
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = RealtimeTrainsService(
        client: mockClient,
        secretsLoader: () async => Secrets(token: 'secret-user-token'),
      );

      final now = DateTime.now();
      final pastPivot = DateTime(now.year, now.month, now.day, 8, 0);

      final departures = await service.fetchDepartures('WAT', pivotTime: pastPivot);
      expect(departures, isNotEmpty);
      expect(departures.first.serviceUid, equals('EARLY1'));
    });
  });
}


