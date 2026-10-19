import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/s.dart';
import '../models/payment_method.dart';
import '../services/api_service.dart';
import '../services/offline_sync_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// Formatter ribuan untuk input nominal (mengetik `50000` → `50.000`).
class ThousandsInputFormatter extends TextInputFormatter {
  const ThousandsInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final value = int.tryParse(digits) ?? 0;
    final formatted = Fmt.thousand(value);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class PaymentEntry {
  PaymentMethod method;
  double amount;

  PaymentEntry({required this.method, this.amount = 0});
}

/// Lembar pembayaran kasir:
/// - pemilihan metode nyata dari server (`/payment-methods`),
/// - tunai dengan preset uang + perhitungan kembalian otomatis,
/// - split payment (API mendukung 1..10 pembayaran per order).
class PaymentDialog extends StatefulWidget {
  final double total;

  /// Kasbon/cicilan: DP boleh lebih kecil dari total. Server mencatat
  /// status pembayaran `partial` + sisa tagihan (`remaining_amount`).
  final bool allowPartial;

  const PaymentDialog({
    super.key,
    required this.total,
    this.allowPartial = false,
  });

  /// Tampilkan sebagai bottom sheet. Return daftar pembayaran valid
  /// (tidak null & tidak kosong berarti kasir menekan "Bayar").
  static Future<List<PaymentEntry>?> show(
    BuildContext context, {
    required double total,
    bool allowPartial = false,
  }) {
    return showModalBottomSheet<List<PaymentEntry>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PaymentDialog(total: total, allowPartial: allowPartial),
    );
  }

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  final ApiService _api = ApiService();
  final OfflineSyncService _offline = OfflineSyncService();
  final TextEditingController _amountCtrl = TextEditingController();

  List<PaymentMethod> _methods = [];
  final List<PaymentEntry> _entries = [];
  int _activeIndex = 0;
  bool _isLoadingMethods = true;
  String? _loadError;
  bool _submitting = false;

  /// True bila daftar metode berasal dari cache lokal (perangkat offline).
  /// Id metode sama dengan server sehingga payload antrean tetap valid.
  bool _usingCachedMethods = false;

  @override
  void initState() {
    super.initState();
    _loadMethods();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMethods() async {
    try {
      final response = await _api.get('/payment-methods');
      final dynamic data = response is Map
          ? (response['data'] ?? response)
          : response;
      final raw = data is List
          ? data.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      final list = raw.map(PaymentMethod.fromJson).toList();

      if (!mounted) return;
      setState(() {
        _methods = list;
        _usingCachedMethods = false;
        if (list.isNotEmpty) {
          _entries
            ..clear()
            ..add(PaymentEntry(method: list.first));
          _activeIndex = 0;
          _applyDefaultAmount();
        } else {
          _loadError = S.tn(
            context,
            'Metode pembayaran belum diatur di server. Hubungi admin.',
          );
        }
        _isLoadingMethods = false;
      });
      if (list.isNotEmpty) {
        // Simpan untuk checkout offline berikutnya (fire-and-forget).
        unawaited(_offline.cachePaymentMethods(raw));
      }
    } on ApiNetworkException catch (_) {
      // Offline: pakai daftar metode tersimpan bila ada.
      final cached = await _offline.getCachedPaymentMethods();
      if (!mounted) return;
      final cachedMethods = cached.map(PaymentMethod.fromJson).toList();
      setState(() {
        if (cachedMethods.isNotEmpty) {
          _methods = cachedMethods;
          _usingCachedMethods = true;
          _entries
            ..clear()
            ..add(PaymentEntry(method: cachedMethods.first));
          _activeIndex = 0;
          _applyDefaultAmount();
          _loadError = null;
        } else {
          _loadError = S.tn(
            context,
            'Tidak dapat terhubung ke server. Periksa jaringan Anda.',
          );
        }
        _isLoadingMethods = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _isLoadingMethods = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = S.tn(context, 'Gagal memuat metode pembayaran.');
        _isLoadingMethods = false;
      });
    }
  }

  /// Entri terpilih; null saat metode belum termuat (mis. gagal load).
  PaymentEntry? get _active => _entries.isEmpty ? null : _entries[_activeIndex];

  double get _totalPaid => _entries.fold(0, (s, e) => s + e.amount);
  double get _remaining => widget.total - _totalPaid;

  static bool isCashMethod(PaymentMethod method) {
    final haystack = '${method.code} ${method.name}'.toLowerCase();
    return haystack.contains('cash') || haystack.contains('tunai');
  }

  /// Untuk metode non-tunai, isi otomatis dengan sisa tagihan
  /// (kasir tidak perlu mengetik nominal persis).
  void _applyDefaultAmount() {
    final entry = _active;
    if (entry == null) return;
    if (entry.amount <= 0 && !isCashMethod(entry.method)) {
      final remaining = widget.total - (_totalPaid - entry.amount);
      if (remaining > 0) entry.amount = remaining;
    }
    _syncAmountController();
  }

  void _syncAmountController() {
    final entry = _active;
    final text = entry != null && entry.amount > 0
        ? Fmt.thousand(entry.amount)
        : '';
    _amountCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _selectMethod(PaymentMethod method) {
    setState(() {
      final entry = _active;
      if (entry == null) return;
      entry.method = method;
      _applyDefaultAmount();
    });
  }

  void _setActiveAmount(double amount) {
    setState(() {
      final entry = _active;
      if (entry == null) return;
      entry.amount = amount;
      _syncAmountController();
    });
  }

  void _addEntry() {
    if (_methods.isEmpty) return;
    setState(() {
      _entries.add(PaymentEntry(method: _methods.first));
      _activeIndex = _entries.length - 1;
      _applyDefaultAmount();
    });
  }

  void _removeEntry(int index) {
    if (_entries.length <= 1) return;
    setState(() {
      _entries.removeAt(index);
      _activeIndex = _activeIndex.clamp(0, _entries.length - 1);
      _syncAmountController();
    });
  }

  void _selectEntry(int index) {
    setState(() {
      _activeIndex = index;
      _syncAmountController();
    });
  }

  /// Preset nominal uang: uang pas + pembulatan umum.
  List<double> _quickAmounts() {
    final base = _remaining > 0 ? _remaining : widget.total;
    final amounts = <double>{base};
    for (final step in [5000, 10000, 20000, 50000, 100000]) {
      final rounded = ((base / step).ceil()) * step;
      if (rounded > base) amounts.add(rounded.toDouble());
    }
    for (final common in [50000.0, 100000.0]) {
      if (common > base) amounts.add(common);
    }
    final list = amounts.where((a) => a > 0).toList()..sort();
    return list.take(5).toList();
  }

  bool get _canSubmit {
    if (_submitting || _isLoadingMethods || _methods.isEmpty) return false;
    if (_entries.isEmpty) return false;
    if (_entries.any((e) => e.method.id == 0)) return false;
    if (_entries.any((e) => e.amount <= 0)) return false;
    if (widget.allowPartial) return true;
    return _totalPaid + 0.001 >= widget.total;
  }

  void _submit() {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    final entries = _entries
        .where((e) => e.amount > 0)
        .map((e) => PaymentEntry(method: e.method, amount: e.amount))
        .toList();
    Navigator.of(context).pop(entries);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              S.t(context, 'Pembayaran'),
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.t(context, 'Total Tagihan'),
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        Fmt.rupiah(widget.total),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.total > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _remaining <= 0
                            ? S.t(context, 'Kembalian')
                            : S.t(context, 'Kurang'),
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        Fmt.rupiah(_remaining.abs()),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _remaining <= 0
                              ? AppColors.success
                              : AppColors.error,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (_loadError != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.error,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _loadError!,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _loadError = null;
                          _isLoadingMethods = true;
                        });
                        _loadMethods();
                      },
                      child: Text(S.t(context, 'Coba Lagi')),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),

            if (_isLoadingMethods)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              // Ringkasan pembayaran bila sudah lebih dari satu metode.
              if (_entries.length > 1)
                Column(
                  children: [
                    for (var i = 0; i < _entries.length; i++) _entryRow(i),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),

              Text(
                S.t(context, 'Metode Pembayaran'),
                style: theme.textTheme.titleSmall?.copyWith(fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: _methods.map((m) {
                  final selected = m.id == _active?.method.id;
                  return ChoiceChip(
                    label: Text(m.name),
                    selected: selected,
                    onSelected: (_) => _selectMethod(m),
                    avatar: Icon(
                      isCashMethod(m)
                          ? Icons.payments_outlined
                          : Icons.credit_card,
                      size: 16,
                      color: selected ? AppColors.primaryDark : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.lg),

              if (_usingCachedMethods)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.cloud_off_outlined,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          S.t(
                            context,
                            'Mode offline — memakai daftar metode tersimpan.',
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: const [ThousandsInputFormatter()],
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
                decoration: InputDecoration(
                  labelText: S.t(context, 'Nominal Dibayar'),
                  prefixText: 'Rp ',
                  prefixStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  hintText: '0',
                ),
                onChanged: (v) =>
                    _setActiveAmount(Fmt.parseMoneyDigits(v).toDouble()),
              ),
              const SizedBox(height: AppSpacing.sm),

              if (_active != null && isCashMethod(_active!.method))
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final amount in _quickAmounts())
                      ActionChip(
                        label: Text(
                          amount == _remaining
                              ? S.t(context, 'Uang Pas')
                              : Fmt.thousand(amount),
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () => _setActiveAmount(amount),
                      ),
                  ],
                ),

              if (_entries.length == 1 && _methods.length > 1) ...[
                const SizedBox(height: AppSpacing.md),
                TextButton.icon(
                  onPressed: _addEntry,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(S.t(context, 'Split / Tambah Pembayaran')),
                ),
              ],

              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _remaining > 0
                              ? widget.allowPartial
                                    ? '${S.t(context, 'Bayar DP')} · ${Fmt.rupiah(_totalPaid)}'
                                    : '${S.t(context, 'Kurang')} ${Fmt.rupiah(_remaining)}'
                              : '${S.t(context, 'Bayar')} · ${Fmt.rupiah(_totalPaid)}',
                          style: const TextStyle(fontSize: 15.5),
                        ),
                ),
              ),
              if (widget.allowPartial && _remaining > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${S.t(context, 'Sisa tagihan')} ${Fmt.rupiah(_remaining)} '
                  '${S.t(context, 'akan tercatat sebagai kasbon pelanggan.')}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Text(
                S.t(
                  context,
                  'Pesanan dicatat setelah server mengonfirmasi. Bila offline, transaksi masuk antrean kirim.',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(fontSize: 10.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _entryRow(int index) {
    final entry = _entries[index];
    final selected = index == _activeIndex;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: () => _selectEntry(index),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isCashMethod(entry.method)
                    ? Icons.payments_outlined
                    : Icons.credit_card,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  entry.method.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                entry.amount > 0 ? Fmt.rupiah(entry.amount) : '-',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                onPressed: () => _removeEntry(index),
                icon: const Icon(Icons.close, size: 16),
                visualDensity: VisualDensity.compact,
                tooltip: S.t(context, 'Hapus pembayaran'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
