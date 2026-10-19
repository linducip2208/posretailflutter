import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../../l10n/s.dart';
import '../../providers/auth_provider.dart';
import '../../services/printer_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_state.dart';

/// Pengaturan printer thermal Bluetooth: scan, hubungkan, uji cetak.
class PrinterScreen extends StatefulWidget {
  const PrinterScreen({super.key});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  final PrinterService _printer = PrinterService();

  List<BluetoothDevice> _devices = [];
  bool _scanning = false;
  bool _testing = false;
  String? _error;

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final devices = await _printer.scanDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _scanning = false;
        if (devices.isEmpty) {
          _error = S.tn(
            context,
            'Tidak ada printer Bluetooth ditemukan. Pastikan printer menyala dan Bluetooth aktif.',
          );
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = S.tn(
          context,
          'Gagal memindai Bluetooth. Periksa izin Bluetooth aplikasi.',
        );
      });
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() => _scanning = true);
    final ok = await _printer.connect(device);
    if (!mounted) return;
    setState(() => _scanning = false);
    showAppSnackbar(
      context,
      ok
          ? S.tn(context, 'Printer terhubung. Siap mencetak struk.')
          : S.tn(context, 'Gagal terhubung ke printer. Coba printer lain.'),
      type: ok ? SnackType.success : SnackType.error,
    );
  }

  Future<void> _testPrint() async {
    setState(() => _testing = true);
    final outletName = context.read<AuthProvider>().currentOutlet?.name;
    try {
      await _printer.printReceipt(
        orderNumber: 'TEST-${DateTime.now().millisecondsSinceEpoch % 10000}',
        date: DateTime.now(),
        cashier: context.read<AuthProvider>().user?.name ?? '-',
        outletName: outletName,
        items: [
          {
            'name': 'Contoh Produk',
            'qty': 1,
            'price': 10000.0,
            'subtotal': 10000.0,
          },
        ],
        subtotal: 10000,
        discount: 0,
        tax: 0,
        total: 10000,
        paid: 10000,
        change: 0,
      );
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Perintah cetak dikirim ke printer.'),
        type: SnackType.success,
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Gagal mencetak. Periksa koneksi printer.'),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _disconnect() async {
    await _printer.disconnect();
    if (!mounted) return;
    showAppSnackbar(
      context,
      S.tn(context, 'Printer diputuskan.'),
      type: SnackType.info,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = _printer.isConnected;

    return Scaffold(
      appBar: AppBar(title: Text(S.t(context, 'Printer'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: connected
                          ? AppColors.successSoft
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      connected ? Icons.print : Icons.print_disabled_outlined,
                      color: connected
                          ? const Color(0xFF047857)
                          : theme.colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          connected
                              ? S.t(context, 'Printer terhubung')
                              : S.t(context, 'Belum ada printer'),
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          S.t(
                            context,
                            'Gunakan printer thermal Bluetooth 58/80mm.',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: _scanning ? null : _scan,
            icon: _scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.bluetooth_searching, size: 18),
            label: Text(
              _scanning
                  ? S.t(context, 'Memindai...')
                  : S.t(context, 'Cari Printer Bluetooth'),
            ),
          ),
          if (connected) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _testing ? null : _testPrint,
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: Text(
                _testing
                    ? S.t(context, 'Mencetak...')
                    : S.t(context, 'Uji Cetak Struk'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: _disconnect,
              icon: const Icon(Icons.link_off, size: 18),
              label: Text(S.t(context, 'Putuskan Printer')),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(_error!, style: const TextStyle(fontSize: 12.5)),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            S.t(context, 'Perangkat terdeteksi'),
            style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_devices.isEmpty && !_scanning)
            EmptyState(
              icon: Icons.print_outlined,
              title: S.t(context, 'Belum ada perangkat'),
              message: S.t(
                context,
                'Tekan "Cari Printer Bluetooth" untuk memindai printer di sekitar.',
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final device in _devices)
                    ListTile(
                      leading: const Icon(Icons.print_outlined),
                      title: Text(
                        device.platformName.isNotEmpty
                            ? device.platformName
                            : S.t(context, '(tanpa nama)'),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        device.remoteId.toString(),
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _scanning ? null : () => _connect(device),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
