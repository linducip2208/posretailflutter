import 'package:flutter/material.dart';
import '../models/order.dart';
import '../services/api_service.dart';

class OrderProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  List<Order> _orders = [];
  bool _isLoading = false;
  String? _error;

  List<Order> get orders => _orders;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchTodayOrders() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.get('/orders/today');
      _orders = (response['data'] as List)
          .map((json) => Order.fromJson(json))
          .toList();
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<Order?> createOrder(Map<String, dynamic> payload) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.post('/orders', body: payload);
      final order = Order.fromJson(response['data'] ?? response);
      _isLoading = false;
      notifyListeners();
      return order;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<Order?> getOrderDetail(int id) async {
    try {
      final response = await _api.get('/orders/$id');
      return Order.fromJson(response['data'] ?? response);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }
}
