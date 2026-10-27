import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/screens/suppliers/supplier_list_screen.dart';
import 'package:pos_retail/services/api_service.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => LangProvider())],
    child: MaterialApp(home: child),
  );
}

List<Map<String, dynamic>> _rows(List<String> names) => [
  for (var i = 0; i < names.length; i++)
    {
      'id': i + 1,
      'name': names[i],
      'phone': '0812000${i + 1}',
      'email': null,
      'address': null,
    },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ApiService.client = http.Client();
  });

  testWidgets('daftar supplier tampil dari server', (tester) async {
    ApiService.client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path.endsWith('/suppliers')) {
        return http.Response(
          jsonEncode({
            'data': _rows(['PT Maju Jaya', 'Toko Berkah']),
            'meta': {'total': 2, 'last_page': 1},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(_wrap(const SupplierListScreen()));
    await tester.pumpAndSettle();

    expect(find.text('PT Maju Jaya'), findsOneWidget);
    expect(find.text('Toko Berkah'), findsOneWidget);
    expect(find.textContaining('2 supplier'), findsOneWidget);
  });

  testWidgets('404 → error state jujur + retry memanggil server lagi', (
    tester,
  ) async {
    var calls = 0;
    ApiService.client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path.endsWith('/suppliers')) {
        calls++;
        return http.Response(
          jsonEncode({'message': 'Data supplier tidak ditemukan di server.'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(_wrap(const SupplierListScreen()));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Gagal memuat data'), findsOneWidget);
    expect(
      find.text('Data supplier tidak ditemukan di server.'),
      findsOneWidget,
    );
    expect(find.text('Coba Lagi'), findsOneWidget);

    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();

    expect(calls, 2);
  });

  testWidgets('tambah supplier sukses me-refresh daftar', (tester) async {
    final rows = _rows(['PT Maju Jaya']);
    ApiService.client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path.endsWith('/suppliers')) {
        return http.Response(
          jsonEncode({
            'data': rows,
            'meta': {'total': rows.length, 'last_page': 1},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'POST' &&
          request.url.path.endsWith('/suppliers')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final created = {'id': rows.length + 1, ...body};
        rows.add(created);
        return http.Response(
          jsonEncode({'data': created}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(_wrap(const SupplierListScreen()));
    await tester.pumpAndSettle();
    expect(find.text('PT Maju Jaya'), findsOneWidget);
    expect(find.text('PT Baru'), findsNothing);

    await tester.tap(find.byTooltip('Tambah supplier'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('supplier_name_field')),
      'PT Baru',
    );
    await tester.enterText(
      find.byKey(const ValueKey('supplier_phone_field')),
      '0812999000',
    );
    await tester.tap(find.byKey(const ValueKey('supplier_save_button')));
    await tester.pumpAndSettle();

    expect(find.text('PT Baru'), findsOneWidget);
    expect(find.text('PT Maju Jaya'), findsOneWidget);
  });
}
