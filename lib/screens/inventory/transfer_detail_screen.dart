import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../models/inventory_ops.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/confirmation_dialog.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';

/// Detail transfer stok: info rute, item, dan aksi workflow
/// draft → kirim → terima sesuai status.
class TransferDetailScreen extends StatefulWidget {
  final int transferId;
  final StockTransfer? initial;

  const TransferDetailScreen({
    super.key,
    required this.transferId,
    this.initial,
  });

  @override
  State<TransferDetailScreen> createState() => _TransferDetailScreenState();
}

class _TransferDetailScreenState extends State<TransferDetailScreen> {
  final ApiService _api = ApiService();

  StockTransfer? _transfer;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _transfer = widget.initial;
    if (widget.initial != null) _loading = false;
    _load();
  }

  Future<void> _load() async {
    if (_transfer == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await _api.get('/stock-transfers/${widget.transferId}');
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (data is Map<String, dynamic>) {
          _transfer = StockTransfer.fromJson(data);
          _error = null;
        } else {
          _error = S.tn(context, 'Transfer tidak ditemukan.');
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
        _error = S.tn(context, 'Gagal memuat detail transfer.');
      });
    }
  }

  Future<void> _doAction(String endpoint, String successMessage) async {
    setState(() => _busy = true);
    try {
      await _api.post('/stock-transfers/${widget.transferId}/$endpoint');
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

  Future<void> _confirmAndShip() async {
    final ok = await confirmDialog(
      context,
      title: S.tn(context, 'Kirim transfer?'),
      message: S.tn(
        context,
        'Stok outlet asal akan dikurangi dan status menjadi Dikirim.',
      ),
      confirmLabel: S.tn(context, 'Kirim'),
    );
    if (!ok || !mounted) return;
    await _doAction(
      'ship',
      S.tn(context, 'Transfer dikirim ke outlet tujuan.'),
    );
  }

  Future<void> _confirmAndReceive() async {
    final ok = await confirmDialog(
      context,
      title: S.tn(context, 'Terima transfer?'),
      message: S.tn(
        context,
        'Stok outlet tujuan akan bertambah sesuai item transfer.',
      ),
      confirmLabel: S.tn(context, 'Terima'),
    );
    if (!ok || !mounted) return;
    await _doAction(
      'receive',
      S.tn(context, 'Transfer diterima. Stok bertambah.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _transfer;
    return Scaffold(
      appBar: AppBar(
        title: Text(t?.displayTitle ?? S.t(context, 'Detail Transfer')),
      ),
      body: _buildBody(t),
      bottomNavigationBar: t == null ? null : _buildActions(t),
    );
  }

  Widget _buildBody(StockTransfer? t) {
    if (_loading && t == null) {
      return const LoadingSkeleton(items: 5, itemHeight: 64);
    }
    if (t == null) {
      return ErrorState(
        message: _error ?? S.tn(context, 'Transfer tidak ditemukan.'),
        icon: Icons.swap_horiz_outlined,
        onRetry: _load,
      );
    }
    final items = t.items ?? const <TransferItem>[];
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
                          t.displayTitle,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontSize: 16),
                        ),
                      ),
                      StatusBadge(
                        transferStatusLabel(t.status),
                        tone: toneForTransferStatus(t.status),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _infoRow(S.t(context, 'Rute'), t.routeLabel()),
                  _infoRow(
                    S.t(context, 'Tanggal'),
                    Fmt.dateTime(t.createdAt),
                  ),
                  if (t.note != null && t.note!.isNotEmpty)
                    _infoRow(S.t(context, 'Catatan'), t.note!),
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
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (items.isEmpty)
                    Text(
                      S.t(context, 'Detail item tidak tersedia.'),
                      style: Theme.of(context).textTheme.bodySmall,
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                  const Divider(height: AppSpacing.xl),
                  Row(
                    children: [
                      Expanded(child: Text(S.t(context, 'Total qty'))),
                      Text(
                        '${t.totalQty}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
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

  Widget? _buildActions(StockTransfer t) {
    List<Widget> buttons = [];
    if (t.status == 'draft') {
      buttons.add(
        Expanded(
          child: FilledButton.icon(
            onPressed: _busy ? null : _confirmAndShip,
            icon: const Icon(Icons.local_shipping_outlined, size: 18),
            label: Text(
              S.t(context, 'Kirim'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      );
    } else if (t.status == 'dikirim') {
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
