import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_retail/services/api_service.dart';
import 'package:pos_retail/services/offline_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final offline = OfflineSyncService();

  setUpAll(() {
    // sqflite di desktop/CI: pakai implementasi FFI (sqlite3 native).
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await offline.dispose();
    // ':memory:' → DB bersih per test, tidak menyentuh data aplikasi.
    await offline.init(databasePath: ':memory:');
  });

  tearDown(() async {
    await offline.dispose();
    ApiService.client = http.Client();
    ApiService.onUnauthorized = null;
  });

  Future<void> queueOrders(int count) async {
    for (var i = 0; i < count; i++) {
      await offline.queueOrder({
        'client_uuid': 'uuid-$i',
        'outlet_id': 1,
        'items': [
          {'product_id': 1, 'quantity': 1, 'price': 1000},
        ],
        'payments': [
          {'payment_method_id': 1, 'amount': 1000},
        ],
      });
    }
  }

  MockClient successClient(List<int> batchSizes, {String status = 'created'}) {
    return MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final orders = body['orders'] as List;
      batchSizes.add(orders.length);
      return http.Response(
        jsonEncode({
          'data': orders
              .map(
                (o) => {
                  'client_uuid': (o as Map)['client_uuid'],
                  'status': status,
                },
              )
              .toList(),
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
  }

  test(
    'sync mengirim maksimal 50 per batch dan loop sampai antrean habis',
    () async {
      await queueOrders(60);
      expect(await offline.getPendingCount(), 60);

      final batchSizes = <int>[];
      ApiService.client = successClient(batchSizes);

      final synced = await offline.syncPendingOrders(force: true);

      expect(synced, 60);
      expect(batchSizes, [50, 10]);
      expect(await offline.getPendingCount(), 0);
    },
  );

  test('status duplicate dari server dianggap sukses (idempoten)', () async {
    await queueOrders(1);
    ApiService.client = successClient(<int>[], status: 'duplicate');

    expect(await offline.syncPendingOrders(force: true), 1);
    expect(await offline.getPendingCount(), 0);
  });

  test(
    'batch ditolak server (422) → attempts naik + last_error, data aman',
    () async {
      await queueOrders(1);
      ApiService.client = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Validasi gagal'}),
          422,
          headers: {'content-type': 'application/json'},
        );
      });

      expect(await offline.syncPendingOrders(force: true), 0);
      expect(await offline.getPendingCount(), 1);

      final rows = await offline.getPendingOrders();
      expect(rows.single['attempts'], 1);
      expect(rows.single['last_error'], contains('Validasi gagal'));

      // Tanpa force: masih dalam jendela backoff → tidak dicoba lagi.
      expect(await offline.syncPendingOrders(), 0);
    },
  );

  test('kegagalan jaringan tidak menambah attempts (tanpa penalti)', () async {
    await queueOrders(1);
    ApiService.client = MockClient((request) async {
      throw http.ClientException('connection refused');
    });

    expect(await offline.syncPendingOrders(force: true), 0);
    expect(await offline.getPendingCount(), 1);

    final rows = await offline.getPendingOrders();
    expect((rows.single['attempts'] as int?) ?? 0, 0);
  });

  test(
    'ApiService memetakan kegagalan jaringan ke ApiNetworkException',
    () async {
      ApiService.client = MockClient((request) async {
        throw http.ClientException('connection refused');
      });

      await expectLater(
        ApiService().get('/products', auth: false),
        throwsA(isA<ApiNetworkException>()),
      );
    },
  );

  test('401 memicu onUnauthorized sekali saja (debounce)', () async {
    var calls = 0;
    ApiService.onUnauthorized = () => calls++;

    ApiService.client = MockClient((request) async {
      return http.Response(
        jsonEncode({'message': 'Unauthenticated.'}),
        401,
        headers: {'content-type': 'application/json'},
      );
    });

    for (var i = 0; i < 3; i++) {
      await expectLater(
        ApiService().get('/user'),
        throwsA(isA<ApiException>()),
      );
    }

    expect(calls, 1);
  });
}
