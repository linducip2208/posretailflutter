import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:pos_retail/l10n/lang_provider.dart';
import 'package:pos_retail/models/outlet.dart';
import 'package:pos_retail/providers/auth_provider.dart';
import 'package:pos_retail/screens/system/attendance_screen.dart';
import 'package:pos_retail/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LangProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
    ],
    child: MaterialApp(home: child),
  );
}

MockClient _okClient() {
  return MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/attendances')) {
      return http.Response(
        jsonEncode({
          'data': [
            {
              'id': 1,
              'user_name': 'Budi Kasir',
              'date': '2026-10-27',
              'clock_in': '2026-10-27T08:05:00Z',
              'status': 'hadir',
            },
            {
              'id': 2,
              'user_name': 'Siti Gudang',
              'date': '2026-10-27',
              'clock_in': '2026-10-27T09:30:00Z',
              'status': 'terlambat',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/attendances/clock-in')) {
      return http.Response(
        jsonEncode({
          'data': {'id': 3, 'status': 'hadir'},
          'message': 'Clock-in tercatat',
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

  testWidgets('daftar kehadiran tampil + badge status', (tester) async {
    ApiService.client = _okClient();

    await tester.pumpWidget(_wrap(const AttendanceScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Budi Kasir'), findsOneWidget);
    expect(find.text('Siti Gudang'), findsOneWidget);
    expect(find.text('Hadir'), findsOneWidget);
    expect(find.text('Terlambat'), findsOneWidget);
  });

  testWidgets('clock-in sukses → snackbar sukses', (tester) async {
    SharedPreferences.setMockInitialValues({});
    ApiService.client = _okClient();
    final auth = AuthProvider();
    await auth.selectOutlet(Outlet(id: 1, name: 'Toko A'));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LangProvider()),
          ChangeNotifierProvider.value(value: auth),
        ],
        child: const MaterialApp(home: AttendanceScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock_in_button')));
    await tester.pumpAndSettle();

    expect(find.text('Clock-in berhasil dicatat.'), findsOneWidget);
  });

  testWidgets('404 jujur + retry', (tester) async {
    var calls = 0;
    ApiService.client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return http.Response(
          jsonEncode({'message': 'Belum ada endpoint.'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'data': [
            {'id': 1, 'user_name': 'Budi Kasir', 'status': 'izin'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(_wrap(const AttendanceScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Coba Lagi'), findsOneWidget);
    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Budi Kasir'), findsOneWidget);
    expect(find.text('Izin'), findsOneWidget);
  });
}
