// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gapminder/main.dart';

void main() {
  testWidgets('GapMinderApp initial screen smoke test', (WidgetTester tester) async {
    // Build our app and advance past splash screen.
    await tester.pumpWidget(const GapMinderApp());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));

    // Verify that the title or app bar elements render.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
