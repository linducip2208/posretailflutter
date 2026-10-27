import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/providers/auth_provider.dart';
import 'package:pos_retail/screens/reports/purchase_report_screen.dart';
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
    if (request.url.path.endsWith('/reports/purchases')) {
      return http.Response(
        jsonEncode({
          'data': {
            'total_cost': '1500000.00',
            'po_count': 4,
            'outstanding_po': 1,
            'top_suppliers': [
              {'name': 'PT Maju', 'total': '900000.00'},
              {'name': 'CV Berkah', 'total': '600000.00'},
            ],
            'trend': [
              {'date': '2026-10-26', 'total': '500000.00'},
              {'date': '2026-10-27', 'total': '1000000.00'},
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

  testWidgets('kartu total + supplier teratas + tren tampil', (tester) async {
    ApiService.client = _okClient();

    await tester.pumpWidget(_wrap(const PurchaseReportScreen()));
    await tester.pumpAndSettle();

    expect(find.text('4'), findsWidgets); // jumlah PO
    expect(find.text('PT Maju'), findsOneWidget);
    expect(find.text('CV Berkah'), findsOneWidget);
    expect(find.text('2026-10-26'), findsOneWidget);
    // Catatan jujur export via web selalu tampil (ListView malas → drag dulu).
    final verticalList = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.vertical,
    );
    await tester.drag(verticalList, const Offset(0, -800));
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
            'total_cost': 100000,
            'po_count': 1,
            'outstanding_po': 0,
            'top_suppliers': [],
            'trend': [],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(_wrap(const PurchaseReportScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Coba Lagi'), findsOneWidget);
    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Coba Lagi'), findsNothing);
  });
}
