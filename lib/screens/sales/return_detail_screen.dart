import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../models/sales_ops.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/confirmation_dialog.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';

/// Detail retur: info, item, alasan + aksi approve/reject sesuai status.
///
/// Kontrak backend: `GET /returns/{id}` (relasi `returnItems.product` +
/// `order`), `POST /returns/{id}/approve` → `completed`,
/// `POST /returns/{id}/reject {reason?}` → `rejected`. 404 berarti server
/// lama yang belum diperbarui — dilaporkan jujur.
class ReturnDetailScreen extends StatefulWidget {
  final int returnId;
  final ReturnOrder? initial;

  const ReturnDetailScreen({super.key, required this.returnId, this.initial});

  @override
  State<ReturnDetailScreen> createState() => _ReturnDetailScreenState();
}

class _ReturnDetailScreenState extends State<ReturnDetailScreen> {
  final ApiService _api = ApiService();

  ReturnOrder? _retur;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _retur = widget.initial;
    if (widget.initial != null) _loading = false;
    _load();
  }

  Future<void> _load() async {
    if (_retur == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await _api.get('/returns/${widget.returnId}');
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (data is Map<String, dynamic>) {
          _retur = ReturnOrder.fromJson(data);
          _error = null;
        } else {
          _error = S.tn(context, 'Retur tidak ditemukan.');
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_retur != null) {
        // GET /returns/{id} ada di backend baru; 404 berarti server lama
        // yang belum diperbarui: tampilkan data awal + pesan jujur.
        setState(() => _loading = false);
        showAppSnackbar(context, e.message, type: SnackType.error);
      } else {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (!mounted) return;
      if (_retur != null) {
        setState(() => _loading = false);
        showAppSnackbar(
          context,
          S.tn(context, 'Gagal memuat detail retur.'),
          type: SnackType.error,
        );
      } else {
        setState(() {
          _loading = false;
          _error = S.tn(context, 'Gagal memuat detail retur.');
        });
      }
    }
  }

  Future<void> _doAction(String endpoint, String successMessage,
      [Map<String, dynamic>? body]) async {
    setState(() => _busy = true);
    try {
      await _api.post('/returns/${widget.returnId}/$endpoint', body: body);
      if (!mounted) return;
      showAppSnackbar(context, successMessage, type: SnackType.success);
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackbar(context, e.message, type: SnackType.error);
    } catch (_) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Aksi gagal. Coba lagi.'),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmAndApprove() async {
    final ok = await confirmDialog(
      context,
      title: S.tn(context, 'Setujui retur?'),
      message: S.tn(context, 'Stok produk akan kembali bertambah.'),
      confirmLabel: S.tn(context, 'Setujui'),
    );
    if (!ok || !mounted) return;
    await _doAction(
      'approve',
      S.tn(context, 'Retur disetujui. Stok bertambah.'),
    );
  }

  Future<void> _confirmAndReject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectDialog(),
    );
    if (reason == null || !mounted) return;
    await _doAction(
      'reject',
      S.tn(context, 'Retur ditolak.'),
      {if (reason.isNotEmpty) 'reason': reason},
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _retur;
    return Scaffold(
      appBar: AppBar(
        title: Text(r?.displayNumber ?? S.t(context, 'Detail Retur')),
      ),
      body: _buildBody(r),
      bottomNavigationBar: r == null ? null : _buildActions(r),
    );
  }

  Widget _buildBody(ReturnOrder? r) {
    if (_loading && r == null) {
      return const LoadingSkeleton(items: 5, itemHeight: 64);
    }
    if (r == null) {
      return ErrorState(
        message: _error ?? S.tn(context, 'Retur tidak ditemukan.'),
        icon: Icons.assignment_return_outlined,
        onRetry: _load,
      );
    }
    final theme = Theme.of(context);
    final items = r.items ?? const <ReturnItem>[];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                      Expanded(
                        child: Text(
                          r.displayNumber,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                          ),
                        ),
                      ),
                      StatusBadge(
                        returnStatusLabel(r.status),
                        tone: toneForReturnStatus(r.status),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _infoRow(
                    S.t(context, 'Order'),
                    r.orderNumber ??
                        (r.orderId != null ? 'Order #${r.orderId}' : '-'),
                  ),
                  _infoRow(
                    S.t(context, 'Tanggal'),
                    Fmt.dateTime(r.createdAt),
                  ),
                  if (r.totalAmount > 0)
                    _infoRow(
                      S.t(context, 'Total'),
                      Fmt.rupiah(r.totalAmount),
                    ),
                  if (r.reason != null && r.reason!.isNotEmpty)
                    _infoRow(S.t(context, 'Alasan'), r.reason!),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.t(context, 'Item retur'),
                    style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (items.isEmpty)
                    Text(
                      S.t(context, 'Detail item tidak tersedia.'),
                      style: theme.textTheme.bodySmall,
                    )
                  else
                    ...items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                (item.productName?.isNotEmpty ?? false)
                                    ? item.productName!
                                    : 'Produk #${item.productId}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              '× ${item.qty}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget? _buildActions(ReturnOrder r) {
    if (_loading && _retur == null) return null;
    if (r.status != 'pending') return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _confirmAndApprove,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(
                  S.t(context, 'Setujui'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _confirmAndReject,
                icon: const Icon(
                  Icons.cancel_outlined,
                  size: 18,
                  color: AppColors.error,
                ),
                label: Text(
                  S.t(context, 'Tolak'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.error,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog alasan penolakan: controller dimiliki dialog sendiri agar tidak
/// di-dispose saat rute dialog masih beranimasi keluar.
class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.tn(context, 'Tolak retur?')),
      content: TextField(
        controller: _reasonCtrl,
        autofocus: true,
        maxLines: 2,
        decoration: InputDecoration(
          labelText: S.tn(context, 'Alasan penolakan'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(S.tn(context, 'Batal')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, _reasonCtrl.text.trim()),
          child: Text(S.tn(context, 'Tolak Retur')),
        ),
      ],
    );
  }
}
