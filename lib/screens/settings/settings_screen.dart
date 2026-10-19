import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/api_config.dart';
import '../../l10n/lang_provider.dart';
import '../../l10n/s.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/status_badge.dart';
import '../more/about_screen.dart';
import '../outlet/outlet_selection_screen.dart';

/// Pengaturan aplikasi: bahasa, outlet aktif, dan informasi server.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final lang = context.watch<LangProvider>();
    final outlet = auth.currentOutlet;

    return Scaffold(
      appBar: AppBar(title: Text(S.t(context, 'Pengaturan'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            S.t(context, 'Aplikasi'),
            style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.translate),
                  title: Text(
                    S.t(context, 'Bahasa'),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    lang.isEnglish ? 'English' : 'Bahasa Indonesia',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'id', label: Text('ID')),
                      ButtonSegment(value: 'en', label: Text('EN')),
                    ],
                    selected: {lang.code},
                    onSelectionChanged: (selection) =>
                        lang.setCode(selection.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(
                    S.t(context, 'Outlet Aktif'),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    outlet?.name ?? S.t(context, 'Belum dipilih'),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const OutletSelectionScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            S.t(context, 'Server'),
            style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: Text(
                    S.t(context, 'Alamat API'),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    ApiConfig.baseUrl,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text(
                    S.t(context, 'Batas Waktu Request'),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${ApiConfig.requestTimeout.inSeconds} ${S.t(context, 'detik')}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(
                    S.t(context, 'Bantuan & Tentang'),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Card(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.4,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      S.t(
                        context,
                        'Aplikasi kasir ini tidak menampilkan atau menyimpan password. Token sesi disimpan terenkripsi di perangkat.',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                  StatusBadge(S.t(context, 'Aman'), tone: BadgeTone.success),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
