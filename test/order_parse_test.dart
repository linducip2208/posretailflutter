import 'package:flutter_test/flutter_test.dart';
import 'package:pos_retail/models/order.dart';

void main() {
  group('Order parsing lanjutan', () {
    test('cashier_name dipakai; fallback ke user.name bila tidak ada', () {
      final withCashier = Order.fromJson({
        'id': 1,
        'order_number': 'ORD-1',
        'cashier_name': 'Sari',
        'total_amount': '1000.00',
      });
      expect(withCashier.cashierName, 'Sari');

      final withUser = Order.fromJson({
        'id': 2,
        'order_number': 'ORD-2',
        'user': {'name': 'Budi'},
        'total_amount': '2000.00',
      });
      expect(withUser.cashierName, 'Budi');
    });

    test('item pesanan menjaga id (dipakai refund) dan desimal string', () {
      final order = Order.fromJson({
        'id': 5,
        'order_number': 'ORD-5',
        'total_amount': '11100.00',
        'items': [
          {
            'id': 77,
            'product_id': 4,
            'product': {'name': 'Kopi'},
            'quantity': 3,
            'unit_price': '3700.00',
            'subtotal': '11100.00',
          },
        ],
      });

      final item = order.items!.single;
      expect(item.id, 77);
      expect(item.productId, 4);
      expect(item.unitPrice, 3700.0);
      expect(item.subtotal, 11100.0);
    });

    test('payments menjaga payment_method_id + amount untuk rekap metode', () {
      final order = Order.fromJson({
        'id': 6,
        'order_number': 'ORD-6',
        'total_amount': '50000.00',
        'payments': [
          {
            'id': 1,
            'payment_method_id': 2,
            'amount': '30000.00',
            'status': 'success',
          },
          {
            'id': 2,
            'payment_method_id': 3,
            'amount': '20000.00',
            'status': 'success',
          },
        ],
      });

      final payments = order.payments!;
      expect(payments.length, 2);
      final total = payments.fold<double>(0, (s, p) => s + p.amount);
      expect(total, 50000.0);
      expect(payments.first.paymentMethodId, 2);
    });

    test('status tidak dikenal tetap string aman (tanpa crash UI)', () {
      final order = Order.fromJson({
        'id': 7,
        'order_number': 'ORD-7',
        'payment_status': 'entah',
        'order_status': 'entah',
        'total_amount': '0',
      });
      expect(order.paymentStatus, 'entah');
      expect(order.orderStatus, 'entah');
      expect(order.totalAmount, 0);
    });
  });
}
