import '../models/system_ops.dart';

/// Visibilitas menu "Lainnya" berdasarkan peran pengguna.
///
/// Server tetap sumber kebenaran otorisasi (layar menangani 403);
/// helper ini hanya menyembunyikan menu yang jelas di luar wewenang peran
/// agar UX jujur. Peran yang tidak dikenal / kosong → tampil semua
/// (fail-open) supaya tidak ada yang terkunci keluar karena perbedaan
/// penamaan role di server.
bool menuVisibleForRole(String? role, List<String>? allowed) {
  if (allowed == null) return true;
  final normalized = role?.trim().toLowerCase();
  if (normalized == null ||
      normalized.isEmpty ||
      !knownRoles.contains(normalized)) {
    return true;
  }
  return allowed.contains(normalized);
}

/// Peran yang boleh melihat menu operasional kasir/penjualan.
const List<String> salesRoles = ['owner', 'admin', 'manager', 'kasir'];

/// Peran yang boleh melihat menu pembelian/inventori (gudang).
const List<String> stockRoles = ['owner', 'admin', 'manager', 'gudang'];

/// Peran yang boleh melihat laporan (manajerial).
const List<String> reportRoles = ['owner', 'admin', 'manager'];

/// Peran yang boleh mengelola pengguna (tanpa manager: matrix akses
/// menempatkan user-management di admin/owner).
const List<String> userAdminRoles = ['owner', 'admin'];
