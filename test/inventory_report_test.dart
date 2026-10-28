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

/// Backend nyata:
/// GET /reports/stock → {inventory_value, low_stock, out_of_stock}
/// GET /stock-movements → envelope {product: {name}, type, quantity, ...}.
MockClient _okClient() {
  return MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/reports/stock')) {
      return http.Response(
        jsonEncode({
          'data': {
            'inventory_value': 25000000,
            'low_stock': 3,
            'out_of_stock': 1,
            'outlet_scope': [1],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/stock-movements')) {
      return http.Response(
        jsonEncode({
          'data': [
            {
              'id': 1,
              'product': {'id': 7, 'name': 'Kopi Arabika'},
              'type': 'out',
              'quantity': 2,
              'reference_type': 'sale',
              'created_at': '2026-10-27T10:00:00.000Z',
            },
          ],
          'meta': {'current_page': 1, 'total': 1},
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

  testWidgets('kartu nilai + jumlah menipis/habis + mutasi tampil',
      (tester) async {
    ApiService.client = _okClient();

    await tester.pumpWidget(_wrap(const InventoryReportScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Kopi Arabika'), findsOneWidget);
    expect(find.text('Stok Menipis'), findsOneWidget);
    expect(find.text('Stok Habis'), findsOneWidget);
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
      if (request.url.path.endsWith('/reports/stock')) {
        return http.Response(
          jsonEncode({
            'data': {
              'inventory_value': 0,
              'low_stock': 0,
              'out_of_stock': 0,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'data': [],
          'meta': {'current_page': 1, 'total': 0},
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

    // Gagal di load pertama (2 request paralel: stock 404);
    // retry = stock + movements.
    expect(calls, 4);
    expect(find.text('Coba Lagi'), findsNothing);
  });
}
