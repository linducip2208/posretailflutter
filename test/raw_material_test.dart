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
import 'package:pos_retail/screens/inventory/raw_material_screen.dart';
import 'package:pos_retail/services/api_service.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => LangProvider())],
    child: MaterialApp(home: child),
  );
}

/// Fixture sesuai kontrak backend live: `current_stock`, relasi `unit`,
/// `code`, `outlet_id`.
Map<String, dynamic> _materialJson({int id = 1, double stock = 2}) => {
  'id': id,
  'name': 'Gula Pasir',
  'code': 'RM-001',
  'outlet_id': 1,
  'unit_id': 1,
  'unit': {'name': 'kg'},
  'current_stock': stock,
  'min_stock': 5,
  'cost_per_unit': '15000',
};

MockClient _screenClient({int listStatus = 200}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/raw-materials')) {
      if (listStatus != 200) {
        return http.Response(
          jsonEncode({'message': 'Data tidak ditemukan.'}),
          listStatus,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'data': [_materialJson()],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'GET' && path.endsWith('/products')) {
      return http.Response(
        jsonEncode({'data': []}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 404);
  });
}

MockClient _createClient() {
  var created = false;
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('/raw-materials')) {
      // Kontrak backend: name + outlet_id wajib.
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      assert(
        body['name'] != null && body['outlet_id'] != null,
        'POST /raw-materials wajib membawa name + outlet_id',
      );
      created = true;
      return http.Response(
        jsonEncode({'data': _materialJson(id: 2, stock: 10)}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'GET' &&
        (path.endsWith('/outlets') || path.endsWith('/units'))) {
      return http.Response(
        jsonEncode({
          'data': [
            {'id': 1, 'name': 'Outlet Pusat'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'GET' && path.endsWith('/raw-materials')) {
      return http.Response(
        jsonEncode({
          'data': [
            _materialJson(),
            if (created) _materialJson(id: 2, stock: 10),
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'GET' && path.endsWith('/products')) {
      return http.Response(
        jsonEncode({'data': []}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 404);
  });
}

MockClient _editClient() {
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'PUT' && path.endsWith('/raw-materials/1')) {
      // Kontrak backend baru: PUT {name?, outlet_id?, unit_id?,
      // cost_per_unit?, current_stock?, min_stock?, active?}.
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      assert(
        body['name'] != null && body['outlet_id'] != null,
        'PUT /raw-materials/{id} wajib membawa name + outlet_id',
      );
      return http.Response(
        jsonEncode({'data': _materialJson(id: 1, stock: 8)}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'GET' &&
        (path.endsWith('/outlets') || path.endsWith('/units'))) {
      return http.Response(
        jsonEncode({
          'data': [
            {'id': 1, 'name': 'Outlet Pusat'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'GET' && path.endsWith('/raw-materials')) {
      return http.Response(
        jsonEncode({
          'data': [_materialJson()],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'GET' && path.endsWith('/products')) {
      return http.Response(
        jsonEncode({'data': []}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 404);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Widget test tidak punya implementasi platform asli: pakai fake
  // secure storage resmi + mock SharedPreferences agar helper PUT
  // (_sendPut → SecureTokenStorage.readToken) selesai tanpa token,
  // sama seperti request tanpa header Authorization.
  setUpAll(() {
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform({});
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    ApiService.client = http.Client();
  });

  testWidgets('daftar bahan tampil + badge menipis', (tester) async {
    ApiService.client = _screenClient();

    await tester.pumpWidget(_wrap(const RawMaterialScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Gula Pasir'), findsOneWidget);
    expect(find.text('Menipis'), findsOneWidget);
  });

  testWidgets('bahan 404 → error jujur + tombol retry', (tester) async {
    ApiService.client = _screenClient(listStatus: 404);

    await tester.pumpWidget(_wrap(const RawMaterialScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Data tidak ditemukan.'), findsOneWidget);
    expect(find.text('Coba Lagi'), findsOneWidget);
  });

  testWidgets('tambah bahan sukses → snackbar + daftar bertambah', (
    tester,
  ) async {
    ApiService.client = _createClient();

    await tester.pumpWidget(_wrap(const RawMaterialScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tambah Bahan'));
    await tester.pumpAndSettle();

    expect(find.text('Tambah Bahan Baku'), findsOneWidget);
    // Pilih outlet (wajib di kontrak backend).
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Outlet Pusat').last);
    await tester.pumpAndSettle();
    final nameField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(nameField.first, 'Tepung Terigu');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(find.text('Bahan baku tersimpan di server.'), findsOneWidget);
  });

  testWidgets('ubah bahan sukses via PUT → snackbar', (tester) async {
    ApiService.client = _editClient();

    await tester.pumpWidget(_wrap(const RawMaterialScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Gula Pasir'), findsOneWidget);
    await tester.tap(find.byTooltip('Ubah'));
    await tester.pumpAndSettle();

    expect(find.text('Ubah Bahan Baku'), findsOneWidget);
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(find.text('Bahan baku tersimpan di server.'), findsOneWidget);
  });
}
