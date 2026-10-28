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
import 'opname_detail_screen.dart';

/// Daftar sesi stock opname: filter status, pagination,
/// buka sesi baru, dan navigasi ke detail penghitungan.
class OpnameListScreen extends StatefulWidget {
  /// Outlet eksplisit agar layar testable tanpa [AuthProvider].
  final int? outletId;

  const OpnameListScreen({super.key, this.outletId});

  @override
  State<OpnameListScreen> createState() => _OpnameListScreenState();
}

class _OpnameListScreenState extends State<OpnameListScreen> {
  /// Status persis backend live: `pending` → `completed`.
  static const _filters = ['semua', 'pending', 'completed'];

  final ApiService _api = ApiService();
  final ScrollController _scrollCtrl = ScrollController();

  List<StockOpname> _sessions = [];
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
        '/stock-opnames',
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
        _sessions = data is List
            ? data
                  .whereType<Map<String, dynamic>>()
                  .map(StockOpname.fromJson)
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
        _error = S.tn(context, 'Gagal memuat sesi opname.');
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
        '/stock-opnames',
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
          _sessions = [
            ..._sessions,
            ...data.whereType<Map<String, dynamic>>().map(StockOpname.fromJson),
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
      builder: (_) => _OpnameCreateDialog(outletId: outletId),
    );
    if (created == true && mounted) {
      showAppSnackbar(
        context,
        S.tn(context, 'Sesi opname dibuka.'),
        type: SnackType.success,
      );
      await _refresh();
    }
  }

  Future<void> _openDetail(StockOpname session) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OpnameDetailScreen(
          opnameId: session.id,
          initial: session,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Stock Opname')),
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
        label: Text(S.t(context, 'Buka Sesi')),
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
                          : opnameStatusLabel(f),
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
    if (_sessions.isEmpty) {
      return EmptyState(
        icon: Icons.fact_check_outlined,
        title: S.t(context, 'Tidak ada sesi opname'),
        message: S.t(context, 'Buka sesi baru untuk mulai menghitung stok.'),
        actionLabel: S.t(context, 'Buka Sesi'),
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
        itemCount: _sessions.length + 1,
        itemBuilder: (_, i) {
          if (i == _sessions.length) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : Text(
                        '$_total ${S.t(context, 'sesi')}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
            );
          }
          return _sessionCard(_sessions[i]);
        },
      ),
    );
  }

  Widget _sessionCard(StockOpname s) {
    final itemCount = s.items?.length ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.fact_check_outlined, size: 20),
        ),
        title: Text(
          s.displayTitle,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (itemCount > 0) '$itemCount item',
            Fmt.date(s.createdAt),
          ].join(' · '),
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: StatusBadge(
          opnameStatusLabel(s.status),
          tone: toneForOpnameStatus(s.status),
        ),
        onTap: () => _openDetail(s),
      ),
    );
  }
}

/// Dialog buka sesi: POST /stock-opnames
/// `{outlet_id, notes?, items: [{product_id, actual_stock}]}`.
///
/// Backend mewajibkan minimal 1 item, jadi dialog ini sekaligus
/// mengumpulkan hitung fisik awal.
class _OpnameCreateDialog extends StatefulWidget {
  final int outletId;

  const _OpnameCreateDialog({required this.outletId});

  @override
  State<_OpnameCreateDialog> createState() => _OpnameCreateDialogState();
}

class _DraftOpnameItem {
  final int productId;
  final String productName;
  final int actualStock;

  _DraftOpnameItem({
    required this.productId,
    required this.productName,
    required this.actualStock,
  });
}

class _OpnameCreateDialogState extends State<_OpnameCreateDialog> {
  final ApiService _api = ApiService();
  final _noteCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _foundProducts = [];
  bool _searching = false;
  final List<_DraftOpnameItem> _items = [];
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _noteCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String _) {
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
    final rawId = raw['id'];
    final id = rawId is int
        ? rawId
        : rawId is num
            ? rawId.toInt()
            : int.tryParse(rawId?.toString() ?? '') ?? 0;
    final name = raw['name']?.toString() ?? 'Produk #$id';
    final qty = await showDialog<int>(
      context: context,
      builder: (_) => _ActualQtyDialog(productName: name),
    );
    if (qty == null || !mounted) return;
    setState(() {
      final existing = _items.indexWhere((e) => e.productId == id);
      final item = _DraftOpnameItem(
        productId: id,
        productName: name,
        actualStock: qty,
      );
      if (existing >= 0) {
        _items[existing] = item;
      } else {
        _items.add(item);
      }
      _searchCtrl.clear();
      _foundProducts = [];
    });
  }

  Future<void> _submit() async {
    if (_items.isEmpty) {
      setState(
        () => _error = S.tn(context, 'Tambahkan minimal satu item hitung fisik.'),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _api.post(
        '/stock-opnames',
        body: {
          'outlet_id': widget.outletId,
          if (_noteCtrl.text.trim().isNotEmpty)
            'notes': _noteCtrl.text.trim(),
          'items': _items
              .map(
                (e) => {
                  'product_id': e.productId,
                  'actual_stock': e.actualStock,
                },
              )
              .toList(),
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
        _error = S.tn(context, 'Gagal membuka sesi opname.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.t(context, 'Buka Sesi Opname')),
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
              Text(
                S.t(context, 'Sesi baru menyimpan stok sistem sebagai acuan dan hitung fisik awal.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  labelText: S.t(context, 'Cari produk'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                ),
                onChanged: _onSearchChanged,
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
                          '${S.t(context, 'Fisik')}: ${e.actualStock}',
                          style: const TextStyle(fontSize: 12),
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
              : Text(S.t(context, 'Buka')),
        ),
      ],
    );
  }
}

/// Dialog stok fisik (integer, sesuai validasi backend `actual_stock`).
class _ActualQtyDialog extends StatefulWidget {
  final String productName;

  const _ActualQtyDialog({required this.productName});

  @override
  State<_ActualQtyDialog> createState() => _ActualQtyDialogState();
}

class _ActualQtyDialogState extends State<_ActualQtyDialog> {
  final _qtyCtrl = TextEditingController(text: '0');

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
        decoration: InputDecoration(labelText: S.t(context, 'Stok fisik')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(S.t(context, 'Batal')),
        ),
        FilledButton(
          onPressed: () {
            final qty = int.tryParse(_qtyCtrl.text.trim()) ?? -1;
            if (qty < 0) return;
            Navigator.pop(context, qty);
          },
          child: Text(S.t(context, 'Tambah')),
        ),
      ],
    );
  }
}
