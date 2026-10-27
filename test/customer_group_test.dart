import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/screens/loyalty/customer_group_screen.dart';
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

  testWidgets('daftar grup tampil dengan diskon + syarat upgrade', (
    tester,
  ) async {
    ApiService.client = MockClient((request) async {
      if (request.url.path.endsWith('/customer-groups')) {
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 1, 'name': 'Regular', 'discount_percent': 0, 'min_spent': 0, 'member_count': 10},
              {'id': 2, 'name': 'Member', 'discount_percent': 5, 'min_spent': 500000, 'member_count': 3},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(_wrap(const CustomerGroupScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Regular'), findsOneWidget);
    expect(find.text('Member'), findsOneWidget);
    expect(find.textContaining('diskon'), findsWidgets);
    expect(find.textContaining('Syarat upgrade'), findsWidgets);
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
            {'id': 1, 'name': 'Regular', 'discount_percent': 0, 'min_spent': 0},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(_wrap(const CustomerGroupScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Data tidak ditemukan.'), findsOneWidget);
    expect(find.text('Coba Lagi'), findsOneWidget);

    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();

    expect(find.text('Regular'), findsOneWidget);
  });
}
