import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gapminder/models/departure.dart';
import 'package:gapminder/models/service_detail.dart';

void main() {
  group('Departure.fromJson', () {
    test('should parse rtt-ng location search JSON correctly', () {
      final jsonStr = '''
      {
        "metadata": {
          "destination": [{"description": "London Waterloo"}],
          "platform": {"planned": "12", "changed": false},
          "displayAs": "CALL"
        },
        "scheduleMetadata": {
          "uniqueIdentity": "gb-nr:W12345:2025-10-26",
          "departureDate": "2025-10-26",
          "operator": {"name": "South Western Railway"},
          "modeType": "TRAIN"
        },
        "temporalData": {
          "departure": {"scheduled": "10:15:00", "realtimeForecast": "10:17:00"},
          "realtimeAdvertisedLateness": 2
        }
      }
      ''';
      final json = jsonDecode(jsonStr);
      final departure = Departure.fromJson(json);

      expect(departure.serviceUid, "gb-nr:W12345:2025-10-26");
      expect(departure.destination, "London Waterloo");
      expect(departure.scheduledTime, "1015");
      expect(departure.realtimeTime, "1017");
      expect(departure.platform, "12");
      expect(departure.status, "LATE");
      expect(departure.operatorName, "South Western Railway");
    });

    test('should handle early trains', () {
      final jsonStr = '''
      {
        "metadata": {"destination": [{"description": "Reading"}]},
        "scheduleMetadata": {},
        "temporalData": {
          "departure": {"scheduled": "10:15:00", "realtimeForecast": "10:13:00"},
          "realtimeAdvertisedLateness": -2
        }
      }
      ''';
      final json = jsonDecode(jsonStr);
      final departure = Departure.fromJson(json);
      expect(departure.status, "EARLY");
    });

    test('should prioritize serviceLocation and prefer actual platform over planned', () {
      final jsonStr = '''
      {
        "metadata": {
          "destination": [{"description": "Basingstoke"}],
          "platform": {"planned": "3", "actual": "5", "changed": true},
          "serviceLocation": "AT_PLAT",
          "displayAs": "CALL"
        },
        "scheduleMetadata": {
          "uniqueIdentity": "gb-nr:B98765:2025-10-26"
        },
        "temporalData": {
          "departure": {"scheduled": "12:00:00"},
          "realtimeAdvertisedLateness": 0
        }
      }
      ''';
      final json = jsonDecode(jsonStr);
      final departure = Departure.fromJson(json);
      expect(departure.platform, "5");
      expect(departure.platformChanged, true);
      expect(departure.status, "AT_PLAT");
    });

    test('should detect platformChanged when locationMetadata planned and actual platforms differ', () {
      final jsonStr = '''
      {
        "locationMetadata": {
          "destination": [{"description": "Southampton Central"}],
          "platform": {
            "planned": "2",
            "actual": "3"
          }
        },
        "scheduleMetadata": {
          "uniqueIdentity": "gb-nr:S12345:2026-07-28"
        }
      }
      ''';
      final json = jsonDecode(jsonStr);
      final departure = Departure.fromJson(json);
      expect(departure.platform, "3");
      expect(departure.platformChanged, true);
    });

    test('should not mark platformChanged when locationMetadata planned and actual platforms match', () {
      final jsonStr = '''
      {
        "locationMetadata": {
          "destination": [{"description": "Southampton Central"}],
          "platform": {
            "planned": "2",
            "actual": "2"
          }
        },
        "scheduleMetadata": {
          "uniqueIdentity": "gb-nr:S12345:2026-07-28"
        }
      }
      ''';
      final json = jsonDecode(jsonStr);
      final departure = Departure.fromJson(json);
      expect(departure.platform, "2");
      expect(departure.platformChanged, false);
    });

    test('should handle cancelled service displayAs', () {
      final jsonStr = '''
      {
        "metadata": {
          "destination": [{"description": "Salisbury"}],
          "displayAs": "CANCELLED_CALL",
          "cancelReasonShortText": "Signal failure"
        },
        "scheduleMetadata": {
          "uniqueIdentity": "gb-nr:C11111:2025-10-26"
        }
      }
      ''';
      final json = jsonDecode(jsonStr);
      final departure = Departure.fromJson(json);
      expect(departure.status, "CANCELLED");
      expect(departure.cancelReasonShortText, "Signal failure");
    });

    test('should parse service code and operator from flat/alternative JSON fields', () {
      final jsonStr = '''
      {
        "serviceCode": "W99999",
        "date": "2026-07-22",
        "destination": {"name": "Portsmouth Harbour"},
        "operator": "Great Western Railway",
        "departure": {"scheduled": "14:30:00"}
      }
      ''';
      final json = jsonDecode(jsonStr);
      final departure = Departure.fromJson(json);
      expect(departure.serviceUid, "W99999");
      expect(departure.destination, "Portsmouth Harbour");
      expect(departure.operatorName, "Great Western Railway");
      expect(departure.scheduledTime, "1430");
    });

    test('should parse RTT locationDetail payload format correctly', () {
      final jsonStr = '''
      {
        "serviceUid": "W88888",
        "runDate": "2026-07-22",
        "atocName": "South Western Railway",
        "locationDetail": {
          "gbttBookedDeparture": "1745",
          "realtimeDeparture": "1747",
          "platform": "4",
          "platformChanged": false,
          "destination": [{"description": "Weymouth"}],
          "serviceLocation": "AT_PLAT"
        }
      }
      ''';
      final json = jsonDecode(jsonStr);
      final departure = Departure.fromJson(json);

      expect(departure.serviceUid, "W88888");
      expect(departure.scheduledTime, "1745");
      expect(departure.realtimeTime, "1747");
      expect(departure.platform, "4");
      expect(departure.destination, "Weymouth");
      expect(departure.operatorName, "South Western Railway");
      expect(departure.status, "AT_PLAT");
    });
  });

  group('ServiceDetail.fromJson', () {
    test('should parse rtt-ng service detail JSON correctly', () {
      final jsonStr = '''
      {
        "scheduleMetadata": {
          "uniqueIdentity": "gb-nr:W12345:2025-10-26",
          "departureDate": "2025-10-26",
          "identity": "1W45",
          "operator": {"name": "South Western Railway"}
        },
        "origin": [{"description": "Exeter St Davids"}],
        "destination": [{"description": "London Waterloo"}],
        "locations": [
          {
            "geographicLocation": {"description": "Exeter St Davids", "shortCodes": ["EXD"]},
            "temporalData": {"departure": {"scheduled": "08:00:00"}},
            "metadata": {"platform": {"planned": "1"}}
          },
          {
            "geographicLocation": {"description": "London Waterloo", "shortCodes": ["WAT"]},
            "temporalData": {"arrival": {"scheduled": "11:30:00", "realtimeActual": "11:32:00"}},
            "metadata": {"platform": {"planned": "12"}}
          }
        ]
      }
      ''';
      final json = jsonDecode(jsonStr);
      final detail = ServiceDetail.fromJson(json);

      expect(detail.serviceUid, "gb-nr:W12345:2025-10-26");
      expect(detail.origin, "Exeter St Davids");
      expect(detail.destination, "London Waterloo");
      expect(detail.locations.length, 2);
      expect(detail.locations[1].locationName, "London Waterloo");
      expect(detail.locations[1].realtimeArrival, "1132");
    });

    test('should parse RTT-NG wrapped service object with locationMetadata correctly', () {
      final jsonStr = '''
      {
        "query": { "uniqueIdentity": "gb-nr:L79447:2026-07-22" },
        "service": {
          "scheduleMetadata": {
            "uniqueIdentity": "gb-nr:L79447:2026-07-22",
            "departureDate": "2026-07-22",
            "operator": { "code": "SW", "name": "South Western Railway" }
          },
          "origin": [{ "location": { "description": "Exeter Central" } }],
          "destination": [{ "location": { "description": "London Waterloo" } }],
          "locations": [
            {
              "location": { "description": "Exeter Central", "shortCodes": ["EXC"] },
              "locationMetadata": { "platform": { "planned": "3", "actual": "1" } },
              "temporalData": {
                "arrival": { "scheduleAdvertised": "2026-07-22T15:28:00", "realtimeActual": "2026-07-22T15:36:00" },
                "departure": { "scheduleAdvertised": "2026-07-22T15:30:00", "realtimeActual": "2026-07-22T15:36:00" }
              }
            }
          ]
        }
      }
      ''';
      final json = jsonDecode(jsonStr);
      final detail = ServiceDetail.fromJson(json);

      expect(detail.serviceUid, "gb-nr:L79447:2026-07-22");
      expect(detail.origin, "Exeter Central");
      expect(detail.destination, "London Waterloo");
      expect(detail.atocName, "South Western Railway");
      expect(detail.locations.length, 1);
      expect(detail.locations[0].locationName, "Exeter Central");
      expect(detail.locations[0].crs, "EXC");
      expect(detail.locations[0].platform, "1");
      expect(detail.locations[0].gbttBookedDeparture, "1530");
      expect(detail.locations[0].realtimeDeparture, "1536");
    });

    test('should fallback origin and destination from calling points when root arrays are missing', () {
      final jsonStr = '''
      {
        "code": "G12345",
        "atocName": "CrossCountry",
        "locations": [
          {
            "locationName": "Birmingham New Street",
            "crs": "BHM",
            "gbttBookedDeparture": "09:00:00"
          },
          {
            "locationName": "Manchester Piccadilly",
            "crs": "MAN",
            "gbttBookedArrival": "10:30:00"
          }
        ]
      }
      ''';
      final json = jsonDecode(jsonStr);
      final detail = ServiceDetail.fromJson(json);

      expect(detail.serviceUid, "G12345");
      expect(detail.atocName, "CrossCountry");
      expect(detail.origin, "Birmingham New Street");
      expect(detail.destination, "Manchester Piccadilly");
    });

    test('should parse trainReportingIdentity correctly and not use serviceUid as headcode', () {
      final jsonStr = '''
      {
        "query": { "uniqueIdentity": "gb-nr:W12345:2026-07-23" },
        "service": {
          "trainReportingIdentity": "1A23",
          "scheduleMetadata": {
            "uniqueIdentity": "gb-nr:W12345:2026-07-23",
            "identity": "gb-nr:W12345:2026-07-23"
          },
          "origin": [{ "description": "London Waterloo" }],
          "destination": [{ "description": "Exeter St Davids" }]
        }
      }
      ''';
      final json = jsonDecode(jsonStr);
      final detail = ServiceDetail.fromJson(json);

      expect(detail.serviceUid, "gb-nr:W12345:2026-07-23");
      expect(detail.trainIdentity, "1A23");
    });

    test('should parse trainReportingIdentity 1L60 from scheduleMetadata in RTT-NG response', () {
      final jsonStr = '''
      {
        "query": { "uniqueIdentity": "gb-nr:L79447:2026-07-22" },
        "service": {
          "scheduleMetadata": {
            "uniqueIdentity": "gb-nr:L79447:2026-07-22",
            "identity": "L79447",
            "trainReportingIdentity": "1L60"
          }
        }
      }
      ''';
      final json = jsonDecode(jsonStr);
      final detail = ServiceDetail.fromJson(json);

      expect(detail.serviceUid, "gb-nr:L79447:2026-07-22");
      expect(detail.trainIdentity, "1L60");
    });

    test('should reject schedule identity L79447 when it is contained in serviceUid and no trainReportingIdentity exists', () {
      final jsonStr = '''
      {
        "query": { "uniqueIdentity": "gb-nr:L79447:2026-07-22" },
        "service": {
          "scheduleMetadata": {
            "uniqueIdentity": "gb-nr:L79447:2026-07-22",
            "identity": "L79447"
          }
        }
      }
      ''';
      final json = jsonDecode(jsonStr);
      final detail = ServiceDetail.fromJson(json);

      expect(detail.serviceUid, "gb-nr:L79447:2026-07-22");
      expect(detail.trainIdentity, "");
    });

    test('should leave trainIdentity empty if only serviceUid is present in schedule identity', () {
      final jsonStr = '''
      {
        "service": {
          "scheduleMetadata": {
            "uniqueIdentity": "gb-nr:W12345:2026-07-23",
            "identity": "gb-nr:W12345:2026-07-23"
          }
        }
      }
      ''';
      final json = jsonDecode(jsonStr);
      final detail = ServiceDetail.fromJson(json);
      expect(detail.serviceUid, "gb-nr:W12345:2026-07-23");
      expect(detail.trainIdentity, "");
    });

    test('should parse numberOfVehicles on ServiceDetail and CallingPoints for formation changes', () {
      final jsonStr = '''
      {
        "service": {
          "serviceUid": "W12345",
          "runDate": "2026-07-27",
          "locations": [
            {
              "crs": "WAT",
              "description": "London Waterloo",
              "numberOfVehicles": 8
            },
            {
              "crs": "BSK",
              "description": "Basingstoke",
              "numberOfVehicles": 4
            }
          ]
        }
      }
      ''';
      final json = jsonDecode(jsonStr);
      final detail = ServiceDetail.fromJson(json);

      expect(detail.coachCount, 8);
      expect(detail.locations.length, 2);
      expect(detail.locations[0].coachCount, 8);
      expect(detail.locations[1].coachCount, 4);
    });
  });
}



