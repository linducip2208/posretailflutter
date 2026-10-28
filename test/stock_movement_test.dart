import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/providers/auth_provider.dart';
import 'package:pos_retail/screens/inventory/stock_movement_screen.dart';
import 'package:pos_retail/services/api_service.dart';
import 'package:pos_retail/theme/app_theme.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LangProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

/// Fixture sesuai kontrak backend live: `type=in|out`, `quantity`,
/// `reference_type`, `reference_id`, `notes`.
Map<String, dynamic> _movement({
  required int id,
  required String name,
  required String type,
  required num qty,
}) {
  return {
    'id': id,
    'product_id': id,
    'product': {'name': name},
    'outlet_id': 1,
    'type': type,
    'quantity': qty,
    'reference_type': type == 'in' ? 'purchase' : 'transfer',
    'reference_id': 7,
    'notes': type == 'in' ? 'Terima PO #7' : 'Transfer keluar #STF-1',
    'created_at': '2026-10-20T10:00:00Z',
  };
}

MockClient _listClient() {
  return MockClient((request) async {
    if (request.url.path.endsWith('/stock-movements')) {
      return http.Response(
        jsonEncode({
          'data': [
            _movement(id: 1, name: 'Kopi Susu', type: 'in', qty: 5),
            _movement(id: 2, name: 'Roti Bakar', type: 'out', qty: 3),
          ],
          'meta': {'total': 2, 'last_page': 1},
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

  testWidgets('daftar mutasi tampil dengan pewarnaan selisih', (tester) async {
    ApiService.client = _listClient();

    await tester.pumpWidget(_wrap(const StockMovementScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Kopi Susu'), findsOneWidget);
    expect(find.text('Roti Bakar'), findsOneWidget);
    // Label Indonesia per type backend (in/out).
    expect(find.text('Masuk'), findsOneWidget);
    expect(find.text('Keluar'), findsOneWidget);

    final plus = tester.widget<Text>(find.text('+5'));
    expect(plus.style?.color, AppColors.success);
    final minus = tester.widget<Text>(find.text('-3'));
    expect(minus.style?.color, AppColors.error);
  });

  testWidgets('404 tampil jujur + retry memuat ulang', (tester) async {
    var calls = 0;
    ApiService.client = MockClient((request) async {
      if (request.url.path.endsWith('/stock-movements')) {
        calls++;
        if (calls == 1) {
          return http.Response(
            jsonEncode({'message': 'Tidak ketemu.'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'data': [_movement(id: 1, name: 'Kopi Susu', type: 'in', qty: 5)],
            'meta': {'total': 1, 'last_page': 1},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(_wrap(const StockMovementScreen()));
    await tester.pumpAndSettle();

    // Error jujur dari server + tombol coba lagi.
    expect(find.text('Tidak ketemu.'), findsOneWidget);
    expect(find.text('Coba Lagi'), findsOneWidget);

    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Kopi Susu'), findsOneWidget);
  });
}
