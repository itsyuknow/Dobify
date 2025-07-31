import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironly/main.dart'; // Make sure IronlyApp is defined in main.dart

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    // Build the app and trigger a frame
    await tester.pumpWidget(const ironXpress());

    // Basic smoke test to confirm MaterialApp is present
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
