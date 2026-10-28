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

/// Bentuk backend nyata:
/// GET /attendances/today → {data: {...} | null} dengan
/// status present|late, clock_in "HH:mm:ss".
MockClient _okClient() {
  return MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/attendances/today')) {
      return http.Response(
        jsonEncode({
          'data': {
            'id': 1,
            'user_id': 5,
            'outlet_id': 1,
            'date': '2026-10-27',
            'clock_in': '08:05:00',
            'clock_out': null,
            'status': 'late',
            'notes': null,
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/attendances/clock-in')) {
      return http.Response(
        jsonEncode({
          'data': {'id': 3, 'status': 'present'},
          'message': 'Clock-in tercatat',
        }),
        201,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/attendances/clock-out')) {
      return http.Response(
        jsonEncode({
          'data': {'id': 1, 'status': 'late'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/attendances/history')) {
      return http.Response(
        jsonEncode({
          'data': [
            {
              'id': 2,
              'user_id': 5,
              'outlet_id': 1,
              'date': '2026-10-26',
              'clock_in': '07:55:00',
              'clock_out': '17:02:00',
              'status': 'present',
              'user': {'id': 5, 'name': 'Kasir A'},
            },
            {
              'id': 1,
              'user_id': 5,
              'outlet_id': 1,
              'date': '2026-10-27',
              'clock_in': '08:05:00',
              'clock_out': null,
              'status': 'late',
              'user': {'id': 5, 'name': 'Kasir A'},
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

  testWidgets('absensi hari ini tampil + badge status', (tester) async {
    ApiService.client = _okClient();

    await tester.pumpWidget(_wrap(const AttendanceScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Terlambat'), findsNWidgets(2)); // kartu today + baris riwayat
    expect(find.text('08:05'), findsOneWidget);
  });

  testWidgets('riwayat server tampil di bawah kartu today', (tester) async {
    ApiService.client = _okClient();

    await tester.pumpWidget(_wrap(const AttendanceScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Riwayat Absensi'), findsOneWidget);
    expect(find.text('2026-10-26'), findsOneWidget);
    expect(find.textContaining('Kasir A'), findsWidgets);
    expect(
      find.text('Riwayat server belum tersedia, menampilkan hari ini saja.'),
      findsNothing,
    );
  });

  testWidgets('riwayat 404: today-only + pesan jujur', (tester) async {
    ApiService.client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/attendances/history')) {
        return http.Response(
          jsonEncode({'message': 'Belum ada endpoint.'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/attendances/today')) {
        return http.Response(
          jsonEncode({
            'data': {
              'id': 1,
              'user_id': 5,
              'outlet_id': 1,
              'date': '2026-10-27',
              'clock_in': '08:05:00',
              'clock_out': null,
              'status': 'late',
              'notes': null,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    await tester.pumpWidget(_wrap(const AttendanceScreen()));
    await tester.pumpAndSettle();

    expect(find.text('08:05'), findsOneWidget);
    expect(find.text('Riwayat Absensi'), findsNothing);
    expect(
      find.text('Riwayat server belum tersedia, menampilkan hari ini saja.'),
      findsOneWidget,
    );
    expect(
      find.text('Riwayat absensi lengkap tersedia di web admin.'),
      findsOneWidget,
    );
  });

  testWidgets('clock-in sukses → snackbar sukses', (tester) async {
    SharedPreferences.setMockInitialValues({});
    ApiService.client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/attendances/today')) {
        return http.Response(
          jsonEncode({'data': null}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/attendances/clock-in')) {
        return http.Response(
          jsonEncode({
            'data': {'id': 3, 'status': 'present'},
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });
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
    var todayCalls = 0;
    ApiService.client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/attendances/history')) {
        return http.Response(
          jsonEncode({'message': 'Belum ada endpoint.'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      }
      todayCalls++;
      if (todayCalls == 1) {
        return http.Response(
          jsonEncode({'message': 'Belum ada endpoint.'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'data': null}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await tester.pumpWidget(_wrap(const AttendanceScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Coba Lagi'), findsOneWidget);
    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();

    expect(todayCalls, 2);
    expect(find.text('Belum clock-in hari ini.'), findsOneWidget);
  });
}
