import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/lang_provider.dart';
import '../../l10n/s.dart';
import '../../providers/auth_provider.dart';
import '../../services/offline_sync_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/confirmation_dialog.dart';
import '../../widgets/common/status_badge.dart';
import '../auth/login_screen.dart';
import '../customers/customer_list_screen.dart';
import '../outlet/outlet_selection_screen.dart';
import '../settings/settings_screen.dart';
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
    if (!mounted) return;
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
  _MenuEntry({
    required this.icon,
    required this.color,
    required this.label,
    this.subtitle,
    this.badge,
    required this.onTap,
  });
}
