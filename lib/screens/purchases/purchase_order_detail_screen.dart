import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../models/purchase_order.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/confirmation_dialog.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';

/// Detail purchase order: info, item, total, riwayat status,
/// dan tombol aksi workflow sesuai status.
class PurchaseOrderDetailScreen extends StatefulWidget {
  final int poId;
  final PurchaseOrder? initialOrder;

  const PurchaseOrderDetailScreen({
    super.key,
    required this.poId,
    this.initialOrder,
  });

  @override
  State<PurchaseOrderDetailScreen> createState() =>
      _PurchaseOrderDetailScreenState();
}

class _PurchaseOrderDetailScreenState extends State<PurchaseOrderDetailScreen> {
  final ApiService _api = ApiService();

  PurchaseOrder? _order;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder;
    if (widget.initialOrder != null) _loading = false;
    _load();
  }

  Future<void> _load() async {
    if (_order == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await _api.get('/purchase-orders/${widget.poId}');
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (data is Map<String, dynamic>) {
          _order = PurchaseOrder.fromJson(data);
          _error = null;
        } else {
          _error = S.tn(context, 'Purchase order tidak ditemukan.');
        }
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
        _error = S.tn(context, 'Gagal memuat detail purchase order.');
      });
    }
  }

  Future<void> _doAction(String endpoint, String successMessage) async {
    setState(() => _busy = true);
    try {
      await _api.post('/purchase-orders/${widget.poId}/$endpoint');
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

  Future<void> _confirmAndShip(PurchaseOrder order) async {
    final ok = await confirmDialog(
      context,
      title: order.status == 'draft'
          ? S.tn(context, 'Kirim PO ke supplier?')
          : S.tn(context, 'Tandai PO sudah dikirim?'),
      message: S.tn(
        context,
        'Status purchase order akan berubah dan tercatat di riwayat.',
      ),
      confirmLabel: S.tn(context, 'Kirim'),
    );
    if (!ok || !mounted) return;
    await _doAction(
      'ship',
      S.tn(context, 'Purchase order dikirim ke supplier.'),
    );
  }

  Future<void> _confirmAndReceive() async {
    final ok = await confirmDialog(
      context,
      title: S.tn(context, 'Terima barang?'),
      message: S.tn(
        context,
        'Stok produk akan bertambah sesuai item PO.',
      ),
      confirmLabel: S.tn(context, 'Terima'),
    );
    if (!ok || !mounted) return;
    await _doAction(
      'receive',
      S.tn(context, 'Purchase order diterima. Stok bertambah.'),
    );
  }

  Future<void> _confirmAndCancel() async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.tn(context, 'Batalkan PO?')),
        content: TextField(
          controller: reasonCtrl,
          autofocus: true,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: S.tn(context, 'Alasan (opsional)'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.tn(context, 'Batal')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, reasonCtrl.text.trim()),
            child: Text(S.tn(context, 'Batalkan PO')),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.post(
        '/purchase-orders/${widget.poId}/cancel',
        body: {if (reason.isNotEmpty) 'reason': reason},
      );
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Purchase order dibatalkan.'),
        type: SnackType.success,
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackbar(context, e.message, type: SnackType.error);
    } catch (_) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Gagal membatalkan PO.'),
        type: SnackType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      appBar: AppBar(
        title: Text(order?.displayNumber ?? S.t(context, 'Detail PO')),
      ),
      body: _buildBody(order),
      bottomNavigationBar: order == null ? null : _buildActions(order),
    );
  }

  Widget _buildBody(PurchaseOrder? order) {
    if (_loading && order == null) {
      return const LoadingSkeleton(items: 5, itemHeight: 64);
    }
    if (order == null) {
      return ErrorState(
        message: _error ?? S.tn(context, 'Purchase order tidak ditemukan.'),
        icon: Icons.inventory_2_outlined,
        onRetry: _load,
      );
    }

    final theme = Theme.of(context);
    final items = order.items ?? const <PoItem>[];
    final computedTotal = items.fold<double>(0, (s, e) => s + e.subtotal);
    final total = order.totalCost > 0 ? order.totalCost : computedTotal;

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
                          order.displayNumber,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                          ),
                        ),
                      ),
                      StatusBadge(
                        poStatusLabel(order.status),
                        tone: toneForPoStatus(order.status),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _infoRow(
                    S.t(context, 'Supplier'),
                    (order.supplierName?.isNotEmpty ?? false)
                        ? order.supplierName!
                        : 'Supplier #${order.supplierId}',
                  ),
                  _infoRow(
                    S.t(context, 'Tanggal'),
                    Fmt.dateTime(order.createdAt),
                  ),
                  if (order.note != null && order.note!.isNotEmpty)
                    _infoRow(S.t(context, 'Catatan'), order.note!),
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
                    S.t(context, 'Items'),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (item.productName?.isNotEmpty ?? false)
                                        ? item.productName!
                                        : S.t(context, 'Item'),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${item.qty} × ${Fmt.rupiah(item.costPrice)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              Fmt.rupiah(item.subtotal),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Divider(height: AppSpacing.xl),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          S.t(context, 'Total'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        Fmt.rupiah(total),
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (order.history != null && order.history!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.t(context, 'Riwayat Status'),
                      style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ...order.history!.map(
                      (h) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            StatusBadge(
                              poStatusLabel(h.status),
                              tone: toneForPoStatus(h.status),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                [
                                  if (h.by != null && h.by!.isNotEmpty) h.by!,
                                  Fmt.dateTime(h.at),
                                ].join(' · '),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11.5,
                                ),
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
          ],
          // Ruang bawah agar tidak tertutup tombol aksi.
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  /// Tombol aksi workflow sesuai status. Null bila tidak ada aksi.
  Widget? _buildActions(PurchaseOrder order) {
    if (_loading && _order == null) return null;
    final status = order.status;
    final canCancel = status != 'diterima' && status != 'cancelled';

    List<Widget> buttons = [];
    if (status == 'draft' || status == 'dipesan') {
      buttons.add(
        Expanded(
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _confirmAndShip(order),
            icon: const Icon(Icons.local_shipping_outlined, size: 18),
            label: Text(
              status == 'draft'
                  ? S.t(context, 'Kirim ke Supplier')
                  : S.t(context, 'Tandai Dikirim'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      );
    } else if (status == 'dikirim') {
      buttons.add(
        Expanded(
          child: FilledButton.icon(
            onPressed: _busy ? null : _confirmAndReceive,
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: Text(
              S.t(context, 'Terima Barang'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      );
    }
    if (canCancel) {
      buttons.add(
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _confirmAndCancel,
            icon: const Icon(
              Icons.cancel_outlined,
              size: 18,
              color: AppColors.error,
            ),
            label: Text(
              S.t(context, 'Batalkan'),
              style: const TextStyle(fontSize: 13, color: AppColors.error),
            ),
          ),
        ),
      );
    }
    if (buttons.isEmpty) return null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            for (int i = 0; i < buttons.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              buttons[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    final theme = Theme.of(context);
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
