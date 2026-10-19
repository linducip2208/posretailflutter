import 'package:flutter/material.dart';

import '../models/product.dart';
import '../utils/formatters.dart';

class CartItem {
  final Product product;

  /// Varian terpilih (null bila produk tanpa varian).
  final ProductVariant? variant;
  int quantity;
  double discountPercent;

  CartItem({
    required this.product,
    this.variant,
    this.quantity = 1,
    this.discountPercent = 0,
  });

  /// Identitas baris keranjang: produk + varian.
  String get lineKey => '${product.id}:${variant?.id ?? 0}';

  double get unitPrice => variant != null && variant!.sellingPrice > 0
      ? variant!.sellingPrice
      : product.sellingPrice;

  double get lineSubtotal => unitPrice * quantity;
  double get discountAmount => lineSubtotal * (discountPercent / 100);
  double get subtotal => lineSubtotal - discountAmount;

  String get displayName =>
      variant == null ? product.name : '${product.name} · ${variant!.name}';
}

/// Keranjang kasir.
///
/// Aturan uang mengikuti server (sumber kebenaran):
/// - Diskon hanya per item (`discount_percent`) — API tidak menerima diskon
///   total transaksi manual, jadi tidak dihitung di klien.
/// - Pajak default 0 karena API checkout mobile selalu menghitung tanpa pajak
///   (`use_tax=false`). Menampilkan pajak fiktif membuat pembayaran kurang.
class CartProvider extends ChangeNotifier {
  static const int maxQuantity = 999; // batas validasi server: 1..1000

  final List<CartItem> _items = [];
  double _taxPercent = 0;
  int? _customerId;
  String? _customerName;

  List<CartItem> get items => List.unmodifiable(_items);
  double get taxPercent => _taxPercent;
  int? get customerId => _customerId;
  String? get customerName => _customerName;
  int get itemCount => _items.length;
  int get totalQuantity => _items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal {
    return _items.fold(0, (sum, item) => sum + item.lineSubtotal);
  }

  double get itemDiscounts {
    return _items.fold(0, (sum, item) => sum + item.discountAmount);
  }

  double get totalDiscountAmount => itemDiscounts;

  double get taxableBase => subtotal - totalDiscountAmount;

  double get taxAmount => taxableBase * _taxPercent / 100;

  double get totalAmount => taxableBase + taxAmount;

  String get subtotalFormatted => Fmt.rupiah(subtotal);
  String get totalFormatted => Fmt.rupiah(totalAmount);

  void addItem(Product product, {ProductVariant? variant}) {
    final key = '${product.id}:${variant?.id ?? 0}';
    final existing = _items.where((item) => item.lineKey == key);
    if (existing.isNotEmpty) {
      if (existing.first.quantity < maxQuantity) {
        existing.first.quantity++;
      }
    } else {
      _items.add(CartItem(product: product, variant: variant));
    }
    notifyListeners();
  }

  void removeItem(int index) {
    if (index >= 0 && index < _items.length) {
      _items.removeAt(index);
      notifyListeners();
    }
  }

  void updateQuantity(int index, int qty) {
    if (index >= 0 && index < _items.length) {
      if (qty <= 0) {
        _items.removeAt(index);
      } else if (qty > maxQuantity) {
        _items[index].quantity = maxQuantity;
      } else {
        _items[index].quantity = qty;
      }
      notifyListeners();
    }
  }

  void updateDiscount(int index, double percent) {
    if (index >= 0 && index < _items.length) {
      _items[index].discountPercent = percent.clamp(0, 100);
      notifyListeners();
    }
  }

  void setTaxPercent(double percent) {
    _taxPercent = percent < 0 ? 0 : percent;
    notifyListeners();
  }

  void setCustomer(int? id, String? name) {
    _customerId = id;
    _customerName = name;
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _taxPercent = 0;
    _customerId = null;
    _customerName = null;
    notifyListeners();
  }

  Map<String, dynamic> toOrderPayload() {
    // Sumber kebenaran = server: total/diskon/pajak dihitung ulang di
    // CheckoutService. Client hanya kirim item + varian + diskon% per item.
    return {
      'customer_id': _customerId,
      'items': _items
          .map(
            (item) => {
              'product_id': item.product.id,
              'product_variant_id': item.variant?.id,
              'quantity': item.quantity,
              'discount_percent': item.discountPercent,
            },
          )
          .toList(),
    };
  }
}
