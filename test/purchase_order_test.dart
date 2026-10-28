import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/models/purchase_order.dart';
import 'package:pos_retail/screens/purchases/purchase_order_detail_screen.dart';
import 'package:pos_retail/screens/purchases/purchase_order_list_screen.dart';
import 'package:pos_retail/services/api_service.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => LangProvider())],
    child: MaterialApp(home: child),
  );
}

/// Fixture mengikuti kontrak backend persis: `po_number`, `total_amount`,
/// `notes`, relasi `purchaseOrderItems`, item `quantity`/`unit_price`,
/// dan status Inggris `draft`/`ordered`/`received`/`cancelled`.
Map<String, dynamic> _poJson({String status = 'ordered'}) => {
  'id': 1,
  'po_number': 'PO-20261020-0001',
  'supplier_id': 7,
  'supplier': {'id': 7, 'name': 'Supplier Maju'},
  'outlet_id': 1,
  'status': status,
  'total_amount': '150000',
  'notes': 'Stok gula',
  'created_at': '2026-10-20T10:00:00Z',
  'purchaseOrderItems': [
    {
      'product_id': 3,
      'product': {'id': 3, 'name': 'Gula 1kg'},
      'quantity': 10,
      'unit_price': '15000',
      'subtotal': '150000',
    },
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
          'data': _poJson(status: 'received'),
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'GET' && path.endsWith('/purchase-orders/1')) {
      return http.Response(
        jsonEncode({
          'data': _poJson(status: received ? 'received' : 'ordered'),
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

    expect(find.text('PO-20261020-0001'), findsOneWidget);
    expect(find.textContaining('Supplier Maju'), findsOneWidget);
    expect(find.text('Dipesan'), findsWidgets);
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

    expect(find.text('PO-20261020-0001'), findsWidgets);
    expect(find.text('Terima Barang'), findsOneWidget);

    await tester.tap(find.text('Terima Barang'));
    await tester.pumpAndSettle();

    // Dialog konfirmasi → tekan Terima.
    expect(find.text('Terima barang?'), findsOneWidget);
    await tester.tap(find.text('Terima'));
    await tester.pumpAndSettle();

    expect(
      find.text('Purchase order diterima dan tercatat di jurnal.'),
      findsOneWidget,
    );
    expect(find.text('Diterima'), findsWidgets);
  });

  testWidgets('order sukses → snackbar + status dipesan', (tester) async {
    // Backend baru: POST /purchase-orders/{id}/order (draft → ordered).
    var status = 'draft';
    ApiService.client = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'GET' && path.endsWith('/purchase-orders/1')) {
        return http.Response(
          jsonEncode({'data': _poJson(status: status)}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'POST' &&
          path.endsWith('/purchase-orders/1/order')) {
        status = 'ordered';
        return http.Response(
          jsonEncode({'data': _poJson(status: 'ordered')}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _wrap(const PurchaseOrderDetailScreen(poId: 1)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kirim ke Supplier'), findsOneWidget);
    await tester.tap(find.text('Kirim ke Supplier'));
    await tester.pumpAndSettle();

    expect(find.text('Kirim PO ke supplier?'), findsOneWidget);
    await tester.tap(find.text('Kirim'));
    await tester.pumpAndSettle();

    expect(
      find.text('Purchase order dikirim ke supplier.'),
      findsOneWidget,
    );
    expect(find.text('Dipesan'), findsWidgets);
  });

  testWidgets('cancel sukses mengirim reason → snackbar + status dibatalkan',
      (tester) async {
    // Backend baru: POST /purchase-orders/{id}/cancel {reason?}.
    var status = 'draft';
    String? sentReason;
    ApiService.client = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'GET' && path.endsWith('/purchase-orders/1')) {
        return http.Response(
          jsonEncode({'data': _poJson(status: status)}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'POST' &&
          path.endsWith('/purchase-orders/1/cancel')) {
        final body = request.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(request.body) as Map<String, dynamic>;
        sentReason = body['reason']?.toString();
        status = 'cancelled';
        return http.Response(
          jsonEncode({'data': _poJson(status: 'cancelled')}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _wrap(const PurchaseOrderDetailScreen(poId: 1)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Batalkan'));
    await tester.pumpAndSettle();

    expect(find.text('Batalkan PO?'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Stok masih cukup',
    );
    await tester.tap(find.text('Batalkan PO'));
    await tester.pumpAndSettle();

    expect(sentReason, 'Stok masih cukup');
    expect(find.text('Purchase order dibatalkan.'), findsOneWidget);
    expect(find.text('Dibatalkan'), findsWidgets);
  });

  testWidgets('order di server lama → 404 jujur', (tester) async {
    ApiService.client = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'GET' && path.endsWith('/purchase-orders/1')) {
        return http.Response(
          jsonEncode({'data': _poJson(status: 'draft')}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'POST' &&
          path.endsWith('/purchase-orders/1/order')) {
        return http.Response(
          jsonEncode({'message': 'Not found.'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(
      _wrap(const PurchaseOrderDetailScreen(poId: 1)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kirim ke Supplier'), findsOneWidget);
    await tester.tap(find.text('Kirim ke Supplier'));
    await tester.pumpAndSettle();

    expect(find.text('Kirim PO ke supplier?'), findsOneWidget);
    await tester.tap(find.text('Kirim'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('belum diperbarui'),
      findsOneWidget,
    );
  });

  test('model memakai kontrak backend (po_number/total_amount/notes)', () {
    final po = PurchaseOrder.fromJson(_poJson());
    expect(po.number, 'PO-20261020-0001');
    expect(po.displayNumber, 'PO-20261020-0001');
    expect(po.totalCost, 150000);
    expect(po.note, 'Stok gula');
    expect(po.status, 'ordered');
    expect(po.supplierName, 'Supplier Maju');
    expect(po.items, isNotNull);
    expect(po.items!.single.qty, 10);
    expect(po.items!.single.costPrice, 15000);
    expect(poStatusLabel('ordered'), 'Dipesan');
    expect(poStatusLabel('received'), 'Diterima');

    final itemJson = po.items!.single.toJson();
    expect(itemJson['quantity'], 10);
    expect(itemJson['unit_price'], 15000);
    expect(itemJson.containsKey('qty'), isFalse);
    expect(itemJson.containsKey('cost_price'), isFalse);
  });
}
