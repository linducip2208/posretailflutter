import 'package:intl/intl.dart';

import '../config/api_config.dart';

/// Formatter terpusat — jangan bikin NumberFormat baru di tiap screen.
abstract final class Fmt {
  static final NumberFormat _rupiah = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  );

  static final NumberFormat _thousand = NumberFormat.decimalPattern('id_ID');

  /// Rp12.500 (tanpa desimal — Rupiah tidak pakai sen di praktik kasir).
  static String rupiah(num amount) => _rupiah.format(amount);

  /// 12.500 (untuk input nominal).
  static String thousand(num amount) => _thousand.format(amount);

  /// 19 Okt 2026, 14:30 — waktu lokal perangkat (WIB di perangkat kasir).
  static String dateTime(String? raw) {
    final dt = parseIsoToLocal(raw);
    if (dt == null) return '-';
    return _formatSafe('dd MMM yyyy, HH:mm', dt);
  }

  static String date(String? raw) {
    final dt = parseIsoToLocal(raw);
    if (dt == null) return '-';
    return _formatSafe('dd MMM yyyy', dt);
  }

  static String time(DateTime dt) => DateFormat('HH:mm').format(dt);

  /// Format tanggal lokal, fallback ke locale default bila data locale
  /// `id_ID` belum diinisialisasi (mis. di unit test tanpa main()).
  static String _formatSafe(String pattern, DateTime dt) {
    try {
      return DateFormat(pattern, 'id_ID').format(dt);
    } catch (_) {
      return DateFormat(pattern).format(dt);
    }
  }

  static String dateForApi(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  /// Server mengirim ISO-8601 (bisa UTC). Tampilkan dalam waktu lokal.
  static DateTime? parseIsoToLocal(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    return parsed?.toLocal();
  }

  /// "50.000" / "50,000" / "Rp50.000" → 50000. Rupiah selalu bilangan bulat.
  static int parseMoneyDigits(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0;
    return int.tryParse(digits) ?? 0;
  }

  static String compactCount(int value) =>
      value >= 1000 ? _thousand.format(value) : '$value';

  /// URL gambar produk.
  ///
  /// Backend menyimpan `image` sebagai path relatif (mis. `products/x.jpg`)
  /// pada disk `public` → URL sebenarnya `<host>/storage/<path>`.
  /// Mendukung juga URL absolut dan path berawalan `/`.
  static String? productImageUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final image = raw.trim();
    if (image.startsWith('http://') || image.startsWith('https://')) {
      return image;
    }
    final host = _assetHost();
    if (host == null) return null;
    if (image.startsWith('/storage/')) return '$host$image';
    if (image.startsWith('storage/')) return '$host/$image';
    if (image.startsWith('/')) return '$host$image';
    return '$host/storage/$image';
  }

  /// Origin server (tanpa `/api/v1`) untuk mengambil file statis.
  static String? _assetHost() {
    final uri = Uri.tryParse(ApiConfig.baseUrl);
    if (uri == null || uri.host.isEmpty) return null;
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  }
}
