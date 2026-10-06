import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';

class CartItem {
  final Product product;
  int quantity;
  double discountPercent;

  CartItem({
    required this.product,
    this.quantity = 1,
    this.discountPercent = 0,
  });

  double get unitPrice => product.sellingPrice;
  double get subtotal => (unitPrice * quantity) * (1 - discountPercent / 100);
}

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];
  double _totalDiscount = 0;
  double _taxPercent = 11;
  int? _customerId;
  String? _customerName;

  List<CartItem> get items => List.unmodifiable(_items);
  double get totalDiscount => _totalDiscount;
  double get taxPercent => _taxPercent;
  int? get customerId => _customerId;
  String? get customerName => _customerName;
  int get itemCount => _items.length;

  double get subtotal {
    return _items.fold(0, (sum, item) => sum + (item.product.sellingPrice * item.quantity));
  }

  double get itemDiscounts {
    return _items.fold(0, (sum, item) {
      final raw = item.product.sellingPrice * item.quantity;
      return sum + (raw * item.discountPercent / 100);
    });
  }

  double get totalDiscountAmount => itemDiscounts + _totalDiscount;

  double get taxAmount => (subtotal - totalDiscountAmount) * _taxPercent / 100;

  double get totalAmount => subtotal - totalDiscountAmount + taxAmount;

  String get subtotalFormatted => _format(subtotal);
  String get totalFormatted => _format(totalAmount);

  String _format(double amount) {
    return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0).format(amount);
  }

  void addItem(Product product) {
    final existing = _items.where((item) => item.product.id == product.id);
    if (existing.isNotEmpty) {
      existing.first.quantity++;
    } else {
      _items.add(CartItem(product: product));
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
      } else {
        _items[index].quantity = qty;
      }
      notifyListeners();
    }
  }

  void updateDiscount(int index, double percent) {
    if (index >= 0 && index < _items.length) {
      _items[index].discountPercent = percent;
      notifyListeners();
    }
  }

  void setTotalDiscount(double amount) {
    _totalDiscount = amount;
    notifyListeners();
  }

  void setTaxPercent(double percent) {
    _taxPercent = percent;
    notifyListeners();
  }

  void setCustomer(int? id, String? name) {
    _customerId = id;
    _customerName = name;
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _totalDiscount = 0;
    _taxPercent = 11;
    _customerId = null;
    _customerName = null;
    notifyListeners();
  }

  Map<String, dynamic> toOrderPayload() {
    return {
      'customer_id': _customerId,
      'items': _items.map((item) => {
        'product_id': item.product.id,
        'quantity': item.quantity,
        'unit_price': item.unitPrice,
        'discount_percent': item.discountPercent,
      }).toList(),
      'discount_amount': _totalDiscount,
      'tax_amount': taxAmount,
    };
  }
}
