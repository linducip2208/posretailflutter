import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/models/order.dart';
import 'package:pos_retail/screens/orders/order_detail_screen.dart';
import 'package:pos_retail/services/api_service.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => LangProvider())],
    child: MaterialApp(home: child),
  );
}

Map<String, dynamic> _orderJson() => {
  'id': 501,
  'order_number': 'ORD-TEST-501',
  'outlet_id': 1,
  'subtotal': 12000,
  'discount_amount': 0,
  'tax_amount': 0,
  'total_amount': 12000,
  'payment_status': 'paid',
  'order_status': 'completed',
  'created_at': '2026-10-19 11:15:16',
  'queue_number': '007',
  'items': [
    {
      'id': 1446,
      'product_id': 1,
      'product': {'name': 'Chitato Sapi Panggang 60gr'},
      'quantity': 1,
      'unit_price': 12000,
      'subtotal': 12000,
    },
  ],
  'payments': [
    {'id': 501, 'payment_method_id': 1, 'amount': 12000, 'status': 'success'},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Catatan: alur SyncScreen TIDAK diuji di widget test — operasi sqlite
  // (sqflite FFI) menggantung di zona fake-async flutter_test (terbukti
  // via file probe minimal). Alur antrean/sync tercakup di
  // `offline_sync_test.dart` (real async) + E2E perangkat nyata.
  group('OrderDetailScreen (refund)', () {
    tearDown(() {
      ApiService.client = http.Client();
      ApiService.onUnauthorized = null;
    });

    testWidgets('order completed menampilkan aksi refund + sheet item', (
      tester,
    ) async {
      ApiService.client = MockClient((request) async {
        if (request.url.path.endsWith('/orders/501')) {
          return http.Response(
            jsonEncode({'data': _orderJson()}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      });

      final initial = Order.fromJson(_orderJson());
      await tester.pumpWidget(
        _wrap(OrderDetailScreen(orderId: 501, initialOrder: initial)),
      );
      await tester.pumpAndSettle();

      expect(find.text('ORD-TEST-501'), findsWidgets);
      expect(find.byIcon(Icons.assignment_return_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.assignment_return_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Refund Item'), findsOneWidget);
      expect(find.textContaining('Chitato Sapi Panggang 60gr'), findsWidgets);
    });
  });
}
