import 'package:flutter_test/flutter_test.dart';
import 'package:pos_retail/utils/formatters.dart';

void main() {
  group('Fmt uang', () {
    test('rupiah memakai simbol Rp dan pemisah ribuan id_ID', () {
      final text = Fmt.rupiah(12500);
      expect(text.startsWith('Rp'), isTrue, reason: text);
      expect(text.replaceAll(RegExp(r'[^0-9]'), ''), '12500');
    });

    test('thousand untuk input nominal', () {
      expect(Fmt.thousand(50000), '50.000');
      expect(Fmt.thousand(0), '0');
    });

    test('parseMoneyDigits menerima format Indonesia', () {
      expect(Fmt.parseMoneyDigits('Rp 50.000'), 50000);
      expect(Fmt.parseMoneyDigits('50,000'), 50000);
      expect(Fmt.parseMoneyDigits('12a3'), 123);
      expect(Fmt.parseMoneyDigits(''), 0);
      expect(Fmt.parseMoneyDigits('Rp'), 0);
    });

    test('compactCount hanya memadatkan >= 1000', () {
      expect(Fmt.compactCount(999), '999');
      expect(Fmt.compactCount(1200), '1.200');
    });
  });

  group('Fmt tanggal', () {
    test('dateForApi memakai format yyyy-MM-dd', () {
      expect(Fmt.dateForApi(DateTime(2026, 10, 19)), '2026-10-19');
    });

    test('dateTime menampilkan waktu lokal, aman tanpa locale id_ID', () {
      final text = Fmt.dateTime('2026-10-19T07:30:00Z');
      expect(
        RegExp(r'\d{2} \w{3} \d{4}, \d{2}:\d{2}').hasMatch(text),
        isTrue,
        reason: text,
      );
    });

    test('dateTime data rusak/kosong → "-"', () {
      expect(Fmt.dateTime(null), '-');
      expect(Fmt.dateTime(''), '-');
      expect(Fmt.dateTime('bukan-tanggal'), '-');
    });
  });

  group('Fmt.productImageUrl', () {
    test('path relatif disk public → /storage/', () {
      expect(
        Fmt.productImageUrl('products/kaos.jpg'),
        'https://posretail.whitelabel.co.id/storage/products/kaos.jpg',
      );
    });

    test('path berawalan / dipertahankan', () {
      expect(
        Fmt.productImageUrl('/storage/x.png'),
        'https://posretail.whitelabel.co.id/storage/x.png',
      );
      expect(
        Fmt.productImageUrl('storage/x.png'),
        'https://posretail.whitelabel.co.id/storage/x.png',
      );
    });

    test('URL absolut diteruskan apa adanya', () {
      const url = 'https://cdn.example.com/a.png';
      expect(Fmt.productImageUrl(url), url);
    });

    test('null/kosong → null (UI pakai placeholder)', () {
      expect(Fmt.productImageUrl(null), isNull);
      expect(Fmt.productImageUrl('  '), isNull);
    });
  });
}
