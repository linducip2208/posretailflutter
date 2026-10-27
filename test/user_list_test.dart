import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/providers/auth_provider.dart';
import 'package:pos_retail/screens/system/user_list_screen.dart';
import 'package:pos_retail/services/api_service.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LangProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
    ],
    child: MaterialApp(home: child),
  );
}

MockClient _okClient() {
  return MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/users')) {
      return http.Response(
        jsonEncode({
          'data': [
            {
              'id': 1,
              'name': 'Budi Kasir',
              'email': 'budi@toko.id',
              'role': 'kasir',
              'active': true,
            },
            {
              'id': 2,
              'name': 'Siti Gudang',
              'email': 'siti@toko.id',
              'role': 'gudang',
              'active': false,
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/roles')) {
      return http.Response(
        jsonEncode({
          'data': [
            {'name': 'kasir'},
            {'name': 'gudang'},
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

  testWidgets('daftar pengguna tampil dari GET /users', (tester) async {
    ApiService.client = _okClient();

    await tester.pumpWidget(_wrap(const UserListScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Budi Kasir'), findsOneWidget);
    expect(find.text('Siti Gudang'), findsOneWidget);
    expect(find.textContaining('Kasir'), findsWidgets);
  });

  testWidgets('404 jujur + tombol Coba Lagi me-retry', (tester) async {
    var calls = 0;
    ApiService.client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return http.Response(
          jsonEncode({'message': 'Belum ada endpoint.'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'data': [
            {'id': 1, 'name': 'Budi Kasir', 'role': 'kasir'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(_wrap(const UserListScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Coba Lagi'), findsOneWidget);
    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();

    expect(calls, 3); // users gagal + roles gagal, retry users (+roles)
    expect(find.text('Budi Kasir'), findsOneWidget);
  });
}
