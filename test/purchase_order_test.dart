import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/screens/purchases/purchase_order_detail_screen.dart';
import 'package:pos_retail/screens/purchases/purchase_order_list_screen.dart';
import 'package:pos_retail/services/api_service.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => LangProvider())],
    child: MaterialApp(home: child),
  );
}

Map<String, dynamic> _poJson({String status = 'dikirim'}) => {
  'id': 1,
  'number': 'PO-001',
  'supplier_id': 7,
  'supplier_name': 'Supplier Maju',
  'outlet_id': 1,
  'status': status,
  'total_cost': '150000',
  'note': 'Stok gula',
  'created_at': '2026-10-20T10:00:00Z',
  'items': [
    {
      'product_id': 3,
      'product_name': 'Gula 1kg',
      'qty': 10,
      'cost_price': '15000',
    },
  ],
  'history': [
    {'status': 'draft', 'created_at': '2026-10-19T09:00:00Z'},
    {'status': 'dikirim', 'created_at': '2026-10-20T10:00:00Z'},
  ],
};

MockClient _listClient({int listStatus = 200}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/purchase-orders')) {
      if (listStatus != 200) {
        return http.Response(
          jsonEncode({'message': 'Data tidak ditemukan.'}),
          listStatus,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'data': [_poJson()],
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
        jsonEncode({
          'data': _poJson(status: 'diterima'),
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'GET' && path.endsWith('/purchase-orders/1')) {
      return http.Response(
        jsonEncode({
          'data': _poJson(status: received ? 'diterima' : 'dikirim'),
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

  testWidgets('daftar PO tampil dari server', (tester) async {
    ApiService.client = _listClient();

    await tester.pumpWidget(
      _wrap(const PurchaseOrderListScreen(outletId: 1)),
    );
    await tester.pumpAndSettle();

    expect(find.text('PO-001'), findsOneWidget);
    expect(find.textContaining('Supplier Maju'), findsOneWidget);
    expect(find.text('Dikirim'), findsWidgets);
  });

  testWidgets('PO 404 → error jujur + tombol retry', (tester) async {
    ApiService.client = _listClient(listStatus: 404);

    await tester.pumpWidget(
      _wrap(const PurchaseOrderListScreen(outletId: 1)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Data tidak ditemukan.'), findsOneWidget);
    expect(find.text('Coba Lagi'), findsOneWidget);
  });

  testWidgets('receive sukses → snackbar + status berubah', (tester) async {
    ApiService.client = _detailClient();

    await tester.pumpWidget(
      _wrap(const PurchaseOrderDetailScreen(poId: 1)),
    );
    await tester.pumpAndSettle();

    expect(find.text('PO-001'), findsWidgets);
    expect(find.text('Terima Barang'), findsOneWidget);

    await tester.tap(find.text('Terima Barang'));
    await tester.pumpAndSettle();

    // Dialog konfirmasi → tekan Terima.
    expect(find.text('Terima barang?'), findsOneWidget);
    await tester.tap(find.text('Terima'));
    await tester.pumpAndSettle();

    expect(
      find.text('Purchase order diterima. Stok bertambah.'),
      findsOneWidget,
    );
    expect(find.text('Diterima'), findsWidgets);
  });
}
