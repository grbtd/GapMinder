import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gapminder/models/departure.dart';
import 'package:gapminder/models/station.dart';
import 'package:gapminder/screens/service_detail_screen.dart';

void main() {
  testWidgets('ServiceDetailScreen renders correctly with departure', (WidgetTester tester) async {
    final station = Station(
      name: 'London Waterloo',
      crsCode: 'WAT',
      latitude: 51.503,
      longitude: -0.113,
    );

    final departure = Departure(
      serviceUid: 'W12345',
      runDate: '2025-10-26',
      scheduledTime: '1015',
      realtimeTime: '1015',
      platform: '12',
      operatorName: 'South Western Railway',
      destination: 'Portsmouth Harbour',
      platformChanged: false,
      status: 'ON TIME',
      serviceType: 'TRAIN',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ServiceDetailScreen(
          station: station,
          departure: departure,
        ),
      ),
    );

    // Initial loading state
    expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));
  });
}
