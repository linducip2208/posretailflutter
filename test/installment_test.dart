import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/screens/sales/installment_screen.dart';
import 'package:pos_retail/services/api_service.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => LangProvider())],
    child: MaterialApp(home: child),
  );
}

/// Bentuk backend: order_id, installment_number, amount, due_date,
/// paid_date, status pending|paid|overdue.
Map<String, dynamic> _insJson({
  int id = 1,
  int orderId = 9,
  int number = 1,
  String status = 'pending',
}) => {
  'id': id,
  'order_id': orderId,
  'installment_number': number,
  'amount': '100000.00',
  'due_date': '2026-11-20',
  'paid_date': null,
  'status': status,
  'order': {'id': orderId, 'number': 'ORD-00$orderId'},
};

MockClient _lookupClient({int lookupStatus = 200}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/payment-methods')) {
      return http.Response(
        jsonEncode({
          'data': [
            {'id': 1, 'name': 'Tunai'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'GET' && path.endsWith('/installments')) {
      if (lookupStatus != 200) {
        return http.Response(
          jsonEncode({'message': 'Data tidak ditemukan.'}),
          lookupStatus,
          headers: {'content-type': 'application/json'},
        );
      }
      // Backend TIDAK mendukung filter order_id: selalu daftar penuh,
      // Flutter menyaring di sisi klien.
      return http.Response(
        jsonEncode({
          'data': [
            _insJson(),
            _insJson(id: 2, orderId: 10, number: 1, status: 'paid'),
          ],
          'meta': {'total': 2, 'last_page': 1},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'POST' && path.endsWith('/installments/1/pay')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['payment_method_id'] == null) {
        return http.Response(
          jsonEncode({'message': 'Data tidak valid, periksa isian.'}),
          422,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'data': {
            'installment_id': 1,
            'paid_total': body['amount'],
            'remaining': 0,
            'payment_status': 'paid',
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

  testWidgets('daftar cicilan tampil + saring order di klien', (tester) async {
    ApiService.client = _lookupClient();

    await tester.pumpWidget(_wrap(const InstallmentScreen(initialOrderId: 9)));
    await tester.pumpAndSettle();

    expect(find.text('Cicilan #1'), findsOneWidget);
    expect(find.textContaining('Order #9'), findsOneWidget);
    expect(find.text('Menunggu'), findsWidgets);
    // Order lain dari server ikut terkirim tapi disaring di klien.
    expect(find.textContaining('Order #10'), findsNothing);
  });

  testWidgets('cicilan 404 → error jujur + tombol retry', (tester) async {
    ApiService.client = _lookupClient(lookupStatus: 404);

    await tester.pumpWidget(_wrap(const InstallmentScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Data tidak ditemukan.'), findsOneWidget);
    expect(find.text('Coba Lagi'), findsOneWidget);
  });

  testWidgets('bayar wajib metode + sukses tercatat', (tester) async {
    ApiService.client = _lookupClient();

    await tester.pumpWidget(_wrap(const InstallmentScreen(initialOrderId: 9)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bayar'));
    await tester.pumpAndSettle();

    // Tanpa metode → validasi menolak (backend mewajibkan payment_method_id).
    await tester.tap(find.text('Bayar').last);
    await tester.pumpAndSettle();
    expect(find.text('Pilih metode pembayaran.'), findsOneWidget);

    // Pilih metode lalu bayar.
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tunai').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bayar').last);
    await tester.pumpAndSettle();

    expect(find.text('Pembayaran tercatat.'), findsOneWidget);
  });
}
