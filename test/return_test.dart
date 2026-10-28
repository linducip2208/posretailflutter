import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/screens/sales/return_detail_screen.dart';
import 'package:pos_retail/screens/sales/return_list_screen.dart';
import 'package:pos_retail/services/api_service.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => LangProvider())],
    child: MaterialApp(home: child),
  );
}

/// Bentuk backend: return_number, returnItems{quantity}, total_amount,
/// status pending|completed|rejected, relasi order.
Map<String, dynamic> _returJson({String status = 'pending'}) => {
  'id': 5,
  'order_id': 12,
  'order_number': 'ORD-012',
  'return_number': 'RT-20261020-0005',
  'outlet_id': 1,
  'status': status,
  'total_amount': '20000.00',
  'reason': 'Barang cacat',
  'created_at': '2026-10-20T10:00:00Z',
  'returnItems': [
    {'product_id': 3, 'product_name': 'Kopi 250g', 'quantity': 2},
  ],
};

MockClient _listClient({int listStatus = 200}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/returns')) {
      if (listStatus != 200) {
        return http.Response(
          jsonEncode({'message': 'Data tidak ditemukan.'}),
          listStatus,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'data': [_returJson()],
          'meta': {'total': 1, 'last_page': 1},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 404);
  });
}

MockClient _detailClient({bool withReject = false}) {
  var status = 'pending';
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('/approve')) {
      status = 'completed';
      return http.Response(
        jsonEncode({'data': _returJson(status: 'completed')}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (withReject &&
        request.method == 'POST' &&
        path.endsWith('/reject')) {
      status = 'rejected';
      return http.Response(
        jsonEncode({'data': _returJson(status: 'rejected')}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'GET' && path.endsWith('/returns/5')) {
      return http.Response(
        jsonEncode({
          'data': _returJson(status: status),
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

  testWidgets('daftar retur tampil dari server', (tester) async {
    ApiService.client = _listClient();

    await tester.pumpWidget(_wrap(const ReturnListScreen(outletId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('RT-20261020-0005'), findsOneWidget);
    expect(find.textContaining('ORD-012'), findsOneWidget);
    expect(find.text('Menunggu'), findsWidgets);
  });

  testWidgets('retur 404 → error jujur + tombol retry', (tester) async {
    ApiService.client = _listClient(listStatus: 404);

    await tester.pumpWidget(_wrap(const ReturnListScreen(outletId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('Data tidak ditemukan.'), findsOneWidget);
    expect(find.text('Coba Lagi'), findsOneWidget);
  });

  testWidgets('approve sukses → snackbar + status selesai', (tester) async {
    ApiService.client = _detailClient();

    await tester.pumpWidget(_wrap(const ReturnDetailScreen(returnId: 5)));
    await tester.pumpAndSettle();

    expect(find.text('RT-20261020-0005'), findsWidgets);
    expect(find.text('Setujui'), findsOneWidget);

    await tester.tap(find.text('Setujui'));
    await tester.pumpAndSettle();

    expect(find.text('Setujui retur?'), findsOneWidget);
    await tester.tap(find.text('Setujui').last);
    await tester.pumpAndSettle();

    expect(find.text('Retur disetujui. Stok bertambah.'), findsOneWidget);
    expect(find.text('Selesai'), findsWidgets);
  });

  testWidgets('reject sukses → snackbar + status ditolak', (tester) async {
    // Backend baru: POST /returns/{id}/reject {reason?} → status rejected.
    ApiService.client = _detailClient(withReject: true);

    await tester.pumpWidget(_wrap(const ReturnDetailScreen(returnId: 5)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tolak'));
    await tester.pumpAndSettle();

    expect(find.text('Tolak retur?'), findsOneWidget);
    await tester.tap(find.text('Tolak Retur'));
    await tester.pumpAndSettle();

    expect(find.text('Retur ditolak.'), findsOneWidget);
    expect(find.text('Ditolak'), findsWidgets);
  });

  testWidgets('reject di server lama → 404 jujur via snackbar', (tester) async {
    // Server lama tanpa POST /returns/{id}/reject.
    ApiService.client = _detailClient(withReject: false);

    await tester.pumpWidget(_wrap(const ReturnDetailScreen(returnId: 5)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tolak'));
    await tester.pumpAndSettle();

    expect(find.text('Tolak retur?'), findsOneWidget);
    await tester.tap(find.text('Tolak Retur'));
    await tester.pumpAndSettle();

    expect(find.text('Data tidak ditemukan.'), findsOneWidget);
  });
}
