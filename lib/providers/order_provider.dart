import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/api_service.dart';

/// Sumber data pesanan untuk Beranda/Transaksi/Riwayat.
/// Semua pembacaan memakai outlet aktif agar angka konsisten dengan server.
class OrderProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  List<Order> _orders = [];
  bool _isLoading = false;
  String? _error;
  bool _lastErrorOffline = false;

  List<Order> get orders => List.unmodifiable(_orders);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get lastErrorOffline => _lastErrorOffline;

  /// Pesanan hari ini (server sudah mengecualikan pesanan dibatalkan).
  Future<void> fetchTodayOrders({int? outletId}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _api.get(
        '/orders/today',
        query: {'outlet_id': outletId?.toString()},
      );
      _orders = _parseList(response);
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Gagal memuat pesanan. Coba lagi.';
    }
    _isLoading = false;
    notifyListeners();
  }

  List<Order> _parseList(dynamic response) {
    final dynamic data = response is Map
        ? (response['data'] ?? response)
        : response;
    if (data is! List) return [];
    return data.whereType<Map<String, dynamic>>().map(Order.fromJson).toList();
  }

  /// Membuat pesanan online. Return null jika gagal; cek [error] dan
  /// [lastErrorOffline] untuk membedakan gagal jaringan vs ditolak server.
  Future<Order?> createOrder(Map<String, dynamic> payload) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.post('/orders', body: payload);
      final dynamic data = response is Map
          ? (response['data'] ?? response)
          : response;
      final order = data is Map<String, dynamic> ? Order.fromJson(data) : null;
      _lastErrorOffline = false;
      _error = order == null ? 'Respons server tidak dikenali.' : null;
      _isLoading = false;
      notifyListeners();
      return order;
    } on ApiException catch (e) {
      _lastErrorOffline = e is ApiNetworkException;
      _error = e.message;
      _isLoading = false;
      notifyListeners();
      return null;
    } catch (_) {
      _lastErrorOffline = false;
      _error = 'Transaksi gagal diproses. Coba lagi.';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<Order?> getOrderDetail(int id) async {
    try {
      final response = await _api.get('/orders/$id');
      final dynamic data = response is Map
          ? (response['data'] ?? response)
          : response;
      if (data is! Map<String, dynamic>) return null;
      return Order.fromJson(data);
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return null;
    } catch (_) {
      _error = 'Gagal memuat detail pesanan.';
      notifyListeners();
      return null;
    }
  }
}
