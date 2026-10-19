import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/s.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/confirmation_dialog.dart';
import '../../widgets/payment_dialog.dart' show ThousandsInputFormatter;

/// Shift kasir (buka/tutup) dengan pencatatan kas awal, kas akhir,
/// kas harapan, dan selisih — dihitung oleh server.
///
/// Catatan keterbatasan API: server belum menyediakan endpoint daftar/
/// ambil shift berjalan, sehingga aplikasi mengingat shift yang dibuka
/// dari perangkat ini (SharedPreferences). Bila shift dibuka dari
/// perangkat/admin lain, tutup shift dari sana.
class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  static const _keyShiftId = 'shift_id';
  static const _keyShiftOutletId = 'shift_outlet_id';
  static const _keyShiftOutletName = 'shift_outlet_name';
  static const _keyShiftStartedAt = 'shift_started_at';
  static const _keyShiftStartingCash = 'shift_starting_cash';

  final ApiService _api = ApiService();
  final TextEditingController _cashCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  bool _loading = true;
  bool _submitting = false;

  int? _shiftId;
  int? _shiftOutletId;
  String _shiftOutletName = '';
  DateTime? _shiftStartedAt;
  double _shiftStartingCash = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_keyShiftId);
    if (!mounted) return;
    setState(() {
      _shiftId = id;
      _shiftOutletId = prefs.getInt(_keyShiftOutletId);
      _shiftOutletName = prefs.getString(_keyShiftOutletName) ?? '';
      final startedAt = prefs.getString(_keyShiftStartedAt);
      _shiftStartedAt = startedAt != null ? DateTime.tryParse(startedAt) : null;
      _shiftStartingCash = prefs.getDouble(_keyShiftStartingCash) ?? 0;
      _loading = false;
    });
  }

  Future<void> _saveShift(Map<String, dynamic> shift) async {
    final outletName = context.read<AuthProvider>().currentOutlet?.name ?? '';
    final prefs = await SharedPreferences.getInstance();
    final id = (shift['id'] as num?)?.toInt() ?? 0;
    await prefs.setInt(_keyShiftId, id);
    await prefs.setInt(
      _keyShiftOutletId,
      (shift['outlet_id'] as num?)?.toInt() ?? 0,
    );
    await prefs.setString(_keyShiftOutletName, outletName);
    await prefs.setString(
      _keyShiftStartedAt,
      shift['started_at']?.toString() ?? DateTime.now().toIso8601String(),
    );
    await prefs.setDouble(_keyShiftStartingCash, _num(shift['starting_cash']));
  }

  Future<void> _clearShift() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyShiftId);
    await prefs.remove(_keyShiftOutletId);
    await prefs.remove(_keyShiftOutletName);
    await prefs.remove(_keyShiftStartedAt);
    await prefs.remove(_keyShiftStartingCash);
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  Future<void> _openShift() async {
    if (_submitting) return;
    final outletId = context.read<AuthProvider>().currentOutletId;
    if (outletId == null) {
      showAppSnackbar(
        context,
        S.tn(context, 'Pilih outlet dulu.'),
        type: SnackType.warning,
      );
      return;
    }
    final cash = Fmt.parseMoneyDigits(_cashCtrl.text).toDouble();
    if (cash <= 0) {
      showAppSnackbar(
        context,
        S.tn(context, 'Isi kas awal shift.'),
        type: SnackType.warning,
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final response = await _api.post(
        '/shifts/open',
        body: {
          'outlet_id': outletId,
          'starting_cash': cash,
          'notes': _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
        },
      );
      final data = response is Map ? response['data'] : null;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Respons shift tidak valid');
      }
      await _saveShift(data);
      if (!mounted) return;
      _cashCtrl.clear();
      _notesCtrl.clear();
      showAppSnackbar(
        context,
        S.tn(context, 'Shift dibuka. Selamat bekerja!'),
        type: SnackType.success,
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        e.statusCode == 422 && e.message.toLowerCase().contains('shift terbuka')
            ? S.tn(
                context,
                'Outlet ini masih punya shift terbuka (mungkin dari perangkat/admin lain). Tutup shift tersebut dari panel admin web.',
              )
            : e.message,
        type: SnackType.error,
        duration: const Duration(seconds: 6),
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Gagal membuka shift.'),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _closeShift() async {
    if (_submitting || _shiftId == null) return;
    final cash = Fmt.parseMoneyDigits(_cashCtrl.text).toDouble();
    if (cash < 0) {
      showAppSnackbar(
        context,
        S.tn(context, 'Isi kas akhir shift.'),
        type: SnackType.warning,
      );
      return;
    }

    final ok = await confirmDialog(
      context,
      title: S.tn(context, 'Tutup shift?'),
      message: S.tn(
        context,
        'Kas akhir akan dicatat dan shift ditutup. Pastikan uang fisik di laci sudah dihitung.',
      ),
      confirmLabel: S.tn(context, 'Tutup Shift'),
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _submitting = true);
    try {
      final response = await _api.post(
        '/shifts/$_shiftId/close',
        body: {'ending_cash': cash},
      );
      final data = response is Map ? response['data'] : null;
      await _clearShift();
      if (!mounted) return;
      _cashCtrl.clear();
      if (data is Map) {
        final expected = _num(data['expected_cash']);
        final ending = _num(data['ending_cash']);
        final difference = _num(data['difference']);
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(S.t(dialogContext, 'Shift ditutup')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _resultRow(dialogContext, 'Kas Harapan', expected),
                _resultRow(dialogContext, 'Kas Aktual', ending),
                const Divider(),
                _resultRow(
                  dialogContext,
                  'Selisih',
                  difference,
                  color: difference.abs() < 0.01
                      ? AppColors.success
                      : difference > 0
                      ? AppColors.primary
                      : AppColors.error,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(S.t(dialogContext, 'Selesai')),
              ),
            ],
          ),
        );
      } else {
        showAppSnackbar(
          context,
          S.tn(context, 'Shift ditutup.'),
          type: SnackType.success,
        );
      }
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        e.message,
        type: SnackType.error,
        duration: const Duration(seconds: 6),
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Gagal menutup shift.'),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _resultRow(
    BuildContext context,
    String label,
    double amount, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5)),
          Text(
            Fmt.rupiah(amount),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t(context, 'Shift Kasir'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    final outlet = context.watch<AuthProvider>().currentOutlet;
    final outletMismatch =
        _shiftId != null &&
        _shiftOutletId != null &&
        outlet?.id != _shiftOutletId;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _shiftId == null
                            ? theme.colorScheme.surfaceContainerHighest
                            : AppColors.successSoft,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Icon(
                        _shiftId == null
                            ? Icons.lock_open_outlined
                            : Icons.point_of_sale_outlined,
                        size: 20,
                        color: _shiftId == null
                            ? theme.colorScheme.onSurfaceVariant
                            : const Color(0xFF047857),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _shiftId == null
                                ? S.t(
                                    context,
                                    'Belum ada shift di perangkat ini',
                                  )
                                : S.t(context, 'Shift sedang berjalan'),
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _shiftId == null
                                ? S.t(
                                    context,
                                    'Buka shift untuk mencatat kas awal kasir.',
                                  )
                                : (_shiftOutletName.isNotEmpty
                                      ? _shiftOutletName
                                      : outlet?.name ?? '-'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_shiftId != null) ...[
                  const Divider(height: AppSpacing.xl),
                  Text(
                    S.t(context, 'Dibuka'),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5),
                  ),
                  Text(
                    _shiftStartedAt == null
                        ? '-'
                        : Fmt.dateTime(_shiftStartedAt!.toIso8601String()),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _resultRow(
                    context,
                    S.t(context, 'Kas Awal'),
                    _shiftStartingCash,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (outletMismatch) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.warningSoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              '${S.t(context, 'Catatan')}: ${S.t(context, 'shift ini dibuka untuk outlet')} '
              '"$_shiftOutletName", ${S.t(context, 'sedangkan outlet aktif sekarang')} '
              '"${outlet?.name ?? '-'}". ${S.t(context, 'Tutup shift ini atau ganti outlet aktif.')}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text(
          _shiftId == null
              ? S.t(context, 'Buka Shift Baru')
              : S.t(context, 'Tutup Shift'),
          style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _cashCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: const [ThousandsInputFormatter()],
          decoration: InputDecoration(
            labelText: _shiftId == null
                ? S.t(context, 'Kas Awal (Rp)')
                : S.t(context, 'Kas Akhir / Aktual di Laci (Rp)'),
            prefixText: 'Rp ',
          ),
        ),
        if (_shiftId == null) ...[
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _notesCtrl,
            decoration: InputDecoration(
              labelText: S.t(context, 'Catatan (opsional)'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _openShift,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(S.t(context, 'Buka Shift')),
            ),
          ),
        ] else ...[
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _closeShift,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.stop_rounded, size: 20),
              label: Text(S.t(context, 'Tutup Shift & Hitung Kas')),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: S.tn(context, 'Lupakan shift di perangkat ini?'),
                message: S.tn(
                  context,
                  'Shift TETAP terbuka di server — hanya catatan lokal di perangkat ini yang dihapus. Gunakan hanya bila Anda yakin shift ditutup dari admin web.',
                ),
                confirmLabel: S.tn(context, 'Lupakan'),
                destructive: true,
              );
              if (!ok) return;
              await _clearShift();
              await _load();
            },
            child: Text(
              S.t(context, 'Lupakan catatan shift di perangkat ini'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Text(
          S.t(
            context,
            'Server menghitung kas harapan = kas awal + penjualan tunai − kas keluar (mis. refund). Selisih positif berarti laci lebih banyak dari perhitungan.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11.5,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
