import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../models/sales_ops.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';

/// Layar cicilan: daftar dari `GET /installments` (filter status server,
/// saring order di sisi klien) + bayar per cicilan via
/// `POST /installments/{id}/pay` (`amount` + `payment_method_id` wajib).
///
/// Backend tidak punya endpoint buat-jadwal maupun filter `order_id`,
/// jadi kedua hal itu TIDAK dipanggil (lihat docs/BACKEND_PATCH_SALES.md).
class InstallmentScreen extends StatefulWidget {
  final int? initialOrderId;

  const InstallmentScreen({super.key, this.initialOrderId});

  @override
  State<InstallmentScreen> createState() => _InstallmentScreenState();
}

class _InstallmentScreenState extends State<InstallmentScreen> {
  static const _filters = ['semua', 'pending', 'paid', 'overdue'];

  final ApiService _api = ApiService();
  late final TextEditingController _orderCtrl = TextEditingController(
    text: widget.initialOrderId?.toString() ?? '',
  );

  List<Installment> _rows = [];
  bool _loading = true;
  String? _error;
  String _statusFilter = 'semua';
  List<Map<String, dynamic>> _payMethods = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
  }

  @override
  void dispose() {
    _orderCtrl.dispose();
    super.dispose();
  }

  int? get _orderFilter => int.tryParse(_orderCtrl.text.trim());

  List<Installment> get _visible {
    final f = _orderFilter;
    if (f == null || f <= 0) return _rows;
    return _rows.where((e) => e.orderId == f).toList();
  }

  Future<void> _lookup() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.get(
        '/installments',
        query: {
          'per_page': '50',
          if (_statusFilter != 'semua') 'status': _statusFilter,
        },
      );
      final data = response is Map ? response['data'] : response;
      if (!mounted) return;
      setState(() {
        _rows = data is List
            ? data
                  .whereType<Map<String, dynamic>>()
                  .map(Installment.fromJson)
                  .toList()
            : <Installment>[];
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = S.tn(context, 'Gagal memuat cicilan.');
      });
    }
  }

  Future<void> _loadPayMethods() async {
    if (_payMethods.isNotEmpty) return;
    try {
      final response = await _api.get('/payment-methods');
      final data = response is Map ? response['data'] : response;
      if (data is List) {
        _payMethods = data.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {
      // Gagal dimuat: dialog bayar menampilkan pesan jujur + retry.
    }
  }

  Future<void> _openPayDialog(Installment ins) async {
    await _loadPayMethods();
    if (!mounted) return;
    final paid = await showDialog<bool>(
      context: context,
      builder: (_) => _PayDialog(installment: ins, methods: _payMethods),
    );
    if (paid == true && mounted) {
      showAppSnackbar(
        context,
        S.tn(context, 'Pembayaran tercatat.'),
        type: SnackType.success,
      );
      await _lookup();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Cicilan & DP')),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Muat ulang'),
            onPressed: _loading ? null : _lookup,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _orderCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: S.t(context, 'Saring ID Order (opsional)'),
                      isDense: true,
                      prefixIcon: const Icon(Icons.receipt_long, size: 20),
                    ),
                    onSubmitted: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: () => setState(() {}),
                  child: Text(S.t(context, 'Cari')),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: _filters.map((f) {
                final selected = _statusFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    label: Text(
                      f == 'semua'
                          ? S.t(context, 'Semua')
                          : installmentStatusLabel(f),
                    ),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _statusFilter = f);
                      _lookup();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingSkeleton(items: 4, itemHeight: 64);
    if (_error != null) return ErrorState(message: _error!, onRetry: _lookup);
    final rows = _visible;
    if (rows.isEmpty) {
      return EmptyState(
        icon: Icons.calendar_month_outlined,
        title: S.t(context, 'Belum ada cicilan'),
        message: S.t(
          context,
          'Cicilan dibuat dari penjualan kredit di kasir.',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _lookup,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        itemCount: rows.length,
        itemBuilder: (_, i) => _rowCard(rows[i]),
      ),
    );
  }

  Widget _rowCard(Installment ins) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.calendar_month_outlined, size: 20),
        ),
        title: Text(
          '${S.tn(context, 'Cicilan')} #${ins.installmentNumber}',
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (ins.orderId != null) 'Order #${ins.orderId}',
            Fmt.rupiah(ins.amount),
            '${S.tn(context, 'Jatuh tempo')}: ${Fmt.date(ins.dueDate)}',
          ].join(' · '),
          style: const TextStyle(fontSize: 11.5),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusBadge(
              installmentStatusLabel(ins.status),
              tone: toneForInstallmentStatus(ins.status),
            ),
            if (!ins.isPaid) ...[
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: () => _openPayDialog(ins),
                child: Text(S.t(context, 'Bayar')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dialog bayar satu cicilan: nominal + metode wajib
/// → POST /installments/{id}/pay.
class _PayDialog extends StatefulWidget {
  final Installment installment;
  final List<Map<String, dynamic>> methods;

  const _PayDialog({required this.installment, required this.methods});

  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  final ApiService _api = ApiService();
  late final TextEditingController _amountCtrl = TextEditingController(
    text: widget.installment.amount > 0
        ? widget.installment.amount.toInt().toString()
        : '',
  );
  int? _methodId;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = Fmt.parseMoneyDigits(_amountCtrl.text);
    if (amount <= 0) {
      setState(() => _error = S.tn(context, 'Nominal wajib diisi.'));
      return;
    }
    // Backend mewajibkan payment_method_id.
    if (_methodId == null) {
      setState(() => _error = S.tn(context, 'Pilih metode pembayaran.'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _api.post(
        '/installments/${widget.installment.id}/pay',
        body: {'amount': amount, 'payment_method_id': _methodId},
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = S.tn(context, 'Gagal mencatat pembayaran.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        '${S.t(context, 'Bayar')} ${S.tn(context, 'Cicilan')} #${widget.installment.installmentNumber}',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(_error!, style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            TextField(
              controller: _amountCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '${S.t(context, 'Nominal')} *',
                prefixText: 'Rp ',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (widget.methods.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  S.t(
                    context,
                    'Metode pembayaran belum tersedia. Muat ulang lalu coba lagi.',
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              )
            else
              DropdownButtonFormField<int>(
                initialValue: _methodId,
                decoration: InputDecoration(
                  labelText: '${S.t(context, 'Metode')} *',
                ),
                items: widget.methods.map((m) {
                  final raw = m['id'];
                  final int id = raw is int
                      ? raw
                      : raw is num
                      ? raw.toInt()
                      : int.tryParse(raw?.toString() ?? '') ?? 0;
                  return DropdownMenuItem(
                    value: id,
                    child: Text(m['name']?.toString() ?? 'Metode #$id'),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _methodId = v),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: Text(S.t(context, 'Batal')),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(S.t(context, 'Bayar')),
        ),
      ],
    );
  }
}
