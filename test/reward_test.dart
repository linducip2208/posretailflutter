import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/screens/loyalty/reward_list_screen.dart';
import 'package:pos_retail/services/api_service.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => LangProvider())],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

/// Bentuk backend nyata: GET /loyalty/rewards (envelope, active=true)
/// {id, name, points_required, discount_type, discount_value, active}.
MockClient _client({int status = 200}) {
  return MockClient((request) async {
    if (request.url.path.endsWith('/loyalty/rewards')) {
      if (status != 200) {
        return http.Response(
          jsonEncode({'message': 'Data tidak ditemukan.'}),
          status,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'data': [
            {
              'id': 1,
              'name': 'Kopi Gratis',
              'points_required': 100,
              'discount_type': 'fixed',
              'discount_value': '10000.00',
              'active': true,
            },
            {
              'id': 2,
              'name': 'Voucher 10rb',
              'points_required': 200,
              'discount_type': 'fixed',
              'discount_value': '10000.00',
              'active': true,
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 404);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ApiService.client = http.Client();
  });

  testWidgets('daftar reward tampil dari server', (tester) async {
    ApiService.client = _client();

    await tester.pumpWidget(_wrap(const RewardListScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Kopi Gratis'), findsOneWidget);
    expect(find.textContaining('100'), findsWidgets);
    expect(find.text('Voucher 10rb'), findsOneWidget);
  });

  testWidgets('404 jujur + tombol retry memuat ulang', (tester) async {
    var calls = 0;
    ApiService.client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return http.Response(
          jsonEncode({'message': 'Data tidak ditemukan.'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'data': [
            {
              'id': 1,
              'name': 'Kopi Gratis',
              'points_required': 100,
              'active': true,
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(_wrap(const RewardListScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Data tidak ditemukan.'), findsOneWidget);
    expect(find.text('Coba Lagi'), findsOneWidget);

    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();

    expect(find.text('Kopi Gratis'), findsOneWidget);
  });
}
