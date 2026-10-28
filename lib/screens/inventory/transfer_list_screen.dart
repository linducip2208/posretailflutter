import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/s.dart';
import '../../models/inventory_ops.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';
import 'transfer_detail_screen.dart';

/// Daftar transfer stok: filter status, buat transfer baru
/// (dari outlet aktif ke outlet tujuan), navigasi ke detail.
class TransferListScreen extends StatefulWidget {
  final int? outletId;

  const TransferListScreen({super.key, this.outletId});

  @override
  State<TransferListScreen> createState() => _TransferListScreenState();
}

class _TransferListScreenState extends State<TransferListScreen> {
  /// Status persis backend live: `draft` → `sent` → `received`.
  static const _filters = ['semua', 'draft', 'sent', 'received'];

  final ApiService _api = ApiService();
  final ScrollController _scrollCtrl = ScrollController();

  List<StockTransfer> _items = [];
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
    final position = _scrollCtrl.position;
    if (position.pixels >= position.maxScrollExtent - 300) _loadMore();
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
        '/stock-transfers',
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
        _items = data is List
            ? data
                  .whereType<Map<String, dynamic>>()
                  .map(StockTransfer.fromJson)
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
        _error = S.tn(context, 'Gagal memuat transfer stok.');
      });
    }
  }

  Future<void> _loadMore() async {
    final outletId = _resolveOutletId();
    if (outletId == null || _page >= _lastPage) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final response = await _api.get(
        '/stock-transfers',
        query: {
          'outlet_id': '$outletId',
          'per_page': '50',
          'page': '$nextPage',
          if (_statusFilter != 'semua') 'status': _statusFilter,
        },
      );
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      setState(() {
        if (data is List) {
          _items = [
            ..._items,
            ...data.whereType<Map<String, dynamic>>().map(StockTransfer.fromJson),
          ];
        }
        _page = nextPage;
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
      builder: (_) => _TransferFormDialog(fromOutletId: outletId),
    );
    if (created == true && mounted) {
      showAppSnackbar(
        context,
        S.tn(context, 'Transfer tersimpan di server.'),
        type: SnackType.success,
      );
      await _refresh();
    }
  }

  Future<void> _openDetail(StockTransfer t) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransferDetailScreen(
          transferId: t.id,
          initial: t,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Transfer Stok')),
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
        label: Text(S.t(context, 'Buat Transfer')),
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
                          : transferStatusLabel(f),
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
    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.swap_horiz_outlined,
        title: S.t(context, 'Tidak ada transfer stok'),
        message: S.t(context, 'Buat transfer baru dengan tombol di bawah.'),
        actionLabel: S.t(context, 'Buat Transfer'),
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
        itemCount: _items.length + 1,
        itemBuilder: (_, i) {
          if (i == _items.length) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : Text(
                        '$_total ${S.t(context, 'transfer')}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
            );
          }
          return _transferCard(_items[i]);
        },
      ),
    );
  }

  Widget _transferCard(StockTransfer t) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.swap_horiz_outlined, size: 20),
        ),
        title: Text(
          t.displayTitle,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${t.routeLabel()} · ${t.totalQty} item · ${Fmt.date(t.createdAt)}',
          style: const TextStyle(fontSize: 11.5),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: StatusBadge(
          transferStatusLabel(t.status),
          tone: toneForTransferStatus(t.status),
        ),
        onTap: () => _openDetail(t),
      ),
    );
  }
}

/// Pilihan outlet tujuan dari GET /outlets.
class _OutletOption {
  final int id;
  final String name;

  _OutletOption({required this.id, required this.name});
}

class _DraftTransferItem {
  final int productId;
  final String productName;
  int qty;

  _DraftTransferItem({
    required this.productId,
    required this.productName,
    required this.qty,
  });
}

/// Dialog buat transfer: pilih outlet tujuan, tambah item produk+qty,
/// POST /stock-transfers.
class _TransferFormDialog extends StatefulWidget {
  final int fromOutletId;

  const _TransferFormDialog({required this.fromOutletId});

  @override
  State<_TransferFormDialog> createState() => _TransferFormDialogState();
}

class _TransferFormDialogState extends State<_TransferFormDialog> {
  final ApiService _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  Timer? _debounce;

  List<_OutletOption> _outlets = [];
  bool _loadingOutlets = true;
  int? _toOutletId;

  List<Map<String, dynamic>> _foundProducts = [];
  bool _searching = false;
  final List<_DraftTransferItem> _items = [];
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOutlets();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOutlets() async {
    try {
      final response = await _api.get('/outlets');
      final data = response is Map ? response['data'] : response;
      if (!mounted) return;
      setState(() {
        _outlets = data is List
            ? data.whereType<Map<String, dynamic>>().map((m) {
                int id = 0;
                final rawId = m['id'];
                if (rawId is int) {
                  id = rawId;
                } else if (rawId is num) {
                  id = rawId.toInt();
                } else {
                  id = int.tryParse(rawId?.toString() ?? '') ?? 0;
                }
                return _OutletOption(
                  id: id,
                  name: (m['name']?.toString() ?? '').isEmpty
                      ? 'Outlet #$id'
                      : m['name'].toString(),
                );
              }).where((o) => o.id != widget.fromOutletId).toList()
            : [];
        _loadingOutlets = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingOutlets = false);
    }
  }

  void _onProductSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _searchProducts);
  }

  Future<void> _searchProducts() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _foundProducts = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final response = await _api.get('/products', query: {'search': q});
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      setState(() {
        _foundProducts = data is List
            ? data.whereType<Map<String, dynamic>>().toList()
            : [];
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  Future<void> _addProduct(Map<String, dynamic> raw) async {
    int id = 0;
    final rawId = raw['id'];
    if (rawId is int) {
      id = rawId;
    } else if (rawId is num) {
      id = rawId.toInt();
    } else {
      id = int.tryParse(rawId?.toString() ?? '') ?? 0;
    }
    final name = raw['name']?.toString() ?? 'Produk #$id';
    final qty = await showDialog<int>(
      context: context,
      builder: (_) => _TransferQtyDialog(productName: name),
    );
    if (qty == null || !mounted) return;
    setState(() {
      final existing = _items.indexWhere((e) => e.productId == id);
      if (existing >= 0) {
        _items[existing].qty += qty;
      } else {
        _items.add(
          _DraftTransferItem(productId: id, productName: name, qty: qty),
        );
      }
      _searchCtrl.clear();
      _foundProducts = [];
    });
  }

  Future<void> _submit() async {
    if (_toOutletId == null) {
      setState(() => _error = S.tn(context, 'Pilih outlet tujuan dulu.'));
      return;
    }
    if (_items.isEmpty) {
      setState(() => _error = S.tn(context, 'Tambahkan minimal satu item.'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _api.post(
        '/stock-transfers',
        body: {
          'from_outlet_id': widget.fromOutletId,
          'to_outlet_id': _toOutletId,
          'items': _items
              .map((e) => {'product_id': e.productId, 'quantity': e.qty})
              .toList(),
          if (_noteCtrl.text.trim().isNotEmpty)
            'notes': _noteCtrl.text.trim(),
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
        _error = S.tn(context, 'Gagal menyimpan transfer.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.t(context, 'Buat Transfer Stok')),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.errorSoft,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(_error!, style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (_loadingOutlets)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                DropdownButtonFormField<int>(
                  initialValue: _toOutletId,
                  decoration: InputDecoration(
                    labelText: S.t(context, 'Outlet tujuan'),
                  ),
                  items: _outlets
                      .map(
                        (o) => DropdownMenuItem(
                          value: o.id,
                          child: Text(o.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _toOutletId = v),
                ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  labelText: S.t(context, 'Cari produk untuk ditambah'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                ),
                onChanged: _onProductSearchChanged,
              ),
              if (_searching)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                ..._foundProducts.map(
                  (p) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      p['name']?.toString() ?? '-',
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: const Icon(Icons.add, size: 20),
                    onTap: () => _addProduct(p),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              if (_items.isEmpty)
                Text(
                  S.t(context, 'Belum ada item. Cari produk di atas.'),
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                ..._items.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.productName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '× ${e.qty}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => setState(() => _items.remove(e)),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _noteCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: S.t(context, 'Catatan (opsional)'),
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

class _TransferQtyDialog extends StatefulWidget {
  final String productName;

  const _TransferQtyDialog({required this.productName});

  @override
  State<_TransferQtyDialog> createState() => _TransferQtyDialogState();
}

class _TransferQtyDialogState extends State<_TransferQtyDialog> {
  final _qtyCtrl = TextEditingController(text: '1');

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.productName, style: const TextStyle(fontSize: 15)),
      content: TextField(
        controller: _qtyCtrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: S.t(context, 'Qty')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(S.t(context, 'Batal')),
        ),
        FilledButton(
          onPressed: () {
            final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
            if (qty <= 0) return;
            Navigator.pop(context, qty);
          },
          child: Text(S.t(context, 'Tambah')),
        ),
      ],
    );
  }
}
