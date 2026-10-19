import 'package:flutter_test/flutter_test.dart';
import 'package:pos_retail/models/product.dart';
import 'package:pos_retail/providers/cart_provider.dart';

Product _product({List<ProductVariant> variants = const []}) {
  return Product(
    id: 10,
    name: 'Kaos',
    sellingPrice: 50000,
    currentStock: 20,
    variants: variants,
  );
}

void main() {
  group('Keranjang + varian', () {
    test('produk sama digabung; varian berbeda jadi baris terpisah', () {
      final cart = CartProvider();
      final p = _product(
        variants: [
          ProductVariant(
            id: 1,
            name: 'M',
            sellingPrice: 52000,
            currentStock: 5,
          ),
          ProductVariant(
            id: 2,
            name: 'L',
            sellingPrice: 54000,
            currentStock: 4,
          ),
        ],
      );

      cart.addItem(p, variant: p.variants[0]);
      cart.addItem(p, variant: p.variants[0]);
      cart.addItem(p, variant: p.variants[1]);

      expect(cart.items.length, 2);
      expect(cart.items[0].quantity, 2);
      expect(cart.items[1].quantity, 1);
      expect(cart.items[0].unitPrice, 52000);
      expect(cart.items[1].unitPrice, 54000);
      expect(cart.totalAmount, 52000 * 2 + 54000);
    });

    test('produk tanpa varian memakai harga produk', () {
      final cart = CartProvider();
      cart.addItem(_product());
      expect(cart.items.single.unitPrice, 50000);
      expect(cart.items.single.displayName, 'Kaos');
    });

    test('displayName varian + lineKey unik per varian', () {
      final cart = CartProvider();
      final p = _product(
        variants: [
          ProductVariant(
            id: 1,
            name: 'M',
            sellingPrice: 52000,
            currentStock: 5,
          ),
        ],
      );
      cart.addItem(p, variant: p.variants.first);
      expect(cart.items.single.displayName, 'Kaos · M');
      expect(cart.items.single.lineKey, '10:1');
    });

    test('quantity di atas batas server dipangkas ke maxQuantity', () {
      final cart = CartProvider();
      cart.addItem(_product());
      cart.updateQuantity(0, 100000);
      expect(cart.items.single.quantity, CartProvider.maxQuantity);
    });

    test(
      'payload checkout mengirim product_variant_id (null untuk non-varian)',
      () {
        final cart = CartProvider();
        final p = _product(
          variants: [
            ProductVariant(
              id: 3,
              name: 'XL',
              sellingPrice: 55000,
              currentStock: 2,
            ),
          ],
        );
        cart.addItem(p, variant: p.variants.first);
        cart.addItem(_product(), variant: null);

        final payload = cart.toOrderPayload();
        final items = payload['items'] as List;
        expect(items.length, 2);
        expect(items[0]['product_id'], 10);
        expect(items[0]['product_variant_id'], 3);
        expect(items[0]['quantity'], 1);
        expect(items[1]['product_variant_id'], isNull);
        // Client tidak mengirim pajak/diskon total — server yang menghitung.
        expect(payload.containsKey('tax_percent'), isFalse);
        expect(payload.containsKey('discount_amount'), isFalse);
      },
    );

    test('clear mengosongkan item, pelanggan, dan pajak', () {
      final cart = CartProvider();
      cart.addItem(_product());
      cart.setCustomer(5, 'Budi');
      cart.setTaxPercent(11);
      cart.clear();
      expect(cart.items, isEmpty);
      expect(cart.customerId, isNull);
      expect(cart.taxPercent, 0);
    });
  });
}
