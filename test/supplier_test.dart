import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/models/supplier.dart';
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
      'contact_person': 'Budi ${i + 1}',
      'phone': '0812000${i + 1}',
      'email': null,
      'address': null,
    },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Widget test tidak punya implementasi platform asli: pakai fake
  // secure storage resmi + mock SharedPreferences agar helper PUT/DELETE
  // (_sendWrite → SecureTokenStorage.readToken) selesai tanpa token,
  // sama seperti request tanpa header Authorization.
  setUpAll(() {
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform({});
    SharedPreferences.setMockInitialValues({});
  });

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

  testWidgets('ubah supplier sukses via PUT → snackbar', (tester) async {
    // Backend baru: PUT /suppliers/{id} {name, contact_person?, ...}.
    String? putMethod;
    Map<String, dynamic>? putBody;
    ApiService.client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path.endsWith('/suppliers')) {
        return http.Response(
          jsonEncode({
            'data': _rows(['PT Maju Jaya']),
            'meta': {'total': 1, 'last_page': 1},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'PUT' &&
          request.url.path.endsWith('/suppliers/1')) {
        putMethod = request.method;
        putBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'data': {'id': 1, ...putBody!},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(_wrap(const SupplierListScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Aksi supplier').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ubah'));
    await tester.pumpAndSettle();

    expect(find.text('Ubah Supplier'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('supplier_name_field')),
      'PT Maju Jaya Baru',
    );
    await tester.tap(find.byKey(const ValueKey('supplier_save_button')));
    await tester.pumpAndSettle();

    expect(putMethod, 'PUT');
    expect(putBody?['name'], 'PT Maju Jaya Baru');
    expect(find.text('Supplier berhasil diperbarui.'), findsOneWidget);
  });

  testWidgets('hapus supplier sukses via DELETE → snackbar', (tester) async {
    // Backend baru: DELETE /suppliers/{id} (409 bila masih punya PO).
    var deleted = false;
    ApiService.client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path.endsWith('/suppliers')) {
        return http.Response(
          jsonEncode({
            'data': _rows(['PT Maju Jaya']),
            'meta': {'total': 1, 'last_page': 1},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'DELETE' &&
          request.url.path.endsWith('/suppliers/1')) {
        deleted = true;
        return http.Response(
          jsonEncode({'message': 'Supplier berhasil dihapus.'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(_wrap(const SupplierListScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Aksi supplier').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus'));
    await tester.pumpAndSettle();

    expect(find.text('Hapus supplier?'), findsOneWidget);
    await tester.tap(find.text('Hapus').last);
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(find.text('Supplier berhasil dihapus.'), findsOneWidget);
  });

  test('model memakai kontrak backend (contact_person + po_count)', () {    final s = Supplier.fromJson({
      'id': 5,
      'name': 'PT Maju',
      'contact_person': 'Budi',
      'phone': '0812',
      'po_count': 3,
    });
    expect(s.contactPerson, 'Budi');
    expect(s.poCount, 3);

    final legacy = Supplier.fromJson({
      'id': 6,
      'name': 'PT Lama',
      'purchase_orders_count': 2,
    });
    expect(legacy.poCount, 2);
    expect(legacy.contactPerson, isNull);
  });
}
