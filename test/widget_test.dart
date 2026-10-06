import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_retail/main.dart';

void main() {
  testWidgets('Splash screen renders POS Retail branding', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byIcon(Icons.store), findsOneWidget);

    expect(find.text('POS Retail'), findsOneWidget);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
