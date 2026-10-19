import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../l10n/s.dart';
import '../../theme/app_theme.dart';

/// Tentang aplikasi + bantuan singkat.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String _buildName = String.fromEnvironment(
    'FLUTTER_BUILD_NAME',
    defaultValue: 'dev',
  );
  static const String _buildNumber = String.fromEnvironment(
    'FLUTTER_BUILD_NUMBER',
    defaultValue: '0',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(S.t(context, 'Bantuan & Tentang'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Center(
            child: Column(
              children: [
                Image.asset('assets/logo.png', height: 56),
                const SizedBox(height: AppSpacing.md),
                Text(
                  S.t(context, 'POS Retail'),
                  style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
                ),
                Text(
                  '${S.t(context, 'Versi')} $_buildName+$_buildNumber',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            S.t(context, 'Bantuan Cepat'),
            style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                _faq(
                  context,
                  S.t(context, 'Bagaimana membuat transaksi baru?'),
                  S.t(
                    context,
                    'Buka tab Transaksi, pilih produk, lalu tekan tombol Bayar. '
                    'Pilih metode pembayaran dan masukkan uang yang diterima.',
                  ),
                ),
                _faq(
                  context,
                  S.t(context, 'Kenapa transaksi tersimpan tanpa koneksi?'),
                  S.t(
                    context,
                    'Transaksi otomatis masuk antrean offline dan dikirim ke '
                    'server saat koneksi kembali. Cek antrean di Lainnya → '
                    'Sinkronisasi.',
                  ),
                ),
                _faq(
                  context,
                  S.t(context, 'Bagaimana menghubungkan printer?'),
                  S.t(
                    context,
                    'Buka Lainnya → Printer, nyalakan printer thermal '
                    'Bluetooth 58/80mm, lalu tekan Cari Printer Bluetooth.',
                  ),
                ),
                _faq(
                  context,
                  S.t(context, 'Mengapa data produk tidak bisa diubah?'),
                  S.t(
                    context,
                    'Untuk menjaga konsistensi data, penambahan dan perubahan '
                    'produk/stok dilakukan dari panel admin web.',
                  ),
                ),
                _faq(
                  context,
                  S.t(context, 'Batasan laporan'),
                  S.t(
                    context,
                    'Server menampilkan maksimum 500 transaksi per rentang '
                    '(maksimal 93 hari). Persempit periode bila angka '
                    'ditandai terpotong.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            S.t(context, 'Informasi Teknis'),
            style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.dns_outlined, size: 18),
                  title: Text(
                    S.t(context, 'Server'),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  subtitle: Text(
                    ApiConfig.baseUrl,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.lock_outline, size: 18),
                  title: Text(
                    S.t(context, 'Sesi'),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  subtitle: Text(
                    S.t(
                      context,
                      'Token disimpan aman di perangkat (secure storage) dan '
                      'tidak pernah ditampilkan di layar.',
                    ),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Text(
              '© ${DateTime.now().year} POS Retail',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _faq(BuildContext context, String question, String answer) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      childrenPadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      title: Text(
        question,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            answer,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.5),
          ),
        ),
      ],
    );
  }
}
