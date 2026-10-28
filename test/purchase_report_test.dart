import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/providers/auth_provider.dart';
import 'package:pos_retail/screens/reports/purchase_report_screen.dart';
import 'package:pos_retail/services/api_service.dart';
import 'package:pos_retail/utils/formatters.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LangProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
    ],
    child: MaterialApp(home: child),
  );
}

/// Layar coba GET /reports/purchases dulu (server-side:
/// {data: {total_cost, po_count, outstanding_po, top_suppliers, trend}}).
/// Bila 404 (belum deploy) → fallback agregasi client-side dari
/// GET /purchase-orders (envelope) lalu disaring rentang tanggal.
/// Tanggal dibuat dinamis (hari ini) agar lolos filter periode.
MockClient _okClient() {
  final now = DateTime.now().toIso8601String();
  return MockClient((request) async {
    if (request.url.path.endsWith('/purchase-orders')) {
      return http.Response(
        jsonEncode({
          'data': [
            {
              'id': 1,
              'po_number': 'PO-001',
              'supplier': {'id': 1, 'name': 'PT Maju'},
              'total_amount': '900000.00',
              'status': 'received',
              'created_at': now,
            },
            {
              'id': 2,
              'po_number': 'PO-002',
              'supplier': {'id': 2, 'name': 'CV Berkah'},
              'total_amount': '600000.00',
              'status': 'ordered',
              'created_at': now,
            },
          ],
          'meta': {'current_page': 1, 'total': 2},
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

  testWidgets('server 200: pakai data server tanpa badge lokal', (tester) async {
    final today = Fmt.dateForApi(DateTime.now());
    ApiService.client = MockClient((request) async {
      if (request.url.path.endsWith('/reports/purchases')) {
        return http.Response(
          jsonEncode({
            'data': {
              'start_date': today,
              'end_date': today,
              'total_cost': 1500000,
              'po_count': 2,
              'outstanding_po': 1,
              'top_suppliers': [
                {'name': 'PT Maju', 'total': '900000.00'},
                {'name': 'CV Berkah', 'total': 600000},
              ],
              'trend': [
                {'date': today, 'total': '1500000.00'},
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(_wrap(const PurchaseReportScreen()));
    await tester.pumpAndSettle();

    expect(find.text('PT Maju'), findsOneWidget);
    expect(find.text('CV Berkah'), findsOneWidget);
    expect(find.text(today), findsWidgets);
    expect(
      find.text('Mode lokal (server belum tersedia).'),
      findsNothing,
    );
  });

  testWidgets('server 404: fallback lokal + badge jujur', (tester) async {
    ApiService.client = MockClient((request) async {
      if (request.url.path.endsWith('/reports/purchases')) {
        return http.Response(
          jsonEncode({'message': 'Belum ada endpoint.'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('/purchase-orders')) {
        final now = DateTime.now().toIso8601String();
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 1,
                'po_number': 'PO-001',
                'supplier': {'id': 1, 'name': 'PT Maju'},
                'total_amount': '900000.00',
                'status': 'received',
                'created_at': now,
              },
            ],
            'meta': {'current_page': 1, 'total': 1},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(_wrap(const PurchaseReportScreen()));
    await tester.pumpAndSettle();

    expect(find.text('PT Maju'), findsOneWidget);
    expect(
      find.text('Mode lokal (server belum tersedia).'),
      findsOneWidget,
    );
  });

  testWidgets('kartu total + supplier teratas + tren tampil', (tester) async {
    ApiService.client = _okClient();

    await tester.pumpWidget(_wrap(const PurchaseReportScreen()));
    await tester.pumpAndSettle();

    expect(find.text('PT Maju'), findsOneWidget);
    expect(find.text('CV Berkah'), findsOneWidget);
    expect(find.text(Fmt.dateForApi(DateTime.now())), findsWidgets);
    // Catatan jujur export via web selalu tampil (ListView malas → drag dulu).
    final verticalList = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.vertical,
    );
    await tester.drag(verticalList, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.textContaining('PDF/Excel'), findsWidgets);
  });

  testWidgets('404 jujur + tombol Coba Lagi me-retry', (tester) async {
    var reportsCalls = 0;
    ApiService.client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/reports/purchases')) {
        reportsCalls++;
        if (reportsCalls == 1) {
          return http.Response(
            jsonEncode({'message': 'Belum ada endpoint.'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }
        final today = Fmt.dateForApi(DateTime.now());
        return http.Response(
          jsonEncode({
            'data': {
              'start_date': today,
              'end_date': today,
              'total_cost': 0,
              'po_count': 0,
              'outstanding_po': 0,
              'top_suppliers': [],
              'trend': [],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // Fallback lokal ikut 404 → layar error jujur + tombol retry.
      return http.Response(
        jsonEncode({'message': 'Belum ada endpoint.'}),
        404,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(_wrap(const PurchaseReportScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Coba Lagi'), findsOneWidget);
    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();

    expect(reportsCalls, 2);
    expect(find.text('Coba Lagi'), findsNothing);
  });
}
