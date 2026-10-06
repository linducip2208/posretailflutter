import 'package:flutter_test/flutter_test.dart';
import 'package:pos_retail/models/product.dart';
import 'package:pos_retail/providers/cart_provider.dart';

Product _p({required int id, required double price, int stock = 100}) {
  return Product(id: id, name: 'P$id', sellingPrice: price, currentStock: stock);
}

void main() {
  group('Cart math', () {
    test('subtotal + diskon item + pajak konsisten', () {
      final cart = CartProvider();
      cart.addItem(_p(id: 1, price: 10000));
      cart.addItem(_p(id: 1, price: 10000));
      cart.addItem(_p(id: 2, price: 5000));
      cart.updateDiscount(1, 10); // 10% untuk item indeks 1 (id 2)
      cart.setTaxPercent(11);

      expect(cart.subtotal, 25000);
      expect(cart.itemDiscounts, 500);
      // pajak = (25000-500)*11% = 2695
      expect(cart.taxAmount, 2695);
      expect(cart.totalAmount, 25000 - 500 + 2695);
    });

    test('quantity 0 menghapus item, bukan crash', () {
      final cart = CartProvider();
      cart.addItem(_p(id: 1, price: 1000));
      cart.updateQuantity(0, 0);
      expect(cart.items, isEmpty);
      expect(cart.totalAmount, 0);
    });

    test('index di luar rentang diabaikan', () {
      final cart = CartProvider();
      cart.removeItem(99);
      cart.updateQuantity(-1, 5);
      cart.updateDiscount(5, 50);
      expect(cart.items, isEmpty);
    });

    test('payload hanya kirim yang dibutuhkan server', () {
      final cart = CartProvider();
      cart.addItem(_p(id: 7, price: 20000));
      final payload = cart.toOrderPayload();
      expect(payload.containsKey('discount_amount'), isFalse);
      expect(payload.containsKey('tax_amount'), isFalse);
      expect(payload.containsKey('unit_price'), isFalse);
      final item = (payload['items'] as List).first as Map;
      expect(item['product_id'], 7);
      expect(item['quantity'], 1);
    });
  });
}
