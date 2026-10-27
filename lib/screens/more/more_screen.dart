import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/lang_provider.dart';
import '../../l10n/s.dart';
import '../../providers/auth_provider.dart';
import '../../services/offline_sync_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/menu_access.dart';
import '../../widgets/common/confirmation_dialog.dart';
import '../../widgets/common/status_badge.dart';
import '../auth/login_screen.dart';
import '../customers/customer_list_screen.dart';
import '../inventory/opname_list_screen.dart';
import '../inventory/raw_material_screen.dart';
import '../inventory/stock_movement_screen.dart';
import '../inventory/transfer_list_screen.dart';
import '../loyalty/customer_group_screen.dart';
import '../loyalty/discount_list_screen.dart';
import '../loyalty/reward_list_screen.dart';
import '../outlet/outlet_selection_screen.dart';
import '../purchases/purchase_order_list_screen.dart';
import '../reports/inventory_report_screen.dart';
import '../reports/purchase_report_screen.dart';
import '../reports/report_screen.dart';
import '../sales/held_order_screen.dart';
import '../sales/installment_screen.dart';
import '../sales/return_list_screen.dart';
import '../settings/settings_screen.dart';
import '../suppliers/supplier_list_screen.dart';
import '../system/attendance_screen.dart';
import '../system/user_list_screen.dart';
import 'about_screen.dart';
import 'printer_screen.dart';
import 'profile_screen.dart';
import 'shift_screen.dart';
import 'stock_alert_screen.dart';
import 'sync_screen.dart';

/// Tab "Lainnya": pusat menu operasional, perangkat, akun, dan bantuan.
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final OfflineSyncService _offline = OfflineSyncService();

  int _pendingCount = 0;
  late final void Function(bool) _connectivityListener;

  @override
  void initState() {
    super.initState();
    _connectivityListener = (_) => _refreshPending();
    _offline.addListener(_connectivityListener);
    _refreshPending();
  }

  @override
  void dispose() {
    _offline.removeListener(_connectivityListener);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshPending() async {
    final count = await _offline.getPendingCount();
    if (!mounted || !context.mounted) return;
    setState(() => _pendingCount = count);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _refreshPending();
  }

  Future<void> _confirmLogout() async {
    final ok = await confirmDialog(
      context,
      title: S.tn(context, 'Keluar dari akun?'),
      message: S.tn(
        context,
        'Anda akan kembali ke layar masuk. Transaksi di antrean offline tetap tersimpan di perangkat.',
      ),
      confirmLabel: S.tn(context, 'Keluar'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _showLanguageSheet() async {
    final lang = context.read<LangProvider>();
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: RadioGroup<String>(
          groupValue: lang.code,
          onChanged: (v) {
            if (v == null) return;
            lang.setCode(v);
            Navigator.pop(sheetContext);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  S.t(sheetContext, 'Pilih Bahasa'),
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleMedium?.copyWith(fontSize: 16),
                ),
              ),
              const RadioListTile<String>(
                value: 'id',
                title: Text('Bahasa Indonesia'),
              ),
              const RadioListTile<String>(value: 'en', title: Text('English')),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final outlet = auth.currentOutlet;
    final query = _searchCtrl.text.trim().toLowerCase();

    final sections = _buildSections(context);
    final role = user?.role;
    for (final section in sections) {
      section.items.removeWhere(
        (item) => !menuVisibleForRole(role, item.roles),
      );
    }
    sections.removeWhere((s) => s.items.isEmpty);
    if (query.isNotEmpty) {
      for (final section in sections) {
        section.items.removeWhere(
          (item) => !item.label.toLowerCase().contains(query),
        );
      }
      sections.removeWhere((s) => s.items.isEmpty);
    }

    return Scaffold(
      appBar: AppBar(title: Text(S.t(context, 'Lainnya'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      (user?.name.isNotEmpty ?? false)
                          ? user!.name.substring(0, 1).toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? '-',
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          outlet?.name ?? S.t(context, 'Outlet belum dipilih'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (user?.role != null)
                    StatusBadge(user!.role!, tone: BadgeTone.info),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: S.t(context, 'Cari menu...'),
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final section in sections) ...[
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                bottom: AppSpacing.sm,
              ),
              child: Text(
                section.title,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < section.items.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 56),
                    _menuTile(context, section.items[i]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          OutlinedButton.icon(
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout, size: 18),
            label: Text(S.t(context, 'Keluar')),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              minimumSize: const Size.fromHeight(46),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _menuTile(BuildContext context, _MenuEntry entry) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: entry.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(entry.icon, size: 18, color: entry.color),
      ),
      title: Text(
        entry.label,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      subtitle: entry.subtitle == null
          ? null
          : Text(
              entry.subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.badge != null)
            StatusBadge('${entry.badge}', tone: BadgeTone.warning),
          const SizedBox(width: AppSpacing.xs),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
      onTap: entry.onTap,
    );
  }

  List<_MenuSection> _buildSections(BuildContext context) {
    return [
      _MenuSection(
        title: S.t(context, 'Operasional'),
        items: [
          _MenuEntry(
            icon: Icons.people_outline,
            color: AppColors.primary,
            label: S.t(context, 'Pelanggan'),
            subtitle: S.t(context, 'Daftar & pencarian pelanggan'),
            onTap: () => _open(const CustomerListScreen()),
          ),
          _MenuEntry(
            icon: Icons.warning_amber_rounded,
            color: AppColors.warning,
            label: S.t(context, 'Peringatan Stok'),
            subtitle: S.t(context, 'Stok menipis & rekomendasi restock'),
            onTap: () => _open(const StockAlertScreen()),
          ),
          _MenuEntry(
            icon: Icons.sync,
            color: AppColors.accent,
            label: S.t(context, 'Sinkronisasi'),
            subtitle: S.t(context, 'Antrean transaksi offline'),
            badge: _pendingCount > 0 ? _pendingCount : null,
            onTap: () => _open(const SyncScreen()),
          ),
          _MenuEntry(
            icon: Icons.point_of_sale_outlined,
            color: AppColors.success,
            label: S.t(context, 'Shift Kasir'),
            subtitle: S.t(context, 'Buka/tutup shift & hitung kas'),
            onTap: () => _open(const ShiftScreen()),
          ),
        ],
      ),
      _MenuSection(
        title: S.t(context, 'Penjualan'),
        items: [
          _MenuEntry(
            icon: Icons.assignment_return_outlined,
            color: AppColors.warning,
            label: S.t(context, 'Retur Penjualan'),
            subtitle: S.t(context, 'Pengembalian barang & approval'),
            onTap: () => _open(const ReturnListScreen()),
            roles: salesRoles,
          ),
          _MenuEntry(
            icon: Icons.pause_circle_outline,
            color: AppColors.textSecondary,
            label: S.t(context, 'Tahan Transaksi'),
            subtitle: S.t(context, 'Hold / suspend keranjang sementara'),
            onTap: () => _open(const HeldOrderScreen()),
            roles: salesRoles,
          ),
          _MenuEntry(
            icon: Icons.payments_outlined,
            color: AppColors.success,
            label: S.t(context, 'Cicilan & Uang Muka'),
            subtitle: S.t(context, 'Jadwal bayar & sisa pembayaran'),
            onTap: () => _open(const InstallmentScreen()),
            roles: salesRoles,
          ),
        ],
      ),
      _MenuSection(
        title: S.t(context, 'Pembelian'),
        items: [
          _MenuEntry(
            icon: Icons.shopping_cart_outlined,
            color: AppColors.primary,
            label: S.t(context, 'Purchase Order'),
            subtitle: S.t(context, 'Draft → Dipesan → Diterima'),
            onTap: () => _open(const PurchaseOrderListScreen()),
            roles: stockRoles,
          ),
          _MenuEntry(
            icon: Icons.local_shipping_outlined,
            color: AppColors.accent,
            label: S.t(context, 'Supplier'),
            subtitle: S.t(context, 'Pemasok & riwayat pembelian'),
            onTap: () => _open(const SupplierListScreen()),
            roles: stockRoles,
          ),
        ],
      ),
      _MenuSection(
        title: S.t(context, 'Inventori'),
        items: [
          _MenuEntry(
            icon: Icons.fact_check_outlined,
            color: AppColors.primary,
            label: S.t(context, 'Stock Opname'),
            subtitle: S.t(context, 'Hitung fisik & approval selisih'),
            onTap: () => _open(const OpnameListScreen()),
            roles: stockRoles,
          ),
          _MenuEntry(
            icon: Icons.swap_horiz,
            color: AppColors.success,
            label: S.t(context, 'Transfer Stok'),
            subtitle: S.t(context, 'Pindah stok antar outlet'),
            onTap: () => _open(const TransferListScreen()),
            roles: stockRoles,
          ),
          _MenuEntry(
            icon: Icons.history,
            color: AppColors.textSecondary,
            label: S.t(context, 'Mutasi Stok'),
            subtitle: S.t(context, 'Audit trail pergerakan stok'),
            onTap: () => _open(const StockMovementScreen()),
            roles: stockRoles,
          ),
          _MenuEntry(
            icon: Icons.kitchen_outlined,
            color: AppColors.warning,
            label: S.t(context, 'Bahan Baku & Resep'),
            subtitle: S.t(context, 'Raw material & recipe items'),
            onTap: () => _open(const RawMaterialScreen()),
            roles: stockRoles,
          ),
        ],
      ),
      _MenuSection(
        title: S.t(context, 'Loyalitas & Promo'),
        items: [
          _MenuEntry(
            icon: Icons.card_giftcard_outlined,
            color: AppColors.accent,
            label: S.t(context, 'Poin & Reward'),
            subtitle: S.t(context, 'Poin otomatis & katalog reward'),
            onTap: () => _open(const RewardListScreen()),
            roles: salesRoles,
          ),
          _MenuEntry(
            icon: Icons.discount_outlined,
            color: AppColors.success,
            label: S.t(context, 'Template Diskon'),
            subtitle: S.t(context, 'Persen, fixed, Buy X Get Y'),
            onTap: () => _open(const DiscountListScreen()),
            roles: salesRoles,
          ),
          _MenuEntry(
            icon: Icons.group_outlined,
            color: AppColors.primary,
            label: S.t(context, 'Grup Pelanggan'),
            subtitle: S.t(context, 'Regular, Member, Reseller'),
            onTap: () => _open(const CustomerGroupScreen()),
            roles: salesRoles,
          ),
        ],
      ),
      _MenuSection(
        title: S.t(context, 'Laporan'),
        items: [
          _MenuEntry(
            icon: Icons.bar_chart_outlined,
            color: AppColors.primary,
            label: S.t(context, 'Laporan Penjualan'),
            subtitle: S.t(context, 'Chart, top produk, export'),
            onTap: () => _open(const ReportScreen()),
            roles: reportRoles,
          ),
          _MenuEntry(
            icon: Icons.shopping_bag_outlined,
            color: AppColors.accent,
            label: S.t(context, 'Laporan Pembelian'),
            subtitle: S.t(context, 'PO, supplier, tren harga'),
            onTap: () => _open(const PurchaseReportScreen()),
            roles: reportRoles,
          ),
          _MenuEntry(
            icon: Icons.inventory_2_outlined,
            color: AppColors.warning,
            label: S.t(context, 'Laporan Inventori'),
            subtitle: S.t(context, 'Menipis, overstock, akurasi'),
            onTap: () => _open(const InventoryReportScreen()),
            roles: reportRoles,
          ),
        ],
      ),
      _MenuSection(
        title: S.t(context, 'Sistem'),
        items: [
          _MenuEntry(
            icon: Icons.manage_accounts_outlined,
            color: AppColors.primary,
            label: S.t(context, 'Pengguna & Peran'),
            subtitle: S.t(context, 'Owner, Admin, Kasir, Gudang'),
            onTap: () => _open(const UserListScreen()),
            roles: userAdminRoles,
          ),
          _MenuEntry(
            icon: Icons.fingerprint_outlined,
            color: AppColors.success,
            label: S.t(context, 'Absensi'),
            subtitle: S.t(context, 'Clock in/out pegawai'),
            onTap: () => _open(const AttendanceScreen()),
          ),
        ],
      ),
      _MenuSection(
        title: S.t(context, 'Perangkat & Akun'),
        items: [
          _MenuEntry(
            icon: Icons.print_outlined,
            color: AppColors.textSecondary,
            label: S.t(context, 'Printer'),
            subtitle: S.t(context, 'Printer thermal Bluetooth'),
            onTap: () => _open(const PrinterScreen()),
          ),
          _MenuEntry(
            icon: Icons.storefront_outlined,
            color: AppColors.primary,
            label: S.t(context, 'Outlet Aktif'),
            subtitle: S.t(context, 'Ganti outlet kasir'),
            onTap: () => _open(const OutletSelectionScreen()),
          ),
          _MenuEntry(
            icon: Icons.translate,
            color: AppColors.accent,
            label: S.t(context, 'Bahasa'),
            subtitle: S.t(context, 'Bahasa Indonesia / English'),
            onTap: _showLanguageSheet,
          ),
          _MenuEntry(
            icon: Icons.person_outline,
            color: AppColors.textSecondary,
            label: S.t(context, 'Profil'),
            subtitle: S.t(context, 'Akun, peran, dan outlet'),
            onTap: () => _open(const ProfileScreen()),
          ),
          _MenuEntry(
            icon: Icons.settings_outlined,
            color: AppColors.textSecondary,
            label: S.t(context, 'Pengaturan'),
            subtitle: S.t(context, 'Informasi aplikasi & server'),
            onTap: () => _open(const SettingsScreen()),
          ),
        ],
      ),
      _MenuSection(
        title: S.t(context, 'Informasi'),
        items: [
          _MenuEntry(
            icon: Icons.help_outline,
            color: AppColors.primary,
            label: S.t(context, 'Bantuan & Tentang'),
            subtitle: S.t(context, 'Panduan singkat dan versi aplikasi'),
            onTap: () => _open(const AboutScreen()),
          ),
        ],
      ),
    ];
  }
}

class _MenuSection {
  final String title;
  final List<_MenuEntry> items;
  _MenuSection({required this.title, required this.items});
}

class _MenuEntry {
  final IconData icon;
  final Color color;
  final String label;
  final String? subtitle;
  final int? badge;
  final VoidCallback onTap;

  /// Peran yang boleh melihat menu ini (lowercase, sesuai knownRoles).
  /// null = semua peran. Peran tak dikenal → tetap tampil (fail-open,
  /// server menegakkan 403).
  final List<String>? roles;
  _MenuEntry({
    required this.icon,
    required this.color,
    required this.label,
    this.subtitle,
    this.badge,
    required this.onTap,
    this.roles,
  });
}
