import '../utils/safe_parse.dart';

/// Pengguna & peran (grup 12) + absensi (grup 13) kontrak
/// docs/API_CONTRACT_MOBILE_PARITY.md. Parsing toleran: field hilang
/// atau bertipe string/angka dinormalisasi tanpa throw.

class AppUser {
  final int id;
  final String name;
  final String? email;
  final String role;
  final bool active;
  final List<int> outletIds;

  AppUser({
    required this.id,
    required this.name,
    this.email,
    required this.role,
    this.active = true,
    this.outletIds = const [],
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final rawOutlets = json['outlet_ids'] ?? json['outlets'];
    final List<int> outletIds = [];
    if (rawOutlets is List) {
      for (final e in rawOutlets) {
        if (e is Map && e['id'] != null) {
          outletIds.add(safeInt(e['id']));
        } else {
          final v = safeInt(e, -1);
          if (v >= 0) outletIds.add(v);
        }
      }
    }
    final activeRaw = json['active'] ?? json['is_active'];
    return AppUser(
      id: safeInt(json['id']),
      name: safeString(json['name']),
      email: json['email']?.toString(),
      role: safeString(json['role'], 'kasir').toLowerCase(),
      active: activeRaw == null
          ? true
          : activeRaw is bool
          ? activeRaw
          : safeInt(activeRaw, 1) == 1,
      outletIds: outletIds,
    );
  }

  /// Label Indonesia untuk peran.
  static String roleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
        return 'Pemilik';
      case 'admin':
        return 'Admin';
      case 'manager':
        return 'Manajer';
      case 'gudang':
        return 'Gudang';
      case 'kasir':
      default:
        return 'Kasir';
    }
  }
}

class RoleInfo {
  final String name;
  final List<String> permissions;

  RoleInfo({required this.name, this.permissions = const []});

  factory RoleInfo.fromJson(dynamic json) {
    if (json is String) return RoleInfo(name: json.toLowerCase());
    if (json is Map<String, dynamic>) {
      final rawPerms = json['permissions'];
      // Backend nyata: {id, name, slug, description} — slug adalah
      // kunci stabil (owner/admin/manager/kasir/gudang).
      final key =
          json['slug']?.toString() ?? json['name']?.toString() ?? 'kasir';
      return RoleInfo(
        name: key.toLowerCase(),
        permissions: rawPerms is List
            ? rawPerms.map((e) => e.toString()).toList()
            : const [],
      );
    }
    return RoleInfo(name: 'kasir');
  }
}

/// Matriks akses sederhana untuk ditampilkan di detail user
/// (sesuai halaman demo web di kontrak grup 12).
const Map<String, List<String>> roleAccessMatrix = {
  'kasir': ['Kasir (POS) saja'],
  'gudang': ['Stok', 'Purchase Order', 'Transfer stok'],
  'manager': ['Data master', 'Laporan', 'Approval (PO/retur/opname)'],
  'admin': ['Semua menu kecuali Pengaturan sistem'],
  'owner': ['Akses penuh termasuk Pengaturan sistem'],
};

/// Daftar peran yang dikenal, untuk dropdown bila GET /roles gagal.
const List<String> knownRoles = ['owner', 'admin', 'manager', 'kasir', 'gudang'];

class Attendance {
  final int id;
  final int? userId;
  final String? userName;
  final int? outletId;
  final String? date;
  final String? clockIn;
  final String? clockOut;
  final String status;

  Attendance({
    required this.id,
    this.userId,
    this.userName,
    this.outletId,
    this.date,
    this.clockIn,
    this.clockOut,
    required this.status,
  });

  factory Attendance.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    return Attendance(
      id: safeInt(json['id']),
      userId: json['user_id'] == null
          ? (user is Map ? safeInt(user['id'], -1) : null)
          : safeInt(json['user_id']),
      userName: json['user_name']?.toString() ??
          (user is Map
              ? (user['name']?.toString())
              : json['name']?.toString()),
      outletId: json['outlet_id'] == null
          ? null
          : safeInt(json['outlet_id']),
      date: json['date']?.toString(),
      clockIn: json['clock_in']?.toString() ?? json['clocked_in_at']?.toString(),
      clockOut:
          json['clock_out']?.toString() ?? json['clocked_out_at']?.toString(),
      status: safeString(json['status'], 'hadir').toLowerCase(),
    );
  }

  static String statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'present':
      case 'hadir':
        return 'Hadir';
      case 'late':
      case 'terlambat':
        return 'Terlambat';
      case 'izin':
        return 'Izin';
      case 'sakit':
        return 'Sakit';
      default:
        return 'Hadir';
    }
  }
}
