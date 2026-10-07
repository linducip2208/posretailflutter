import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/providers/auth_provider.dart';
import 'package:pos_retail/screens/auth/login_screen.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LangProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  group('Login screen', () {
    testWidgets('menampilkan form email, password, tombol masuk',
        (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));
      await tester.pump();
      expect(find.text('Masuk'), findsWidgets);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('toggle password visibility bekerja', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));
      await tester.pump();
      // Awal: obscure (visibility_off). Tap ikon untuk tampilkan.
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();
      expect(find.byIcon(Icons.visibility), findsOneWidget);
    });
  });
}
