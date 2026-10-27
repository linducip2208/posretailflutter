import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

Map<String, dynamic> _materialJson({int id = 1, double stock = 2}) => {
  'id': id,
  'name': 'Gula Pasir',
  'unit': 'kg',
  'stock': stock,
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
      created = true;
      return http.Response(
        jsonEncode({'data': _materialJson(id: 2, stock: 10)}),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    final nameField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(nameField.first, 'Tepung Terigu');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(find.text('Bahan baku tersimpan di server.'), findsOneWidget);
  });
}
