import 'package:flutter_test/flutter_test.dart';
import 'package:pos_retail/models/order.dart';
import 'package:pos_retail/models/outlet.dart';
import 'package:pos_retail/models/product.dart';
import 'package:pos_retail/models/user.dart';

void main() {
  group('Model parsing tahan data aneh', () {
    test('Order.fromJson format backend (string desimal)', () {
      final o = Order.fromJson({
        'id': 1,
        'order_number': 'ORD-1',
        'customer_id': null,
        'customer_name': 'Budi',
        'outlet_id': 2,
        'outlet_name': 'Cabang',
        'queue_number': '001',
        'subtotal': '10000.00',
        'discount_amount': '0.00',
        'tax_amount': '1100.00',
        'total_amount': '11100.00',
        'payment_status': 'paid',
        'order_status': 'completed',
        'created_at': '2026-10-06',
        'items': [
          {
            'id': 1,
            'product_id': 5,
            'product': {'name': 'Indomie'},
            'quantity': 2,
            'unit_price': '5000.00',
            'subtotal': '10000.00',
          }
        ],
        'payments': [
          {
            'id': 1,
            'payment_method_id': 2,
            'payment_method': {'name': 'Tunai'},
            'amount': '11100.00',
            'status': 'success',
          }
        ],
      });
      expect(o.totalAmount, 11100);
      expect(o.items!.first.productName, 'Indomie');
      expect(o.payments!.first.methodName, 'Tunai');
    });

    test('Order.fromJson tidak crash untuk JSON rusak', () {
      final o = Order.fromJson({
        'id': 'x',
        'items': 'bukan-list',
        'payments': [
          {'id': 1}
        ],
        'product': 'string',
      });
      expect(o.id, 0);
      expect(o.items, isNull);
      expect(o.payments!.length, 1);
      expect(o.totalAmount, 0);
    });

    test('Product.fromJson turunkan hasVariants dari relasi', () {
      final p = Product.fromJson({
        'id': 1,
        'name': 'Kaos',
        'selling_price': 50000,
        'current_stock': 10,
        'category': {'name': 'Fashion'},
        'variants': [
          {'id': 1}
        ],
      });
      expect(p.hasVariants, isTrue);
      expect(p.categoryName, 'Fashion');
    });

    test('User.fromJson bawa outlets untuk seleksi outlet', () {
      final u = User.fromJson({
        'id': 1,
        'name': 'Kasir',
        'email': 'k@toko.id',
        'role': 'kasir',
        'outlets': [
          {'id': 1, 'name': 'Pusat', 'code': 'P1'},
          {'id': 2, 'name': 'Cabang'}
        ],
      });
      expect(u.outlets.length, 2);
      expect(u.outlets.first, isA<Outlet>());
    });

    test('User lama tanpa outlets tetap valid', () {
      final u = User.fromJson({'id': 1, 'name': 'x', 'email': 'y'});
      expect(u.outlets, isEmpty);
    });
  });
}
