import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_retail/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ApiService.client = http.Client();
    ApiService.onUnauthorized = null;
  });

  test('query parameter di-encode dan nilai kosong/null dihilangkan', () async {
    Uri? captured;
    ApiService.client = MockClient((request) async {
      captured = request.url;
      return http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await ApiService().get(
      '/products',
      query: {'search': 'kaos & celana', 'outlet_id': null, 'category_id': ''},
      auth: false,
    );

    expect(captured, isNotNull);
    expect(captured!.path.endsWith('/products'), isTrue);
    expect(captured!.queryParameters, {'search': 'kaos & celana'});
  });

  test(
    'pesan error 422 dari server dipakai apa adanya + errors diteruskan',
    () async {
      ApiService.client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': 'Stok tidak cukup',
            'errors': {
              'items': ['Stok produk X tidak cukup'],
            },
          }),
          422,
          headers: {'content-type': 'application/json'},
        );
      });

      try {
        await ApiService().post(
          '/orders',
          body: const {'items': []},
          auth: false,
        );
        fail('seharusnya melempar ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, 422);
        expect(e.message, 'Stok tidak cukup');
        expect(e.errors, isA<Map>());
      }
    },
  );

  test('respons tanpa body JSON → pesan manusiawi default', () async {
    ApiService.client = MockClient((request) async {
      return http.Response('', 500);
    });

    try {
      await ApiService().get('/orders/today', auth: false);
      fail('seharusnya melempar ApiException');
    } on ApiException catch (e) {
      expect(e.statusCode, 500);
      expect(e.message, 'Server bermasalah, coba lagi.');
    }
  });

  test('respons non-map (list) diteruskan sebagai list', () async {
    ApiService.client = MockClient((request) async {
      return http.Response(
        jsonEncode([
          {'id': 1},
        ]),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final result = await ApiService().get('/categories', auth: false);
    expect(result, isA<List>());
  });
}
