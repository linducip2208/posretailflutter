import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/s.dart';
import '../../models/purchase_order.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';
import 'purchase_order_detail_screen.dart';

/// Daftar purchase order: filter status, pencarian lokal, pagination,
/// buat PO baru, dan navigasi ke detail.
class PurchaseOrderListScreen extends StatefulWidget {
  /// Outlet eksplisit agar layar testable tanpa [AuthProvider].
  /// Bila null, outlet diambil dari AuthProvider.
  final int? outletId;

  const PurchaseOrderListScreen({super.key, this.outletId});

  @override
  State<PurchaseOrderListScreen> createState() => _PurchaseOrderListScreenState();
}

class _PurchaseOrderListScreenState extends State<PurchaseOrderListScreen> {
  /// Kunci status persis backend (`draft`/`ordered`/`received`/`cancelled`);
  /// label Indonesia dirender via [poStatusLabel].
  static const _filters = [
    'semua',
    'draft',
    'ordered',
    'received',
    'cancelled',
  ];

  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _debounce;

  List<PurchaseOrder> _orders = [];
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
    _debounce?.cancel();
    _searchCtrl.dispose();
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
    if (position.pixels >= position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _refresh();
    });
  }

  /// Item yang lolos filter status + pencarian lokal (nomor/supplier).
  /// Pencarian nomor PO juga dikirim ke server (`search` → `po_number`);
  /// filter nama supplier hanya bisa lokal karena backend tidak mendukungnya.
  List<PurchaseOrder> get _visible {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _orders.where((o) {
      if (_statusFilter != 'semua' && o.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      return o.displayNumber.toLowerCase().contains(q) ||
          (o.supplierName?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Map<String, String?> _listQuery(String outletId, String page) => {
    'outlet_id': outletId,
    'per_page': '50',
    'page': page,
    if (_statusFilter != 'semua') 'status': _statusFilter,
    // Backend hanya mencari di `po_number`; kirim apa adanya, mis.
    // "PO-2026" — filter nama supplier tetap ditangani lokal di [_visible].
    if (_searchCtrl.text.trim().isNotEmpty) 'search': _searchCtrl.text.trim(),
  };

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
        '/purchase-orders',
        query: _listQuery('$outletId', '1'),
      );
      final data = response is Map ? response['data'] : null;
      final meta = response is Map ? response['meta'] : null;
      if (!mounted) return;
      setState(() {
        _orders = data is List
            ? data
                  .whereType<Map<String, dynamic>>()
                  .map(PurchaseOrder.fromJson)
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
        _error = S.tn(context, 'Gagal memuat purchase order.');
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
        '/purchase-orders',
        query: _listQuery('$outletId', '$nextPage'),
      );
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      setState(() {
        if (data is List) {
          _orders = [
            ..._orders,
            ...data.whereType<Map<String, dynamic>>().map(PurchaseOrder.fromJson),
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
      builder: (_) => _PurchaseOrderFormDialog(outletId: outletId),
    );
    if (created == true && mounted) {
      showAppSnackbar(
        context,
        S.tn(context, 'Purchase order tersimpan di server.'),
        type: SnackType.success,
      );
      await _refresh();
    }
  }

  Future<void> _openDetail(PurchaseOrder order) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseOrderDetailScreen(
          poId: order.id,
          initialOrder: order,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Purchase Order')),
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
        label: Text(S.t(context, 'Buat PO')),
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
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: S.t(context, 'Cari nomor atau supplier...'),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _refresh();
                        },
                      ),
              ),
              onChanged: _onSearchChanged,
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
                          : poStatusLabel(f),
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
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingSkeleton(items: 6, itemHeight: 64);
    if (_error != null) return ErrorState(message: _error!, onRetry: _refresh);
    final visible = _visible;
    if (visible.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: S.t(context, 'Tidak ada purchase order'),
        message: S.t(
          context,
          'Buat PO baru dengan tombol di bawah.',
        ),
        actionLabel: S.t(context, 'Buat PO'),
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
        itemCount: visible.length + 1,
        itemBuilder: (_, i) {
          if (i == visible.length) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : Text(
                        '$_total PO',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
            );
          }
          return _poCard(visible[i]);
        },
      ),
    );
  }

  Widget _poCard(PurchaseOrder order) {
    final itemCount = order.items?.fold<int>(0, (s, e) => s + e.qty) ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primaryContainer,
          child: const Icon(Icons.inventory_2_outlined, size: 20),
        ),
        title: Text(
          order.displayNumber,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (order.supplierName != null && order.supplierName!.isNotEmpty)
              order.supplierName!,
            if (itemCount > 0) '$itemCount item',
            Fmt.date(order.createdAt),
          ].join(' · '),
          style: const TextStyle(fontSize: 11.5),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            StatusBadge(
              poStatusLabel(order.status),
              tone: toneForPoStatus(order.status),
            ),
            const SizedBox(height: 2),
            Text(
              Fmt.rupiah(order.totalCost),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        onTap: () => _openDetail(order),
      ),
    );
  }
}

/// Pilihan supplier dari GET /suppliers.
class _SupplierOption {
  final int id;
  final String name;

  _SupplierOption({required this.id, required this.name});
}

/// Satu baris item di form: produk + qty + harga beli.
class _DraftItem {
  final int productId;
  final String productName;
  int qty;
  double costPrice;

  _DraftItem({
    required this.productId,
    required this.productName,
    required this.qty,
    required this.costPrice,
  });

  double get subtotal => qty * costPrice;
}

/// Dialog buat PO: pilih supplier, tambah item (cari produk + qty +
/// harga beli), tampilkan total estimasi, POST /purchase-orders.
class _PurchaseOrderFormDialog extends StatefulWidget {
  final int outletId;

  const _PurchaseOrderFormDialog({required this.outletId});

  @override
  State<_PurchaseOrderFormDialog> createState() =>
      _PurchaseOrderFormDialogState();
}

class _PurchaseOrderFormDialogState extends State<_PurchaseOrderFormDialog> {
  final ApiService _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  Timer? _debounce;

  List<_SupplierOption> _suppliers = [];
  bool _loadingSuppliers = true;
  int? _supplierId;

  List<Map<String, dynamic>> _foundProducts = [];
  bool _searching = false;

  final List<_DraftItem> _items = [];
  bool _submitting = false;
  String? _error;

  double get _estimatedTotal =>
      _items.fold<double>(0, (s, e) => s + e.subtotal);

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    try {
      final response = await _api.get('/suppliers');
      final data = response is Map ? response['data'] : response;
      if (!mounted) return;
      setState(() {
        _suppliers = data is List
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
                return _SupplierOption(
                  id: id,
                  name: (m['name']?.toString() ?? '').isEmpty
                      ? 'Supplier #$id'
                      : m['name'].toString(),
                );
              }).toList()
            : [];
        _loadingSuppliers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSuppliers = false);
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
    double price = 0;
    final rawPrice = raw['selling_price'] ?? raw['cost_price'];
    if (rawPrice is num) {
      price = rawPrice.toDouble();
    } else {
      price = double.tryParse(rawPrice?.toString() ?? '') ?? 0;
    }
    final added = await showDialog<_DraftItem>(
      context: context,
      builder: (_) => _PoItemQtyDialog(productName: name, costPrice: price),
    );
    if (added == null || !mounted) return;
    setState(() {
      final existing = _items.indexWhere((e) => e.productId == id);
      if (existing >= 0) {
        _items[existing].qty += added.qty;
        _items[existing].costPrice = added.costPrice;
      } else {
        _items.add(
          _DraftItem(
            productId: id,
            productName: name,
            qty: added.qty,
            costPrice: added.costPrice,
          ),
        );
      }
      _searchCtrl.clear();
      _foundProducts = [];
    });
  }

  Future<void> _submit() async {
    if (_supplierId == null) {
      setState(() => _error = S.tn(context, 'Pilih supplier dulu.'));
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
        '/purchase-orders',
        body: {
          'supplier_id': _supplierId,
          'outlet_id': widget.outletId,
          // Kontrak backend: `quantity` / `unit_price` / `notes`.
          'items': _items
              .map(
                (e) => {
                  'product_id': e.productId,
                  'quantity': e.qty,
                  'unit_price': e.costPrice,
                },
              )
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
        _error = S.tn(context, 'Gagal menyimpan purchase order.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.t(context, 'Buat Purchase Order')),
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
              if (_loadingSuppliers)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                DropdownButtonFormField<int>(
                  initialValue: _supplierId,
                  decoration: InputDecoration(
                    labelText: S.t(context, 'Supplier'),
                  ),
                  items: _suppliers
                      .map(
                        (s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(s.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _supplierId = v),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.productName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${e.qty} × ${Fmt.rupiah(e.costPrice)}',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          Fmt.rupiah(e.subtotal),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () =>
                              setState(() => _items.remove(e)),
                        ),
                      ],
                    ),
                  ),
                ),
              const Divider(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(child: Text(S.t(context, 'Estimasi total'))),
                  Text(
                    Fmt.rupiah(_estimatedTotal),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
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

/// Dialog qty + harga beli untuk satu produk yang ditambahkan ke PO.
class _PoItemQtyDialog extends StatefulWidget {
  final String productName;
  final double costPrice;

  const _PoItemQtyDialog({required this.productName, required this.costPrice});

  @override
  State<_PoItemQtyDialog> createState() => _PoItemQtyDialogState();
}

class _PoItemQtyDialogState extends State<_PoItemQtyDialog> {
  late final TextEditingController _qtyCtrl = TextEditingController(text: '1');
  late final TextEditingController _costCtrl = TextEditingController(
    text: widget.costPrice > 0 ? widget.costPrice.toInt().toString() : '',
  );

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.productName,
        style: const TextStyle(fontSize: 15),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _qtyCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: S.t(context, 'Qty')),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _costCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: S.t(context, 'Harga beli (Rp)'),
              prefixText: 'Rp ',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(S.t(context, 'Batal')),
        ),
        FilledButton(
          onPressed: () {
            final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
            final cost = Fmt.parseMoneyDigits(_costCtrl.text).toDouble();
            if (qty <= 0 || cost <= 0) return;
            Navigator.pop(
              context,
              _DraftItem(
                productId: 0,
                productName: widget.productName,
                qty: qty,
                costPrice: cost,
              ),
            );
          },
          child: Text(S.t(context, 'Tambah')),
        ),
      ],
    );
  }
}
