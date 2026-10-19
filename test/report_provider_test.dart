import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_retail/providers/report_provider.dart';
import 'package:pos_retail/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final orders = [
    {
      'id': 1,
      'order_number': 'ORD-1',
      'total_amount': '100000.00',
      'payment_status': 'paid',
      'order_status': 'completed',
      'created_at': '2026-10-01T10:00:00Z',
      'items': [
        {
          'product_id': 7,
          'quantity': 2,
          'subtotal': '60000.00',
          'product': {'name': 'Kaos'},
        },
      ],
      'payments': [
        {
          'id': 1,
          'payment_method_id': 1,
          'amount': '100000.00',
          'status': 'success',
        },
      ],
    },
    {
      'id': 2,
      'order_number': 'ORD-2',
      'total_amount': '40000.00',
      'payment_status': 'partial',
      'order_status': 'completed',
      'created_at': '2026-10-02T10:00:00Z',
      'items': [
        {
          'product_id': 7,
          'quantity': 1,
          'subtotal': '20000.00',
          'product': {'name': 'Kaos'},
        },
        {
          'product_id': 9,
          'quantity': 4,
          'subtotal': '20000.00',
          'product': {'name': 'Topi'},
        },
      ],
      'payments': [
        {
          'id': 2,
          'payment_method_id': 2,
          'amount': '10000.00',
          'status': 'success',
        },
        {
          'id': 3,
          'payment_method_id': 1,
          'amount': '5000.00',
          'status': 'success',
        },
      ],
    },
  ];

  tearDown(() {
    ApiService.client = http.Client();
  });

  MockClient router({Uri? capture}) {
    return MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/orders/history')) {
        final start = request.url.queryParameters['start_date'];
        final end = request.url.queryParameters['end_date'];
        final outlet = request.url.queryParameters['outlet_id'];
        return http.Response(
          jsonEncode({
            'data': orders,
            'meta': {'start_date': start, 'end_date': end, 'outlet_id': outlet},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/payment-methods')) {
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 1, 'name': 'Tunai', 'code': 'cash'},
              {'id': 2, 'name': 'QRIS', 'code': 'qris'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'message': 'not found'}),
        404,
        headers: {'content-type': 'application/json'},
      );
    });
  }

  test(
    'agregasi laporan: omzet, status bayar, rata-rata, produk terlaris',
    () async {
      ApiService.client = router();
      final provider = ReportProvider();

      await provider.load(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 7),
        outletId: 3,
      );

      expect(provider.error, isNull);
      expect(provider.totalOrders, 2);
      expect(provider.revenue, 140000);
      expect(provider.paidOrders, 1);
      expect(provider.unpaidOrders, 1);
      expect(provider.avgOrder, 70000);
      expect(provider.truncated, isFalse);

      // Produk terlaris urut qty: Topi (4) lalu Kaos (3).
      expect(provider.bestSellers.first.name, 'Topi');
      expect(provider.bestSellers.first.qty, 4);
      expect(provider.bestSellers[1].name, 'Kaos');
      expect(provider.bestSellers[1].qty, 3);
    },
  );

  test('rekap per metode memetakan id → nama dari /payment-methods', () async {
    ApiService.client = router();
    final provider = ReportProvider();

    await provider.load(
      start: DateTime(2026, 10, 1),
      end: DateTime(2026, 10, 7),
      outletId: 3,
    );
    await provider.loadPaymentBreakdownIfNeeded(outletId: 3);

    expect(provider.paymentBreakdown.length, 2);
    expect(provider.paymentBreakdown.first.name, 'Tunai');
    expect(provider.paymentBreakdown.first.amount, 105000);
    expect(provider.paymentBreakdown.first.count, 2);
    expect(provider.paymentBreakdown[1].name, 'QRIS');
    expect(provider.paymentBreakdown[1].amount, 10000);
  });

  test(
    'rentang > 93 hari ditolak dengan pesan jelas tanpa request API',
    () async {
      var called = 0;
      ApiService.client = MockClient((request) async {
        called++;
        return http.Response('{}', 200);
      });

      final provider = ReportProvider();
      await provider.load(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 1).add(const Duration(days: 94)),
      );

      expect(called, 0);
      expect(provider.error, contains('93'));
      expect(provider.totalOrders, 0);
      expect(provider.revenue, 0);
    },
  );

  test(
    'error server → error terisi dan total di-reset (bukan angka lama)',
    () async {
      ApiService.client = router();
      final provider = ReportProvider();
      await provider.load(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 7),
        outletId: 3,
      );
      expect(provider.revenue, 140000);

      ApiService.client = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Server bermasalah'}),
          500,
          headers: {'content-type': 'application/json'},
        );
      });
      await provider.load(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 7),
        outletId: 3,
      );

      expect(provider.error, isNotNull);
      expect(provider.revenue, 0);
      expect(provider.totalOrders, 0);
    },
  );
}
