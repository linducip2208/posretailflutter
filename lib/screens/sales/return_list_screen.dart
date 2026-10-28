import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/s.dart';
import '../../models/sales_ops.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';
import 'return_detail_screen.dart';

/// Daftar retur penjualan: filter status, pagination,
/// buat retur baru, navigasi ke detail (approve/reject).
class ReturnListScreen extends StatefulWidget {
  /// Outlet eksplisit agar layar testable tanpa [AuthProvider].
  final int? outletId;

  const ReturnListScreen({super.key, this.outletId});

  @override
  State<ReturnListScreen> createState() => _ReturnListScreenState();
}

class _ReturnListScreenState extends State<ReturnListScreen> {
  static const _filters = ['semua', 'pending', 'completed', 'rejected'];

  final ApiService _api = ApiService();
  final ScrollController _scrollCtrl = ScrollController();

  List<ReturnOrder> _returns = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String _statusFilter = 'semua';
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  int? _resolveOutletId() {
    if (widget.outletId != null) return widget.outletId;
    try {
      return context.read<AuthProvider>().currentOutletId;
    } catch (_) {
      return null;
    }
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients || _loadingMore || _page >= _lastPage) return;
    final p = _scrollCtrl.position;
    if (p.pixels >= p.maxScrollExtent - 300) _loadMore();
  }

  Future<void> _refresh() async {
    final outletId = _resolveOutletId();
    if (outletId == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = S.tn(context, 'Pilih outlet dulu.');
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.get(
        '/returns',
        query: {
          'outlet_id': '$outletId',
          'per_page': '50',
          'page': '1',
          if (_statusFilter != 'semua') 'status': _statusFilter,
        },
      );
      final data = response is Map ? response['data'] : null;
      final meta = response is Map ? response['meta'] : null;
      if (!mounted) return;
      setState(() {
        _returns = data is List
            ? data
                  .whereType<Map<String, dynamic>>()
                  .map(ReturnOrder.fromJson)
                  .toList()
            : [];
        _page = 1;
        _lastPage = meta is Map ? (meta['last_page'] as num?)?.toInt() ?? 1 : 1;
        _total = meta is Map ? (meta['total'] as num?)?.toInt() ?? 0 : 0;
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
        _error = S.tn(context, 'Gagal memuat daftar retur.');
      });
    }
  }

  Future<void> _loadMore() async {
    final outletId = _resolveOutletId();
    if (outletId == null || _page >= _lastPage) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final response = await _api.get(
        '/returns',
        query: {
          'outlet_id': '$outletId',
          'per_page': '50',
          'page': '$next',
          if (_statusFilter != 'semua') 'status': _statusFilter,
        },
      );
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      setState(() {
        if (data is List) {
          _returns = [
            ..._returns,
            ...data.whereType<Map<String, dynamic>>().map(ReturnOrder.fromJson),
          ];
        }
        _page = next;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _openCreateDialog() async {
    final outletId = _resolveOutletId();
    if (outletId == null) {
      showAppSnackbar(
        context,
        S.tn(context, 'Pilih outlet dulu.'),
        type: SnackType.warning,
      );
      return;
    }
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _ReturnFormDialog(outletId: outletId),
    );
    if (created == true && mounted) {
      showAppSnackbar(
        context,
        S.tn(context, 'Retur tersimpan di server.'),
        type: SnackType.success,
      );
      await _refresh();
    }
  }

  Future<void> _openDetail(ReturnOrder r) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReturnDetailScreen(returnId: r.id, initial: r),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Retur Penjualan')),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Muat ulang'),
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateDialog,
        icon: const Icon(Icons.add),
        label: Text(S.t(context, 'Buat Retur')),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: _filters.map((f) {
                final selected = _statusFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    label: Text(
                      f == 'semua'
                          ? S.t(context, 'Semua')
                          : returnStatusLabel(f),
                    ),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _statusFilter = f);
                      _refresh();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingSkeleton(items: 6, itemHeight: 64);
    if (_error != null) return ErrorState(message: _error!, onRetry: _refresh);
    if (_returns.isEmpty) {
      return EmptyState(
        icon: Icons.assignment_return_outlined,
        title: S.t(context, 'Tidak ada retur'),
        message: S.t(context, 'Buat retur baru dengan tombol di bawah.'),
        actionLabel: S.t(context, 'Buat Retur'),
        onAction: _openCreateDialog,
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        itemCount: _returns.length + 1,
        itemBuilder: (_, i) {
          if (i == _returns.length) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : Text(
                        '$_total retur',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
            );
          }
          return _returCard(_returns[i]);
        },
      ),
    );
  }

  Widget _returCard(ReturnOrder r) {
    final itemCount = r.items?.fold<int>(0, (s, e) => s + e.qty) ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.assignment_return_outlined, size: 20),
        ),
        title: Text(
          r.displayNumber,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (r.orderNumber != null && r.orderNumber!.isNotEmpty)
              r.orderNumber!
            else if (r.orderId != null)
              'Order #${r.orderId}',
            if (itemCount > 0) '$itemCount item',
            Fmt.date(r.createdAt),
          ].join(' · '),
          style: const TextStyle(fontSize: 11.5),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: StatusBadge(
          returnStatusLabel(r.status),
          tone: toneForReturnStatus(r.status),
        ),
        onTap: () => _openDetail(r),
      ),
    );
  }
}

/// Satu baris item retur di form.
class _DraftReturnItem {
  int productId;
  int qty;

  _DraftReturnItem({required this.productId, required this.qty});
}

/// Dialog buat retur: input order_id + item product_id/qty + reason,
/// POST /returns.
class _ReturnFormDialog extends StatefulWidget {
  final int outletId;

  const _ReturnFormDialog({required this.outletId});

  @override
  State<_ReturnFormDialog> createState() => _ReturnFormDialogState();
}

class _ReturnFormDialogState extends State<_ReturnFormDialog> {
  final ApiService _api = ApiService();
  final _orderCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final List<_DraftReturnItem> _items = [
    _DraftReturnItem(productId: 0, qty: 1),
  ];
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _orderCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final orderId = int.tryParse(_orderCtrl.text.trim());
    if (orderId == null || orderId <= 0) {
      setState(() => _error = S.tn(context, 'ID order wajib diisi.'));
      return;
    }
    final items = _items
        .where((e) => e.productId > 0 && e.qty > 0)
        // Backend: items.*.quantity (bukan qty).
        .map((e) => {'product_id': e.productId, 'quantity': e.qty})
        .toList();
    if (items.isEmpty) {
      setState(
        () => _error = S.tn(context, 'Tambahkan minimal satu item valid.'),
      );
      return;
    }
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = S.tn(context, 'Alasan wajib diisi.'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _api.post(
        '/returns',
        body: {'order_id': orderId, 'items': items, 'reason': reason},
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
        _error = S.tn(context, 'Gagal menyimpan retur.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.t(context, 'Buat Retur')),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                controller: _orderCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: S.t(context, 'ID Order *'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                S.t(context, 'Item retur'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ..._items.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          key: ValueKey('return_product_$idx'),
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: S.t(context, 'ID Produk'),
                            isDense: true,
                          ),
                          controller: TextEditingController(
                            text: item.productId == 0
                                ? ''
                                : '${item.productId}',
                          ),
                          onChanged: (v) =>
                              item.productId = int.tryParse(v.trim()) ?? 0,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          key: ValueKey('return_qty_$idx'),
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: S.t(context, 'Qty'),
                            isDense: true,
                          ),
                          controller: TextEditingController(
                            text: '${item.qty}',
                          ),
                          onChanged: (v) =>
                              item.qty = int.tryParse(v.trim()) ?? 0,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: _items.length <= 1
                            ? null
                            : () => setState(() => _items.removeAt(idx)),
                      ),
                    ],
                  ),
                );
              }),
              TextButton.icon(
                onPressed: () => setState(
                  () => _items.add(_DraftReturnItem(productId: 0, qty: 1)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: Text(S.t(context, 'Tambah item')),
              ),
              TextField(
                controller: _reasonCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: S.t(context, 'Alasan *'),
                ),
              ),
            ],
          ),
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
