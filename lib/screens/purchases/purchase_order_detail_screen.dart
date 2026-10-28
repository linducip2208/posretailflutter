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

  /// Kirim aksi POST ke sub-resource PO: `order` (draft → ordered, tanpa
  /// body), `cancel` (`{reason?}` → `cancelled`), dan `receive` (→
  /// `received`). Ketiganya ada di backend baru; 404 berarti server lama
  /// yang belum diperbarui — diterjemahkan jujur agar bisa retry setelah
  /// backend diupdate.
  Future<bool> _doAction(String endpoint, String successMessage) async {
    setState(() => _busy = true);
    try {
      await _api.post('/purchase-orders/${widget.poId}/$endpoint');
      if (!mounted) return false;
      showAppSnackbar(context, successMessage, type: SnackType.success);
      await _load();
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      showAppSnackbar(
        context,
        e.statusCode == 404 ? _missingEndpointMessage(endpoint) : e.message,
        type: SnackType.error,
      );
      return false;
    } catch (_) {
      if (!mounted) return false;
      showAppSnackbar(
        context,
        S.tn(context, 'Aksi gagal. Coba lagi.'),
        type: SnackType.error,
      );
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Pesan jujur saat endpoint belum tersedia di server: bukan salah user,
  /// dan aksi bisa dicoba lagi setelah backend diupdate.
  String _missingEndpointMessage(String endpoint) {
    final action = endpoint == 'cancel' ? 'Pembatalan' : 'Pengiriman';
    return S.tn(
      context,
      '$action PO belum tersedia di server (mungkin belum diperbarui). Coba lagi nanti.',
    );
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
      'order',
      S.tn(context, 'Purchase order dikirim ke supplier.'),
    );
  }

  Future<void> _confirmAndReceive() async {
    final ok = await confirmDialog(
      context,
      title: S.tn(context, 'Terima barang?'),
      // Backend TIDAK menambah stok otomatis (stok & payable dicatat manual
      // seperti alur web); receive hanya mengubah status + memposting jurnal.
      message: S.tn(
        context,
        'Status PO menjadi Diterima dan jurnal pembelian diposting. Stok dicatat manual seperti alur web.',
      ),
      confirmLabel: S.tn(context, 'Terima'),
    );
    if (!ok || !mounted) return;
    await _doAction(
      'receive',
      S.tn(context, 'Purchase order diterima dan tercatat di jurnal.'),
    );
  }

  Future<void> _confirmAndCancel() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _CancelPoDialog(),
    );
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
      showAppSnackbar(
        context,
        e.statusCode == 404 ? _missingEndpointMessage('cancel') : e.message,
        type: SnackType.error,
      );
    } catch (_) {      if (!mounted) return;
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

  /// Tombol aksi workflow sesuai status backend
  /// (`draft`/`ordered`/`received`/`cancelled`). Null bila tidak ada aksi.
  /// `order`/`receive`/`cancel` didukung backend baru; 404 dari server
  /// lama diterjemahkan jujur oleh [_doAction]/[_confirmAndCancel].
  Widget? _buildActions(PurchaseOrder order) {
    if (_loading && _order == null) return null;
    final status = order.status;
    final isOpen = status == 'draft' || status == 'ordered';
    final canCancel = status != 'received' && status != 'cancelled';

    List<Widget> buttons = [];
    if (isOpen) {
      buttons.add(
        FilledButton.icon(
          onPressed: _busy ? null : () => _confirmAndShip(order),
          icon: const Icon(Icons.local_shipping_outlined, size: 18),
          label: Text(
            status == 'draft'
                ? S.t(context, 'Kirim ke Supplier')
                : S.t(context, 'Tandai Dikirim'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      );
      buttons.add(
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _confirmAndReceive,
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: Text(
            S.t(context, 'Terima Barang'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      );
    } else if (status == 'received' || status == 'cancelled') {
      // Terminal: tidak ada aksi.
    }
    if (canCancel) {
      buttons.add(
        OutlinedButton.icon(
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
      );
    }
    if (buttons.isEmpty) return null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: buttons
              .map(
                (b) => SizedBox(
                  width: (MediaQuery.of(context).size.width - 48) / 2,
                  child: b,
                ),
              )
              .toList(),
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

/// Dialog alasan pembatalan PO: controller dimiliki dialog sendiri agar
/// tidak di-dispose saat rute dialog masih beranimasi keluar.
class _CancelPoDialog extends StatefulWidget {
  const _CancelPoDialog();

  @override
  State<_CancelPoDialog> createState() => _CancelPoDialogState();
}

class _CancelPoDialogState extends State<_CancelPoDialog> {
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.tn(context, 'Batalkan PO?')),
      content: TextField(
        controller: _reasonCtrl,
        autofocus: true,
        maxLines: 2,
        decoration: InputDecoration(
          labelText: S.tn(context, 'Alasan (opsional)'),
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
          child: Text(S.tn(context, 'Batalkan PO')),
        ),
      ],
    );
  }
}
