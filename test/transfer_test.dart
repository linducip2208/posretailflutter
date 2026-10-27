import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/screens/inventory/transfer_detail_screen.dart';
import 'package:pos_retail/screens/inventory/transfer_list_screen.dart';
import 'package:pos_retail/services/api_service.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => LangProvider())],
    child: MaterialApp(home: child),
  );
}

Map<String, dynamic> _transferJson({String status = 'dikirim'}) => {
  'id': 1,
  'from_outlet_id': 1,
  'to_outlet_id': 2,
  'from_name': 'Outlet Pusat',
  'to_name': 'Outlet Cabang',
  'status': status,
  'note': 'Restock',
  'created_at': '2026-10-20T10:00:00Z',
  'items': [
    {'product_id': 3, 'product_name': 'Gula 1kg', 'qty': 10},
  ],
};

MockClient _listClient({int listStatus = 200}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/stock-transfers')) {
      if (listStatus != 200) {
        return http.Response(
          jsonEncode({'message': 'Data tidak ditemukan.'}),
          listStatus,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'data': [_transferJson()],
          'meta': {'total': 1, 'last_page': 1},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 404);
  });
}

MockClient _detailClient() {
  var received = false;
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('/receive')) {
      received = true;
      return http.Response(
        jsonEncode({'data': _transferJson(status: 'diterima')}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'GET' && path.endsWith('/stock-transfers/1')) {
      return http.Response(
        jsonEncode({
          'data': _transferJson(status: received ? 'diterima' : 'dikirim'),
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

  testWidgets('daftar transfer tampil dari server', (tester) async {
    ApiService.client = _listClient();

    await tester.pumpWidget(_wrap(const TransferListScreen(outletId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('Transfer #1'), findsOneWidget);
    expect(find.text('Dikirim'), findsWidgets);
  });

  testWidgets('transfer 404 → error jujur + tombol retry', (tester) async {
    ApiService.client = _listClient(listStatus: 404);

    await tester.pumpWidget(_wrap(const TransferListScreen(outletId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('Data tidak ditemukan.'), findsOneWidget);
    expect(find.text('Coba Lagi'), findsOneWidget);
  });

  testWidgets('receive sukses → snackbar + status berubah', (tester) async {
    ApiService.client = _detailClient();

    await tester.pumpWidget(_wrap(const TransferDetailScreen(transferId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('Transfer #1'), findsWidgets);
    expect(find.text('Terima Barang'), findsOneWidget);

    await tester.tap(find.text('Terima Barang'));
    await tester.pumpAndSettle();

    expect(find.text('Terima transfer?'), findsOneWidget);
    await tester.tap(find.text('Terima'));
    await tester.pumpAndSettle();

    expect(
      find.text('Transfer diterima. Stok bertambah.'),
      findsOneWidget,
    );
    expect(find.text('Diterima'), findsWidgets);
  });
}
