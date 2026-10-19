import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/offline_sync_service.dart';

/// Katalog produk untuk tab Produk dan POS.
///
/// Sumber kebenaran tetap server; cache SQLite dipakai sebagai fallback
/// saat offline (selalu dibatasi outlet aktif).
class ProductProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final OfflineSyncService _offline = OfflineSyncService();

  List<Product> _products = [];
  List<Category> _categories = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _usingOfflineCache = false;
  String? _error;
  String _search = '';
  int? _categoryId;
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  int? _outletId;

  List<Product> get products => List.unmodifiable(_products);
  List<Category> get categories => List.unmodifiable(_categories);
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get usingOfflineCache => _usingOfflineCache;
  String? get error => _error;
  String get search => _search;
  int? get categoryId => _categoryId;
  int get total => _total;
  bool get hasMore => _page < _lastPage;

  void setOutletId(int? outletId) {
    _outletId = outletId;
  }

  void setSearch(String value) {
    _search = value;
  }

  void setCategory(int? categoryId) {
    _categoryId = categoryId;
    refresh();
  }

  Future<void> loadCategories() async {
    if (_categories.isNotEmpty) return;
    try {
      final response = await _api.get('/categories');
      final dynamic data = response is Map
          ? (response['categories'] ?? response['data'] ?? response)
          : response;
      if (data is List) {
        _categories = data
            .whereType<Map<String, dynamic>>()
            .map(Category.fromJson)
            .toList();
        notifyListeners();
      }
    } catch (_) {
      // Kategori bersifat pelengkap — kegagalan tidak memblokir katalog.
    }
  }

  Future<void> refresh() async {
    _page = 1;
    _lastPage = 1;
    await _fetch(reset: true);
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !hasMore) return;
    _page += 1;
    await _fetch(reset: false);
  }

  Future<void> _fetch({required bool reset}) async {
    if (reset) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    } else {
      _isLoadingMore = true;
      notifyListeners();
    }

    try {
      final response = await _api.get(
        '/products',
        query: {
          'search': _search.isEmpty ? null : _search,
          'category_id': _categoryId?.toString(),
          'per_page': '50',
          'page': _page.toString(),
        },
      );

      final dynamic data = response is Map
          ? (response['data'] ?? response)
          : response;
      final meta = response is Map ? response['meta'] : null;
      final list = data is List
          ? data.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];

      final parsed = list.map(Product.fromJson).toList();
      _products = reset ? parsed : [..._products, ...parsed];
      _usingOfflineCache = false;
      _error = null;

      if (meta is Map) {
        _lastPage = (meta['last_page'] as num?)?.toInt() ?? 1;
        _total = (meta['total'] as num?)?.toInt() ?? _products.length;
      } else {
        _lastPage = 1;
        _total = _products.length;
      }

      // Simpan cache lokal outlet-aware (hanya halaman penuh katalog).
      final outletId = _outletId;
      if (outletId != null && list.isNotEmpty) {
        await _offline.cacheProducts(list, outletId: outletId);
      }
    } on ApiNetworkException catch (_) {
      if (reset) {
        await _loadFromOfflineCache();
      } else {
        _error = 'Koneksi terputus saat memuat halaman berikutnya.';
        _page -= 1;
      }
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Gagal memuat produk. Coba lagi.';
    }

    _isLoading = false;
    _isLoadingMore = false;
    notifyListeners();
  }

  Future<void> _loadFromOfflineCache() async {
    final outletId = _outletId;
    if (outletId == null) {
      _error = 'Pilih outlet dulu untuk memuat produk offline.';
      return;
    }
    try {
      final rows = await _offline.searchProducts(
        _search.isEmpty ? null : _search,
        outletId: outletId,
      );
      _products = rows.map(Product.fromJson).toList();
      _usingOfflineCache = true;
      _error = _products.isEmpty
          ? 'Tidak ada cache produk untuk outlet ini. Sambungkan ke internet untuk memuat katalog.'
          : null;
      _lastPage = 1;
      _total = _products.length;
    } catch (_) {
      _error = 'Gagal membaca cache produk.';
    }
  }
}
