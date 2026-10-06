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

  static const int _maxAttempts = 10;

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(p.join(dbPath, 'pos_offline.db'),
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
        CREATE TABLE products (
          id INTEGER PRIMARY KEY,
          outlet_id INTEGER,
          name TEXT, sku TEXT, barcode TEXT,
          selling_price REAL, current_stock INTEGER,
          image TEXT, category_name TEXT,
          updated_at TEXT
        )
      ''');
          await db.execute('''
        CREATE TABLE product_variants (
          id INTEGER PRIMARY KEY,
          product_id INTEGER,
          outlet_id INTEGER,
          name TEXT, sku TEXT, barcode TEXT,
          selling_price REAL, current_stock INTEGER,
          updated_at TEXT
        )
      ''');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_pv_outlet_barcode ON product_variants(outlet_id, barcode)');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_products_outlet ON products(outlet_id)');
          await _createOrdersTable(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createOrdersTable(db);
          }
          if (oldVersion < 3) {
            await _upgradeProductsV3(db);
          }
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

  double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
  int _int(dynamic v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

  Future<void> _upgradeProductsV3(Database db) async {
    // v3: cache outlet-aware + tabel varian. Tanpa DELETE massal.
    final cols = await db.rawQuery('PRAGMA table_info(products)');
    final names = cols.map((c) => c['name'] as String).toSet();
    if (!names.contains('outlet_id')) {
      await db.execute('ALTER TABLE products ADD COLUMN outlet_id INTEGER');
    }
    if (!names.contains('updated_at')) {
      await db.execute('ALTER TABLE products ADD COLUMN updated_at TEXT');
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_variants (
        id INTEGER PRIMARY KEY,
        product_id INTEGER,
        outlet_id INTEGER,
        name TEXT, sku TEXT, barcode TEXT,
        selling_price REAL, current_stock INTEGER,
        updated_at TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pv_outlet_barcode ON product_variants(outlet_id, barcode)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_products_outlet ON products(outlet_id)');
  }

  // Cache produk: UPSERT per baris (replace), TANPA delete massal.
  // Hasil search tidak boleh menghapus katalog yang sudah tersimpan,
  // dan cache tidak boleh tercampur antar outlet.
  Future<void> cacheProducts(List<Map<String, dynamic>> products,
      {required int outletId}) async {
    if (_db == null) return;
    final now = DateTime.now().toIso8601String();
    final batch = _db!.batch();
    for (final p in products) {
      final pid = _int(p['id']);
      batch.insert(
        'products',
        {
          'id': pid,
          'outlet_id': outletId,
          'name': p['name']?.toString(),
          'sku': p['sku']?.toString(),
          'barcode': p['barcode']?.toString(),
          'selling_price': _num(p['selling_price']),
          'current_stock': _int(p['current_stock']),
          'image': p['image']?.toString(),
          'category_name': p['category'] is Map
              ? p['category']['name']?.toString()
              : p['category_name']?.toString(),
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final variants = p['variants'];
      if (variants is List) {
        for (final v in variants) {
          if (v is! Map<String, dynamic>) continue;
          batch.insert(
            'product_variants',
            {
              'id': _int(v['id']),
              'product_id': pid,
              'outlet_id': outletId,
              'name': v['name']?.toString(),
              'sku': v['sku']?.toString(),
              'barcode': v['barcode']?.toString(),
              'selling_price': _num(v['selling_price'] ?? p['selling_price']),
              'current_stock': _int(v['current_stock'] ?? 0),
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    }
    await batch.commit(noResult: true);
  }

  // Search products from local cache (selalu dibatasi outlet aktif).
  Future<List<Map<String, dynamic>>> searchProducts(String? query,
      {required int outletId}) async {
    if (_db == null) return [];
    if (query == null || query.isEmpty) {
      return _db!.query('products',
          where: 'outlet_id = ?', whereArgs: [outletId], limit: 50);
    }
    return _db!.query('products',
        where: 'outlet_id = ? AND (name LIKE ? OR sku LIKE ? OR barcode = ?)',
        whereArgs: [outletId, '%$query%', '%$query%', query],
        limit: 50);
  }

  Future<Map<String, dynamic>?> getProductByBarcode(String barcode,
      {required int outletId}) async {
    if (_db == null || barcode.isEmpty) return null;
    final results = await _db!.query('products',
        where: 'outlet_id = ? AND barcode = ?',
        whereArgs: [outletId, barcode],
        limit: 1);
    if (results.isNotEmpty) return results.first;
    // Fallback: barcode milik varian.
    final v = await _db!.query('product_variants',
        where: 'outlet_id = ? AND barcode = ?',
        whereArgs: [outletId, barcode],
        limit: 1);
    if (v.isEmpty) return null;
    final parent = await _db!.query('products',
        where: 'id = ?', whereArgs: [v.first['product_id']], limit: 1);
    if (parent.isEmpty) return null;
    return {...parent.first, ...v.first, 'id': parent.first['id']};
  }

  Future<void> _createOrdersTable(Database db) async {
    // Idempotent: aman dipanggil dari onCreate maupun onUpgrade.
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='offline_orders'");
    if (tables.isEmpty) {
      await db.execute('''
        CREATE TABLE offline_orders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          client_uuid TEXT,
          payload TEXT,
          created_at TEXT,
          synced INTEGER DEFAULT 0,
          attempts INTEGER DEFAULT 0,
          last_error TEXT
        )
      ''');
      return;
    }
    final cols = await db.rawQuery('PRAGMA table_info(offline_orders)');
    final names = cols.map((c) => c['name'] as String).toSet();
    if (!names.contains('client_uuid')) {
      await db.execute('ALTER TABLE offline_orders ADD COLUMN client_uuid TEXT');
    }
    if (!names.contains('attempts')) {
      await db.execute('ALTER TABLE offline_orders ADD COLUMN attempts INTEGER DEFAULT 0');
    }
    if (!names.contains('last_error')) {
      await db.execute('ALTER TABLE offline_orders ADD COLUMN last_error TEXT');
    }
  }

  // Queue order for later sync. client_uuid wajib (idempotency server).
  Future<void> queueOrder(Map<String, dynamic> payload) async {
    if (_db == null) return;
    await _db!.insert('offline_orders', {
      'client_uuid': payload['client_uuid']?.toString(),
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'synced': 0,
    });
  }

  // Sync pending orders via /orders/sync-batch (idempoten via client_uuid).
  // Hanya ditandai synced=1 jika server status created/duplicate.
  // Gagal = attempts+1 + last_error; lewat batas → berhenti retry otomatis
  // (tetap tampil di badge agar kasir tahu), tanpa loop infinite.
  Future<int> syncPendingOrders() async {
    if (_db == null || !_isOnline) return 0;

    final pending = await _db!.query('offline_orders',
        where: 'synced = 0 AND attempts < $_maxAttempts', orderBy: 'id ASC');
    if (pending.isEmpty) return 0;

    final entries = <Map<String, dynamic>>[];
    for (final order in pending) {
      try {
        entries.add(Map<String, dynamic>.from(
            jsonDecode(order['payload'] as String)));
      } catch (_) {
        await _db!.update(
            'offline_orders',
            {'attempts': _maxAttempts, 'last_error': 'Payload rusak'},
            where: 'id = ?',
            whereArgs: [order['id']]);
      }
    }
    if (entries.isEmpty) return 0;

    Map<String, Map<String, dynamic>> byUuid = {};
    try {
      final res = await ApiService()
          .post('/orders/sync-batch', body: {'orders': entries});
      final data = res is Map ? res['data'] : null;
      if (data is List) {
        for (final r in data) {
          if (r is Map) byUuid[r['client_uuid']?.toString() ?? ''] = Map<String, dynamic>.from(r);
        }
      }
    } catch (_) {
      // Jaringan mati di tengah jalan — semua tetap pending, coba lagi nanti.
      return 0;
    }

    int synced = 0;
    for (final order in pending) {
      final uuid = order['client_uuid']?.toString() ?? '';
      final r = byUuid[uuid];
      if (r != null &&
          (r['status'] == 'created' || r['status'] == 'duplicate')) {
        await _db!.update('offline_orders', {
          'synced': 1,
          'last_error': null,
        }, where: 'id = ?', whereArgs: [order['id']]);
        synced++;
      } else {
        await _db!.update(
            'offline_orders',
            {
              'attempts': ((order['attempts'] as int?) ?? 0) + 1,
              'last_error': r?['message']?.toString() ?? 'Gagal sinkron',
            },
            where: 'id = ?',
            whereArgs: [order['id']]);
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
