import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/screens/sales/held_order_screen.dart';
import 'package:pos_retail/services/api_service.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => LangProvider())],
    child: MaterialApp(home: child),
  );
}

/// Bentuk backend: /held-carts, items array top-level, tanpa expires_at.
Map<String, dynamic> _holdJson() => {
  'id': 2,
  'outlet_id': 1,
  'user_id': 7,
  'customer_id': null,
  'label': 'Meja 4',
  'items': [
    {'product_id': 1, 'name': 'Kopi', 'price': 15000, 'qty': 2},
  ],
  'created_at': '2026-10-26T10:00:00Z',
  'updated_at': '2026-10-26T10:00:00Z',
};

MockClient _listClient({int listStatus = 200}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/held-carts')) {
      if (listStatus != 200) {
        return http.Response(
          jsonEncode({'message': 'Data tidak ditemukan.'}),
          listStatus,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'data': [_holdJson()],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'POST' && path.endsWith('/resume')) {
      return http.Response(
        jsonEncode({'data': _holdJson()}),
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

  testWidgets('daftar hold tampil dari server', (tester) async {
    ApiService.client = _listClient();

    await tester.pumpWidget(_wrap(const HeldOrderScreen(outletId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('Meja 4'), findsOneWidget);
    expect(find.textContaining('2 item'), findsOneWidget);
  });

  testWidgets('hold 404 → error jujur + tombol retry', (tester) async {
    ApiService.client = _listClient(listStatus: 404);

    await tester.pumpWidget(_wrap(const HeldOrderScreen(outletId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('Data tidak ditemukan.'), findsOneWidget);
    expect(find.text('Coba Lagi'), findsOneWidget);
  });

  testWidgets('resume sukses → snackbar + instruksi kasir', (tester) async {
    ApiService.client = _listClient();

    await tester.pumpWidget(_wrap(const HeldOrderScreen(outletId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('Meja 4'), findsOneWidget);
    await tester.tap(find.byTooltip('Lanjutkan'));
    await tester.pumpAndSettle();

    expect(find.text('Lanjutkan transaksi ini?'), findsOneWidget);
    await tester.tap(find.text('Lanjutkan').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Transaksi dilanjutkan'), findsOneWidget);
    expect(find.textContaining('Buka kembali di kasir'), findsOneWidget);
  });
}
