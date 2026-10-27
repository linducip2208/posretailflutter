import 'package:flutter_test/flutter_test.dart';

import 'package:pos_retail/utils/menu_access.dart';

void main() {
  group('menuVisibleForRole', () {
    test('tanpa batasan → selalu tampil', () {
      expect(menuVisibleForRole('kasir', null), isTrue);
      expect(menuVisibleForRole(null, null), isTrue);
    });

    test('peran tak dikenal / kosong → fail-open (tampil semua)', () {
      expect(menuVisibleForRole(null, const ['owner']), isTrue);
      expect(menuVisibleForRole('', const ['owner']), isTrue);
      expect(menuVisibleForRole('superuser', const ['owner']), isTrue);
    });

    test('pencocokan case-insensitive', () {
      expect(menuVisibleForRole('Kasir', const ['kasir']), isTrue);
      expect(menuVisibleForRole(' KASIR ', const ['kasir']), isTrue);
    });

    test('kasir tidak melihat menu gudang, gudang tidak melihat menu kasir', () {
      expect(menuVisibleForRole('kasir', stockRoles), isFalse);
      expect(menuVisibleForRole('gudang', stockRoles), isTrue);
      expect(menuVisibleForRole('gudang', salesRoles), isFalse);
      expect(menuVisibleForRole('kasir', salesRoles), isTrue);
    });

    test('laporan hanya manajerial, pengguna hanya owner/admin', () {
      expect(menuVisibleForRole('kasir', reportRoles), isFalse);
      expect(menuVisibleForRole('manager', reportRoles), isTrue);
      expect(menuVisibleForRole('manager', userAdminRoles), isFalse);
      expect(menuVisibleForRole('admin', userAdminRoles), isTrue);
      expect(menuVisibleForRole('owner', userAdminRoles), isTrue);
    });
  });
}
