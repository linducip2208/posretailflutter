import 'package:flutter/material.dart';
import '../../config/api_config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _taxPercent = 11;
  String _apiUrl = ApiConfig.baseUrl;
  int _outletId = 1;
  bool _autoPrint = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Pengaturan', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pajak (PPN)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _taxPercent,
                        min: 0,
                        max: 20,
                        divisions: 20,
                        label: '$_taxPercent%',
                        onChanged: (v) => setState(() => _taxPercent = v),
                      ),
                    ),
                    Text('${_taxPercent.toInt()}%', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ],
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
                Text('Outlet', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Outlet ID',
                    border: OutlineInputBorder(),
                    helperText: 'ID outlet default untuk transaksi',
                  ),
                  keyboardType: TextInputType.number,
                  controller: TextEditingController(text: '$_outletId'),
                  onChanged: (v) => _outletId = int.tryParse(v) ?? 1,
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
                Text('API Server', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'URL API',
                    border: OutlineInputBorder(),
                    helperText: 'Alamat server backend',
                  ),
                  controller: TextEditingController(text: _apiUrl),
                  onChanged: (v) => _apiUrl = v,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        Card(
          child: SwitchListTile(
            title: const Text('Auto Print Struk', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Cetak otomatis setelah pembayaran'),
            value: _autoPrint,
            onChanged: (v) => setState(() => _autoPrint = v),
          ),
        ),

        const SizedBox(height: 24),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tentang', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('POS Retail v1.0.0', style: theme.textTheme.bodyMedium),
                Text('Sistem Kasir Modern', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
