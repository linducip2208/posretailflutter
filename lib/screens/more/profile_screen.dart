import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/s.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/status_badge.dart';
import '../outlet/outlet_selection_screen.dart';

/// Profil kasir: identitas pengguna, peran, dan outlet yang bisa diakses.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  String _roleLabel(BuildContext context, String? role) {
    switch (role) {
      case 'owner':
        return S.t(context, 'Owner');
      case 'manager':
        return S.t(context, 'Manager');
      case 'admin':
        return S.t(context, 'Admin');
      case 'kasir':
        return S.t(context, 'Kasir');
      case 'gudang':
        return S.t(context, 'Gudang');
      default:
        return role ?? '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final outlet = auth.currentOutlet;

    return Scaffold(
      appBar: AppBar(title: Text(S.t(context, 'Profil'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      (user?.name.isNotEmpty ?? false)
                          ? user!.name.substring(0, 1).toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? '-',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.email ?? '-',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        StatusBadge(
                          _roleLabel(context, user?.role),
                          tone: BadgeTone.info,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            S.t(context, 'Outlet Aktif'),
            style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: Text(
                outlet?.name ?? S.t(context, 'Belum dipilih'),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                outlet?.code != null && outlet!.code!.isNotEmpty
                    ? 'Kode: ${outlet.code}'
                    : S.t(
                        context,
                        'Transaksi baru akan tercatat pada outlet ini.',
                      ),
                style: const TextStyle(fontSize: 11.5),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const OutletSelectionScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            S.t(context, 'Kewenangan'),
            style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.verified_user_outlined, size: 18),
                  title: Text(
                    '${S.t(context, 'Peran')}: ${_roleLabel(context, user?.role)}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.lock_outline, size: 18),
                  title: Text(
                    S.t(
                      context,
                      'Akses transaksi (kasir) mengikuti izin server. Perubahan data master dilakukan dari panel admin web.',
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
