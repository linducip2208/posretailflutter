import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/services/api_service.dart';
import 'package:pos_retail/utils/formatters.dart';
import 'package:pos_retail/widgets/payment_dialog.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => LangProvider())],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

MockClient _methodsClient({int status = 200}) {
  return MockClient((request) async {
    if (request.url.path.endsWith('/payment-methods')) {
      if (status != 200) {
        return http.Response(
          jsonEncode({'message': 'Server bermasalah'}),
          status,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'data': [
            {'id': 1, 'name': 'Tunai', 'code': 'cash'},
            {'id': 2, 'name': 'QRIS', 'code': 'qris'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 404);
  });
}

FilledButton _submitButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ApiService.client = http.Client();
  });

  testWidgets('metode pembayaran dimuat dari server dan tombol terkunci '
      'sebelum nominal diisi', (tester) async {
    ApiService.client = _methodsClient();

    await tester.pumpWidget(_wrap(const PaymentDialog(total: 50000)));
    await tester.pumpAndSettle();

    expect(find.text('Tunai'), findsOneWidget);
    expect(find.text('QRIS'), findsOneWidget);
    expect(_submitButton(tester).onPressed, isNull);
    expect(find.text('Kurang'), findsOneWidget);
  });

  testWidgets('uang pas mengisi nominal penuh lalu Bayar mengembalikan '
      'daftar pembayaran', (tester) async {
    ApiService.client = _methodsClient();
    List<PaymentEntry>? result;

    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => LangProvider())],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await PaymentDialog.show(context, total: 50000);
                },
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Uang Pas'));
    await tester.pump();

    final buttonText = find.textContaining(Fmt.rupiah(50000));
    expect(buttonText, findsWidgets);
    expect(_submitButton(tester).onPressed, isNotNull);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.length, 1);
    expect(result!.single.method.id, 1);
    expect(result!.single.amount, 50000);
  });

  testWidgets('tap ganda cepat tidak menggandakan submit (anti double-tap)', (
    tester,
  ) async {
    ApiService.client = _methodsClient();
    List<PaymentEntry>? result;

    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => LangProvider())],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await PaymentDialog.show(context, total: 10000);
                },
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Uang Pas'));
    await tester.pump();

    // Dua tap dalam frame yang sama: guard _submitting menahan submit kedua.
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.length, 1);
  });

  testWidgets('kasbon: allowPartial mengizinkan DP < total dan menampilkan '
      'sisa tagihan', (tester) async {
    ApiService.client = _methodsClient();

    await tester.pumpWidget(
      _wrap(const PaymentDialog(total: 50000, allowPartial: true)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '20000');
    await tester.pump();

    expect(find.textContaining(Fmt.rupiah(20000)), findsWidgets);
    expect(find.textContaining('Sisa tagihan'), findsOneWidget);
    expect(_submitButton(tester).onPressed, isNotNull);
  });

  testWidgets('kembalian dihitung realtime saat nominal lebih dari total', (
    tester,
  ) async {
    ApiService.client = _methodsClient();

    await tester.pumpWidget(_wrap(const PaymentDialog(total: 50000)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '75000');
    await tester.pump();

    expect(find.text('Kembalian'), findsOneWidget);
    expect(find.text(Fmt.rupiah(25000)), findsWidgets);
  });

  testWidgets('gagal memuat metode → error + tombol Bayar terkunci', (
    tester,
  ) async {
    ApiService.client = _methodsClient(status: 500);

    await tester.pumpWidget(_wrap(const PaymentDialog(total: 50000)));
    await tester.pumpAndSettle();

    expect(find.text('Coba Lagi'), findsOneWidget);
    expect(_submitButton(tester).onPressed, isNull);
  });
}
