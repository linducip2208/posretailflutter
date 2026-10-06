import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/api_config.dart';
import '../../l10n/s.dart';
import '../../l10n/lang_provider.dart';
import '../../providers/auth_provider.dart';
import '../outlet/outlet_selection_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final lang = context.watch<LangProvider>();
    final outlet = auth.currentOutlet;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(S.t(context, 'Pengaturan'),
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),

        Card(
          child: ListTile(
            leading: const Icon(Icons.store),
            title: Text(S.t(context, 'Outlet Aktif'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(outlet != null
                ? '${outlet.name}${outlet.code != null ? ' (${outlet.code})' : ''}'
                : S.t(context, 'Belum dipilih')),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OutletSelectionScreen()),
              );
            },
          ),
        ),

        const SizedBox(height: 12),

        Card(
          child: ListTile(
            leading: const Icon(Icons.person),
            title: Text(S.t(context, 'Kasir'), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${auth.user?.name ?? '-'}${auth.role != null ? ' · ${auth.role}' : ''}'),
          ),
        ),

        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.language),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(S.t(context, 'Bahasa'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'id', label: Text('ID')),
                    ButtonSegment(value: 'en', label: Text('EN')),
                  ],
                  selected: {lang.code},
                  onSelectionChanged: (s) => lang.setCode(s.first),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.t(context, 'Server'),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                SelectableText(ApiConfig.baseUrl, style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(S.t(context, 'Pajak & diskon dihitung server saat checkout.'),
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.t(context, 'Tentang'),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('POS Retail v1.0.0', style: theme.textTheme.bodyMedium),
                Text(S.t(context, 'Sistem Kasir Modern'),
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
