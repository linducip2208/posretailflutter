import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/screens/sales/installment_screen.dart';
import 'package:pos_retail/services/api_service.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => LangProvider())],
    child: MaterialApp(home: child),
  );
}

Map<String, dynamic> _insJson() => {
  'id': 1,
  'order_id': 9,
  'plan': 'monthly',
  'count': 3,
  'down_payment': '50000',
  'due_amount': '250000',
  'payment_status': 'partial',
};

MockClient _lookupClient({int lookupStatus = 200}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/installments')) {
      if (lookupStatus != 200) {
        return http.Response(
          jsonEncode({'message': 'Data tidak ditemukan.'}),
          lookupStatus,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'data': [_insJson()],
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

  testWidgets('lookup cicilan tampil dari server', (tester) async {
    ApiService.client = _lookupClient();

    await tester.pumpWidget(_wrap(const InstallmentScreen(initialOrderId: 9)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Bulanan'), findsOneWidget);
    expect(find.textContaining('Sebagian'), findsOneWidget);
  });

  testWidgets('cicilan 404 → error jujur + tombol retry', (tester) async {
    ApiService.client = _lookupClient(lookupStatus: 404);

    await tester.pumpWidget(_wrap(const InstallmentScreen(initialOrderId: 9)));
    await tester.pumpAndSettle();

    expect(find.text('Data tidak ditemukan.'), findsOneWidget);
    expect(find.text('Coba Lagi'), findsOneWidget);
  });
}
