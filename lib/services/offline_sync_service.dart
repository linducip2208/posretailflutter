import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'api_service.dart';

class OfflineSyncService {
  static final OfflineSyncService _instance = OfflineSyncService._();
  factory OfflineSyncService() => _instance;
  OfflineSyncService._();

  Database? _db;
  bool _isOnline = true;
  final List<void Function(bool)> _listeners = [];

  bool get isOnline => _isOnline;

  void addListener(void Function(bool) callback) {
    _listeners.add(callback);
  }

  void removeListener(void Function(bool) callback) {
    _listeners.remove(callback);
  }

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(p.join(dbPath, 'pos_offline.db'), version: 1,
        onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE products (
          id INTEGER PRIMARY KEY,
          name TEXT, sku TEXT, barcode TEXT,
          selling_price REAL, current_stock INTEGER,
          image TEXT, category_name TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE offline_orders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          payload TEXT,
          created_at TEXT,
          synced INTEGER DEFAULT 0
        )
      ''');
    });

    final connectivity = Connectivity();
    _isOnline = await _checkConnectivity();
    connectivity.onConnectivityChanged.listen((results) async {
      final wasOffline = !_isOnline;
      _isOnline = await _checkConnectivity();
      _notifyListeners();
      if (wasOffline && _isOnline) {
        await syncPendingOrders();
      }
    });
  }

  Future<bool> _checkConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  void _notifyListeners() {
    for (final cb in _listeners) {
      cb(_isOnline);
    }
  }

  // Cache products for offline use
  Future<void> cacheProducts(List<Map<String, dynamic>> products) async {
    if (_db == null) return;
    final batch = _db!.batch();
    batch.delete('products');
    for (final p in products) {
      batch.insert('products', {
        'id': p['id'],
        'name': p['name'],
        'sku': p['sku'],
        'barcode': p['barcode'],
        'selling_price': (p['selling_price'] ?? 0).toDouble(),
        'current_stock': p['current_stock'] ?? 0,
        'image': p['image'],
        'category_name': p['category']?['name'],
      });
    }
    await batch.commit(noResult: true);
  }

  // Search products from local cache
  Future<List<Map<String, dynamic>>> searchProducts(String? query) async {
    if (_db == null) return [];
    if (query == null || query.isEmpty) {
      return _db!.query('products', limit: 50);
    }
    return _db!.query('products',
        where: 'name LIKE ? OR sku LIKE ? OR barcode = ?',
        whereArgs: ['%$query%', '%$query%', query],
        limit: 50);
  }

  Future<Map<String, dynamic>?> getProductByBarcode(String barcode) async {
    if (_db == null) return null;
    final results = await _db!.query('products',
        where: 'barcode = ?', whereArgs: [barcode], limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  // Queue order for later sync
  Future<void> queueOrder(Map<String, dynamic> payload) async {
    if (_db == null) return;
    await _db!.insert('offline_orders', {
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'synced': 0,
    });
  }

  // Sync pending orders when back online.
  // Setiap payload benar-benar di-POST ke /orders dan hanya ditandai
  // synced=1 jika server menerima (2xx). Gagal jaringan/validasi = tetap
  // pending untuk dicoba lagi, jadi tidak ada penjualan offline yang hilang.
  Future<int> syncPendingOrders() async {
    if (_db == null || !_isOnline) return 0;

    final pending = await _db!.query('offline_orders',
        where: 'synced = 0', orderBy: 'id ASC');
    int synced = 0;

    for (final order in pending) {
      try {
        final payload =
            Map<String, dynamic>.from(jsonDecode(order['payload'] as String));
        await ApiService().post('/orders', body: payload);
        await _db!.update('offline_orders', {'synced': 1},
            where: 'id = ?', whereArgs: [order['id']]);
        synced++;
      } catch (_) {
        // Biarkan pending — coba lagi di kesempatan berikutnya.
      }
    }
    return synced;
  }

  Future<int> getPendingCount() async {
    if (_db == null) return 0;
    final result = await _db!.rawQuery(
        'SELECT COUNT(*) as cnt FROM offline_orders WHERE synced = 0');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getPendingOrders() async {
    if (_db == null) return [];
    return _db!.query('offline_orders',
        where: 'synced = 0', orderBy: 'id ASC');
  }

  Future<void> dispose() async {
    await _db?.close();
  }
}
