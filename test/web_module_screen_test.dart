import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/screens/more/web_module_screen.dart';
import 'package:pos_retail/services/api_service.dart';

Widget _wrap(WebModuleScreen screen) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => LangProvider())],
    child: MaterialApp(home: screen),
  );
}

const _testScreen = WebModuleScreen(
  title: 'Supplier',
  description: 'Daftar pemasok',
  webPath: '/admin/suppliers',
  apiEndpoints: ['/suppliers'],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ApiService.client = http.Client();
  });

  testWidgets('404 semua endpoint → status belum tersedia + arahan web admin', (
    tester,
  ) async {
    ApiService.client = MockClient(
      (_) async => http.Response('{}', 404),
    );

    await tester.pumpWidget(_wrap(_testScreen));
    await tester.pumpAndSettle();

    expect(find.textContaining('Belum tersedia'), findsOneWidget);
    expect(find.textContaining('posretail.whitelabel.co.id'), findsOneWidget);
    expect(find.text('Endpoint yang dicoba: /suppliers'), findsOneWidget);
  });

  testWidgets('403 → status tidak ada akses', (tester) async {
    ApiService.client = MockClient(
      (_) async => http.Response(
        jsonEncode({'message': 'Forbidden'}),
        403,
        headers: {'content-type': 'application/json'},
      ),
    );

    await tester.pumpWidget(_wrap(_testScreen));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tidak ada akses'), findsOneWidget);
  });

  testWidgets('200 → pratinjau data nyata + badge terhubung', (tester) async {
    ApiService.client = MockClient((request) async {
      if (request.url.path.endsWith('/suppliers')) {
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 1, 'name': 'PT Maju', 'status': 'aktif'},
              {'id': 2, 'name': 'CV Berkah', 'status': 'aktif'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(_wrap(_testScreen));
    await tester.pumpAndSettle();

    expect(find.textContaining('Terhubung'), findsOneWidget);
    expect(find.text('PT Maju'), findsOneWidget);
    expect(find.text('CV Berkah'), findsOneWidget);
  });

  testWidgets('fallback ke endpoint kedua bila pertama 404', (tester) async {
    ApiService.client = MockClient((request) async {
      if (request.url.path.endsWith('/suppliers')) {
        return http.Response('{}', 404);
      }
      return http.Response(
        jsonEncode({
          'data': [
            {'id': 9, 'name': 'PO-001'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(
      _wrap(
        const WebModuleScreen(
          title: 'Purchase Order',
          description: 'PO',
          webPath: '/admin/purchase-orders',
          apiEndpoints: ['/suppliers', '/purchase-orders'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Terhubung'), findsOneWidget);
    expect(find.text('PO-001'), findsOneWidget);
  });
}
