import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/api_service.dart';
import '../utils/formatters.dart';

class BestSeller {
  final int productId;
  final String name;
  final int qty;
  final double revenue;

  const BestSeller({
    required this.productId,
    required this.name,
    required this.qty,
    required this.revenue,
  });
}

class PaymentBreakdown {
  final String name;
  final int count;
  final double amount;

  const PaymentBreakdown({
    required this.name,
    required this.count,
    required this.amount,
  });
}

/// Data laporan dihitung dari endpoint pesanan nyata (`/orders/history`)
/// yang sudah discope ke outlet aktif. Tidak ada angka karangan:
/// bila gagal, [error] terisi dan UI wajib menampilkan error + retry.
class ReportProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  static const int maxRangeDays = 93; // batas keras backend
  static const int historyLimit = 500; // limit keras backend

  bool _isLoading = false;
  String? _error;

  List<Order> _orders = [];
  int _totalOrders = 0;
  double _revenue = 0;
  int _paidOrders = 0;
  int _unpaidOrders = 0;
  List<BestSeller> _bestSellers = [];
  List<PaymentBreakdown> _paymentBreakdown = [];
  bool _truncated = false;

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Order> get orders => List.unmodifiable(_orders);
  int get totalOrders => _totalOrders;
  double get revenue => _revenue;
  int get paidOrders => _paidOrders;
  int get unpaidOrders => _unpaidOrders;
  double get avgOrder => _totalOrders > 0 ? _revenue / _totalOrders : 0;
  List<BestSeller> get bestSellers => List.unmodifiable(_bestSellers);
  List<PaymentBreakdown> get paymentBreakdown =>
      List.unmodifiable(_paymentBreakdown);
  bool get truncated => _truncated;

  Future<void> load({
    required DateTime start,
    required DateTime end,
    int? outletId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final days = end.difference(start).inDays;

    try {
      if (days > maxRangeDays) {
        throw ApiException(
          statusCode: 422,
          message:
              'Rentang tanggal maksimal $maxRangeDays hari. Persempit periode.',
        );
      }

      final response = await _api.get(
        '/orders/history',
        query: {
          'start_date': Fmt.dateForApi(start),
          'end_date': Fmt.dateForApi(end),
          'outlet_id': outletId?.toString(),
        },
      );

      final dynamic data = response is Map
          ? (response['data'] ?? response)
          : response;
      final rawList = data is List
          ? data.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];

      _orders = rawList.map(Order.fromJson).toList();
      _truncated = rawList.length >= historyLimit;
      _compute(rawList);
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
      _resetTotals();
    } catch (_) {
      _error = 'Gagal memuat laporan. Periksa koneksi lalu coba lagi.';
      _resetTotals();
    }

    _isLoading = false;
    notifyListeners();
  }

  void _resetTotals() {
    _orders = [];
    _totalOrders = 0;
    _revenue = 0;
    _paidOrders = 0;
    _unpaidOrders = 0;
    _bestSellers = [];
    _paymentBreakdown = [];
    _truncated = false;
  }

  void _compute(List<Map<String, dynamic>> raw) {
    double asDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0;
    }

    _totalOrders = raw.length;
    _revenue = raw.fold<double>(0, (s, o) => s + asDouble(o['total_amount']));
    _paidOrders = raw.where((o) => o['payment_status'] == 'paid').length;
    _unpaidOrders = _totalOrders - _paidOrders;

    // Produk terlaris — dari order items (relasi product dimuat backend).
    final byProduct = <int, BestSeller>{};
    for (final order in raw) {
      final items = order['items'];
      if (items is! List) continue;
      for (final item in items) {
        if (item is! Map) continue;
        final product = item['product'];
        final id = (item['product_id'] as num?)?.toInt() ?? 0;
        final name = product is Map
            ? (product['name']?.toString() ?? 'Produk #$id')
            : 'Produk #$id';
        final qty = (item['quantity'] as num?)?.toInt() ?? 0;
        final revenue = asDouble(item['subtotal']);
        final prev = byProduct[id];
        byProduct[id] = BestSeller(
          productId: id,
          name: name,
          qty: (prev?.qty ?? 0) + qty,
          revenue: (prev?.revenue ?? 0) + revenue,
        );
      }
    }
    final best = byProduct.values.toList()
      ..sort((a, b) => b.qty.compareTo(a.qty));
    _bestSellers = best.take(10).toList();
  }

  /// Rekap per metode pembayaran. Endpoint orders hanya mengirim
  /// `payment_method_id`; nama metode dipetakan dari `/payment-methods`.
  Future<void> loadPaymentBreakdownIfNeeded({required int? outletId}) async {
    if (_orders.isEmpty) return;
    final names = await _paymentMethodNames();
    final totals = <int, PaymentBreakdown>{};
    for (final order in _orders) {
      final payments = order.payments;
      if (payments == null) continue;
      for (final p in payments) {
        final id = p.paymentMethodId;
        final name = names[id] ?? 'Metode #$id';
        final prev = totals[id];
        totals[id] = PaymentBreakdown(
          name: name,
          count: (prev?.count ?? 0) + 1,
          amount: (prev?.amount ?? 0) + p.amount,
        );
      }
    }
    _paymentBreakdown = totals.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    notifyListeners();
  }

  static Map<int, String>? _methodNamesCache;

  Future<Map<int, String>> _paymentMethodNames() async {
    final cached = _methodNamesCache;
    if (cached != null) return cached;
    try {
      final response = await _api.get('/payment-methods');
      final dynamic data = response is Map
          ? (response['data'] ?? response)
          : response;
      final map = <int, String>{};
      if (data is List) {
        for (final m in data.whereType<Map<String, dynamic>>()) {
          final id = (m['id'] as num?)?.toInt() ?? 0;
          final name = m['name']?.toString() ?? '';
          if (id > 0 && name.isNotEmpty) map[id] = name;
        }
      }
      _methodNamesCache = map;
      return map;
    } catch (_) {
      return const {};
    }
  }
}
