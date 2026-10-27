import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/providers/auth_provider.dart';
import 'package:pos_retail/screens/reports/inventory_report_screen.dart';
import 'package:pos_retail/services/api_service.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LangProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
    ],
    child: MaterialApp(home: child),
  );
}

MockClient _okClient() {
  return MockClient((request) async {
    if (request.url.path.endsWith('/reports/inventory')) {
      return http.Response(
        jsonEncode({
          'data': {
            'total_value': '25000000.00',
            'opname_accuracy': 96.5,
            'low_stock': [
              {'name': 'Kopi Arabika', 'qty': 2, 'unit': 'pcs'},
            ],
            'overstock': [
              {'name': 'Gula 1kg', 'qty': 500},
            ],
            'movements': [
              {
                'product_name': 'Kopi Arabika',
                'type': 'sale',
                'qty_change': -2,
                'created_at': '2026-10-27T10:00:00Z',
              },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 404);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ApiService.client = http.Client();
  });

  testWidgets('kartu nilai + low stock + overstock + mutasi tampil',
      (tester) async {
    ApiService.client = _okClient();

    await tester.pumpWidget(_wrap(const InventoryReportScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Kopi Arabika'), findsWidgets);
    expect(find.text('Gula 1kg'), findsOneWidget);
    expect(find.text('96.5%'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.textContaining('PDF/Excel'), findsWidgets);
  });

  testWidgets('404 jujur + tombol Coba Lagi me-retry', (tester) async {
    var calls = 0;
    ApiService.client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return http.Response(
          jsonEncode({'message': 'Belum ada endpoint.'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'data': {
            'total_value': 0,
            'low_stock': [],
            'overstock': [],
            'movements': [],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(_wrap(const InventoryReportScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Coba Lagi'), findsOneWidget);
    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Coba Lagi'), findsNothing);
  });
}
