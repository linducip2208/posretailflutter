import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/screens/loyalty/discount_list_screen.dart';
import 'package:pos_retail/services/api_service.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => LangProvider())],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ApiService.client = http.Client();
  });

  testWidgets('daftar template diskon tampil dari server', (tester) async {
    ApiService.client = MockClient((request) async {
      if (request.url.path.endsWith('/discounts')) {
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 1, 'name': 'Promo 10%', 'type': 'percent', 'value': 10, 'active': true},
              {'id': 2, 'name': 'Potongan 5rb', 'type': 'fixed', 'value': 5000, 'active': false},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(_wrap(const DiscountListScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Promo 10%'), findsOneWidget);
    expect(find.text('Potongan 5rb'), findsOneWidget);
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
            {'id': 1, 'name': 'Promo 10%', 'type': 'percent', 'value': 10, 'active': true},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(_wrap(const DiscountListScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Data tidak ditemukan.'), findsOneWidget);
    expect(find.text('Coba Lagi'), findsOneWidget);

    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();

    expect(find.text('Promo 10%'), findsOneWidget);
  });
}
