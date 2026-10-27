import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/screens/inventory/opname_detail_screen.dart';
import 'package:pos_retail/screens/inventory/opname_list_screen.dart';
import 'package:pos_retail/services/api_service.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => LangProvider())],
    child: MaterialApp(home: child),
  );
}

Map<String, dynamic> _opnameJson({String status = 'counted'}) => {
  'id': 1,
  'outlet_id': 1,
  'status': status,
  'note': 'Opname mingguan',
  'created_at': '2026-10-20T10:00:00Z',
  'items': [
    {
      'product_id': 3,
      'product_name': 'Gula 1kg',
      'system_qty': 10,
      'physical_qty': 8,
      'diff': -2,
    },
    {
      'product_id': 4,
      'product_name': 'Kopi 200g',
      'system_qty': 5,
      'physical_qty': 7,
      'diff': 2,
    },
  ],
};

MockClient _listClient({int listStatus = 200}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/stock-opnames')) {
      if (listStatus != 200) {
        return http.Response(
          jsonEncode({'message': 'Data tidak ditemukan.'}),
          listStatus,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'data': [_opnameJson()],
          'meta': {'total': 1, 'last_page': 1},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 404);
  });
}

MockClient _detailClient() {
  var approved = false;
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('/approve')) {
      approved = true;
      return http.Response(
        jsonEncode({'data': _opnameJson(status: 'approved')}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'GET' && path.endsWith('/stock-opnames/1')) {
      return http.Response(
        jsonEncode({
          'data': _opnameJson(status: approved ? 'approved' : 'counted'),
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

  testWidgets('daftar opname tampil dari server', (tester) async {
    ApiService.client = _listClient();

    await tester.pumpWidget(_wrap(const OpnameListScreen(outletId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('Opname #1'), findsOneWidget);
    expect(find.text('Dihitung'), findsWidgets);
  });

  testWidgets('opname 404 → error jujur + tombol retry', (tester) async {
    ApiService.client = _listClient(listStatus: 404);

    await tester.pumpWidget(_wrap(const OpnameListScreen(outletId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('Data tidak ditemukan.'), findsOneWidget);
    expect(find.text('Coba Lagi'), findsOneWidget);
  });

  testWidgets('approve sukses → snackbar + status berubah', (tester) async {
    ApiService.client = _detailClient();

    await tester.pumpWidget(_wrap(const OpnameDetailScreen(opnameId: 1)));
    await tester.pumpAndSettle();

    expect(find.text('Opname #1'), findsWidgets);
    expect(find.text('Setujui & Koreksi Stok'), findsOneWidget);

    await tester.tap(find.text('Setujui & Koreksi Stok'));
    await tester.pumpAndSettle();

    expect(find.text('Setujui hasil opname?'), findsOneWidget);
    await tester.tap(find.text('Setujui'));
    await tester.pumpAndSettle();

    expect(
      find.text('Opname disetujui. Stok dikoreksi.'),
      findsOneWidget,
    );
    expect(find.text('Disetujui'), findsWidgets);
  });
}
