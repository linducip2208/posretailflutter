import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/s.dart';
import '../../models/stock_movement.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';

/// Riwayat mutasi stok — read-only (ditulis server dari
/// penjualan/pembelian/transfer/opname).
///
/// Sumber: `GET /stock-movements?outlet_id=&product_id=&type=in|out`
/// `&page=&per_page=`.
class StockMovementScreen extends StatefulWidget {
  final int? productId;

  const StockMovementScreen({super.key, this.productId});

  @override
  State<StockMovementScreen> createState() => _StockMovementScreenState();
}

class _StockMovementScreenState extends State<StockMovementScreen> {
  final ApiService _api = ApiService();
  final ScrollController _scrollCtrl = ScrollController();

  List<StockMovement> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;

  /// Filter type persis validasi backend: `in` / `out` / semua.
  String _type = 'all';

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

  void _onScroll() {
    if (!_scrollCtrl.hasClients || _loadingMore || _page >= _lastPage) return;
    final position = _scrollCtrl.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Map<String, String?> _query(String page) {
    return {
      'outlet_id': context.read<AuthProvider>().currentOutletId?.toString(),
      'product_id': widget.productId?.toString(),
      // Backend hanya menerima type=in|out; 'all' berarti tanpa filter.
      'type': _type == 'all' ? null : _type,
      'page': page,
      'per_page': '50',
    };
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.get('/stock-movements', query: _query('1'));
      final data = response is Map ? response['data'] : null;
      final meta = response is Map ? response['meta'] : null;
      if (!mounted) return;
      setState(() {
        _items = data is List
            ? data
                  .whereType<Map<String, dynamic>>()
                  .map(StockMovement.fromJson)
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
        _error = S.tn(context, 'Gagal memuat mutasi stok.');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_page >= _lastPage) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final response = await _api.get(
        '/stock-movements',
        query: _query('$nextPage'),
      );
      final data = response is Map ? response['data'] : null;
      if (!mounted) return;
      setState(() {
        if (data is List) {
          _items = [
            ..._items,
            ...data
                .whereType<Map<String, dynamic>>()
                .map(StockMovement.fromJson),
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

  void _resetFilter() {
    setState(() {
      _type = 'all';
    });
    _refresh();
  }

  bool get _hasFilter => _type != 'all';

  static String _fmtQty(double v) =>
      v == v.toInt() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Mutasi Stok')),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Muat ulang'),
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: _type,
            isDense: true,
            decoration: InputDecoration(
              labelText: S.t(context, 'Jenis mutasi'),
            ),
            items: [
              DropdownMenuItem(
                value: 'all',
                child: Text(S.t(context, 'Semua')),
              ),
              for (final t in StockMovement.types)
                DropdownMenuItem(
                  value: t,
                  child: Text(
                    StockMovement(
                      id: 0,
                      productId: 0,
                      type: t,
                    ).labelId,
                  ),
                ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _type = v);
              _refresh();
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_hasFilter)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _resetFilter,
                child: Text(S.t(context, 'Reset')),
              ),
            ),
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
        title: S.t(context, 'Tidak ada mutasi stok'),
        message: S.t(
          context,
          'Belum ada pergerakan stok pada outlet dan periode ini.',
        ),
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
                        '$_total ${S.t(context, 'mutasi')}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
            );
          }
          return _movementCard(_items[i]);
        },
      ),
    );
  }

  Widget _movementCard(StockMovement m) {
    final delta = m.delta;
    final positive = delta >= 0;
    final diffText =
        '${positive ? '+' : ''}${_fmtQty(delta)}';
    final rangeText = m.qtyBefore != null && m.qtyAfter != null
        ? '${_fmtQty(m.qtyBefore!)} → ${_fmtQty(m.qtyAfter!)}'
        : '-';

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        title: Text(
          (m.productName == null || m.productName!.isEmpty)
              ? 'Produk #${m.productId}'
              : m.productName!,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            StatusBadge(m.labelId, tone: _toneForType(m.type)),
            const SizedBox(height: 2),
            Text(
              '${Fmt.dateTime(m.createdAt)} · $rangeText',
              style: const TextStyle(fontSize: 11.5),
            ),
          ],
        ),
        trailing: Text(
          diffText,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: positive ? AppColors.success : AppColors.error,
          ),
        ),
      ),
    );
  }

  BadgeTone _toneForType(String type) {
    switch (type) {
      case 'out':
      case 'sale':
      case 'transfer_out':
        return BadgeTone.warning;
      case 'in':
      case 'purchase':
      case 'transfer_in':
        return BadgeTone.success;
      case 'opname':
        return BadgeTone.info;
      case 'adjustment':
      default:
        return BadgeTone.neutral;
    }
  }
}
