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

/// Layar cicilan & DP per order: lookup by order_id (GET /installments),
/// buat jadwal (POST /orders/{id}/installments),
/// bayar (POST /orders/{id}/payments).
class InstallmentScreen extends StatefulWidget {
  final int? initialOrderId;

  const InstallmentScreen({super.key, this.initialOrderId});

  @override
  State<InstallmentScreen> createState() => _InstallmentScreenState();
}

class _InstallmentScreenState extends State<InstallmentScreen> {
  final ApiService _api = ApiService();
  late final TextEditingController _orderCtrl = TextEditingController(
    text: widget.initialOrderId?.toString() ?? '',
  );

  List<Installment> _rows = [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  final bool _busy = false;
  List<Map<String, dynamic>> _payMethods = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialOrderId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
    }
  }

  @override
  void dispose() {
    _orderCtrl.dispose();
    super.dispose();
  }

  int? get _orderId => int.tryParse(_orderCtrl.text.trim());

  Future<void> _lookup() async {
    final orderId = _orderId;
    if (orderId == null || orderId <= 0) {
      setState(() => _error = S.tn(context, 'ID order wajib diisi.'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.get(
        '/installments',
        query: {'order_id': '$orderId'},
      );
      final data = response is Map ? response['data'] : response;
      if (!mounted) return;
      final list = data is List
          ? data
                .whereType<Map<String, dynamic>>()
                .map(Installment.fromJson)
                .toList()
          : <Installment>[];
      setState(() {
        _rows = list;
        _loading = false;
        _loaded = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loaded = true;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loaded = true;
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
      // Abaikan: payment_method_id opsional, user tetap bisa bayar nominal.
    }
  }

  Future<void> _openPlanDialog() async {
    final orderId = _orderId;
    if (orderId == null || orderId <= 0) {
      showAppSnackbar(
        context,
        S.tn(context, 'Isi ID order dulu.'),
        type: SnackType.warning,
      );
      return;
    }
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _PlanFormDialog(orderId: orderId),
    );
    if (created == true && mounted) {
      showAppSnackbar(
        context,
        S.tn(context, 'Jadwal cicilan tersimpan.'),
        type: SnackType.success,
      );
      await _lookup();
    }
  }

  Future<void> _openPayDialog() async {
    final orderId = _orderId;
    if (orderId == null || orderId <= 0) {
      showAppSnackbar(
        context,
        S.tn(context, 'Isi ID order dulu.'),
        type: SnackType.warning,
      );
      return;
    }
    await _loadPayMethods();
    if (!mounted) return;
    final paid = await showDialog<bool>(
      context: context,
      builder: (_) => _PayDialog(orderId: orderId, methods: _payMethods),
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
      appBar: AppBar(title: Text(S.t(context, 'Cicilan & DP'))),
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
                      labelText: S.t(context, 'ID Order'),
                      isDense: true,
                      prefixIcon: const Icon(Icons.receipt_long, size: 20),
                    ),
                    onSubmitted: (_) => _lookup(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: _loading ? null : _lookup,
                  child: Text(S.t(context, 'Cari')),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _openPlanDialog,
                    icon: const Icon(Icons.calendar_month_outlined, size: 18),
                    label: Text(
                      S.t(context, 'Buat Jadwal'),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _openPayDialog,
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: Text(
                      S.t(context, 'Bayar'),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
              ],
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
    if (!_loaded) {
      return EmptyState(
        icon: Icons.calendar_month_outlined,
        title: S.t(context, 'Cari cicilan per order'),
        message: S.t(context, 'Masukkan ID order lalu tekan Cari.'),
      );
    }
    if (_rows.isEmpty) {
      return EmptyState(
        icon: Icons.calendar_month_outlined,
        title: S.t(context, 'Belum ada jadwal cicilan'),
        message: S.t(context, 'Buat jadwal atau catat DP untuk order ini.'),
        actionLabel: S.t(context, 'Buat Jadwal'),
        onAction: _openPlanDialog,
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
        itemCount: _rows.length,
        itemBuilder: (_, i) => _rowCard(_rows[i]),
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
          '${installmentPlanLabel(ins.plan)} · ${ins.count}x',
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${S.tn(context, 'DP')}: ${Fmt.rupiah(ins.downPayment)} · ${S.tn(context, 'Sisa')}: ${Fmt.rupiah(ins.dueAmount)}',
          style: const TextStyle(fontSize: 11.5),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: StatusBadge(
          paymentStatusLabel(ins.paymentStatus),
          tone: toneForPaymentStatus(ins.paymentStatus ?? ''),
        ),
      ),
    );
  }
}

/// Dialog buat jadwal: plan + count + down_payment opsional.
class _PlanFormDialog extends StatefulWidget {
  final int orderId;

  const _PlanFormDialog({required this.orderId});

  @override
  State<_PlanFormDialog> createState() => _PlanFormDialogState();
}

class _PlanFormDialogState extends State<_PlanFormDialog> {
  final ApiService _api = ApiService();
  String _plan = 'monthly';
  final _countCtrl = TextEditingController(text: '3');
  final _dpCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _countCtrl.dispose();
    _dpCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final count = int.tryParse(_countCtrl.text.trim()) ?? 0;
    if (count <= 0) {
      setState(() => _error = S.tn(context, 'Jumlah cicilan wajib diisi.'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _api.post(
        '/orders/${widget.orderId}/installments',
        body: {
          'plan': _plan,
          'count': count,
          if (_dpCtrl.text.trim().isNotEmpty)
            'down_payment': Fmt.parseMoneyDigits(_dpCtrl.text),
        },
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
        _error = S.tn(context, 'Gagal menyimpan jadwal.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.t(context, 'Buat Jadwal Cicilan')),
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
            DropdownButtonFormField<String>(
              initialValue: _plan,
              decoration: InputDecoration(
                labelText: S.t(context, 'Skema'),
              ),
              items: const ['weekly', 'biweekly', 'monthly']
                  .map(
                    (p) =>
                        DropdownMenuItem(value: p, child: Text(p)),
                  )
                  .toList(),
              onChanged: (v) =>
                  setState(() => _plan = v ?? 'monthly'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _countCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: S.t(context, 'Jumlah cicilan *'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _dpCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: S.t(context, 'DP (Rp, opsional)'),
                prefixText: 'Rp ',
              ),
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
              : Text(S.t(context, 'Simpan')),
        ),
      ],
    );
  }
}

/// Dialog bayar: nominal + metode opsional (dropdown bila tersedia).
class _PayDialog extends StatefulWidget {
  final int orderId;
  final List<Map<String, dynamic>> methods;

  const _PayDialog({required this.orderId, required this.methods});

  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  final ApiService _api = ApiService();
  final _amountCtrl = TextEditingController();
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
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _api.post(
        '/orders/${widget.orderId}/payments',
        body: {
          'amount': amount,
          if (_methodId != null) 'payment_method_id': _methodId,
        },
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
      title: Text(S.t(context, 'Bayar Cicilan/DP')),
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
            if (widget.methods.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<int>(
                initialValue: _methodId,
                decoration: InputDecoration(
                  labelText: S.t(context, 'Metode (opsional)'),
                ),
                items: widget.methods.map((m) {
                  int id = 0;
                  final raw = m['id'];
                  if (raw is int) {
                    id = raw;
                  } else if (raw is num) {
                    id = raw.toInt();
                  } else {
                    id = int.tryParse(raw?.toString() ?? '') ?? 0;
                  }
                  return DropdownMenuItem(
                    value: id,
                    child: Text(m['name']?.toString() ?? 'Metode #$id'),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _methodId = v),
              ),
            ],
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
