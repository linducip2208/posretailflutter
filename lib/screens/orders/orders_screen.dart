import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/s.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';
import 'order_detail_screen.dart';

/// Riwayat transaksi dengan pencarian lokal + filter periode.
/// Sumber data: `/orders/history` (otomatis discope ke outlet aktif).
class OrdersScreen extends StatefulWidget {
  /// Bila diisi (mis. dari struk POS), detail langsung dibuka sekali.
  final int? initialOrderId;

  const OrdersScreen({super.key, this.initialOrderId});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();

  List<Order> _orders = [];
  bool _loading = true;
  String? _error;
  int _periodIndex = 0;
  DateTimeRange? _customRange;
  bool _openedInitial = false;

  static const _maxRangeDays = 93;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _openInitialIfAny();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openInitialIfAny() {
    if (_openedInitial || widget.initialOrderId == null) return;
    _openedInitial = true;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderDetailScreen(orderId: widget.initialOrderId!),
      ),
    );
  }

  DateTimeRange _rangeFor(int index) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (index) {
      case 1:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 6)),
          end: today,
        );
      case 2:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 29)),
          end: today,
        );
      case 3:
        final custom = _customRange;
        if (custom != null) return custom;
        return DateTimeRange(start: today, end: today);
      case 0:
      default:
        return DateTimeRange(start: today, end: today);
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: _customRange,
      helpText: S.tn(context, 'Pilih rentang tanggal'),
      saveText: S.tn(context, 'Terapkan'),
    );
    if (picked == null) return;
    if (picked.end.difference(picked.start).inDays > _maxRangeDays) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Rentang tanggal maksimal 93 hari.'),
        type: SnackType.warning,
      );
      return;
    }
    setState(() {
      _customRange = picked;
      _periodIndex = 3;
    });
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final range = _rangeFor(_periodIndex);
    final outletId = context.read<AuthProvider>().currentOutletId;

    try {
      final response = await _api.get(
        '/orders/history',
        query: {
          'start_date': Fmt.dateForApi(range.start),
          'end_date': Fmt.dateForApi(range.end),
          'outlet_id': outletId?.toString(),
        },
      );
      final dynamic data = response is Map
          ? (response['data'] ?? response)
          : response;
      final list = data is List
          ? data.whereType<Map<String, dynamic>>().map(Order.fromJson).toList()
          : <Order>[];
      if (!mounted) return;
      setState(() {
        _orders = list;
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
        _error = S.tn(context, 'Gagal memuat riwayat transaksi.');
      });
    }
  }

  List<Order> get _filteredOrders {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _orders;
    return _orders.where((o) {
      final number = o.orderNumber.toLowerCase();
      final customer = (o.customerName ?? '').toLowerCase();
      final queue = (o.queueNumber ?? '').toLowerCase();
      return number.contains(query) ||
          customer.contains(query) ||
          queue.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Riwayat Transaksi')),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Muat ulang'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
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
                hintText: S.t(
                  context,
                  'Cari nomor, pelanggan, atau antrian...',
                ),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                _periodChip(0, S.t(context, 'Hari Ini')),
                _periodChip(1, S.t(context, '7 Hari')),
                _periodChip(2, S.t(context, '30 Hari')),
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    avatar: _periodIndex == 3
                        ? null
                        : const Icon(Icons.date_range, size: 16),
                    label: Text(
                      _periodIndex == 3 && _customRange != null
                          ? '${Fmt.dateForApi(_customRange!.start)} → ${Fmt.dateForApi(_customRange!.end)}'
                          : S.t(context, 'Kustom'),
                    ),
                    selected: _periodIndex == 3,
                    onSelected: (_) => _pickCustomRange(),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _periodChip(int index, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: _periodIndex == index,
        onSelected: (_) {
          setState(() => _periodIndex = index);
          _load();
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingSkeleton(items: 6, itemHeight: 64);
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    final orders = _filteredOrders;
    if (orders.isEmpty) {
      final searching = _searchCtrl.text.trim().isNotEmpty;
      return EmptyState(
        icon: searching ? Icons.search_off : Icons.receipt_long_outlined,
        title: searching
            ? S.t(context, 'Transaksi tidak ditemukan')
            : S.t(context, 'Belum ada transaksi'),
        message: searching
            ? S.t(context, 'Ubah kata kunci pencarian.')
            : S.t(context, 'Transaksi yang selesai akan tampil di sini.'),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        itemCount: orders.length,
        itemBuilder: (_, i) => _orderCard(orders[i]),
      ),
    );
  }

  Widget _orderCard(Order order) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                OrderDetailScreen(orderId: order.id, initialOrder: order),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            order.orderNumber,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (order.queueNumber != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          StatusBadge(
                            '${S.t(context, 'Antrian')} ${order.queueNumber}',
                            tone: BadgeTone.info,
                          ),
                        ],
                      ],
                    ),
                  ),
                  StatusBadge(
                    orderStatusLabel(context, order.orderStatus),
                    tone: toneForOrderStatus(order.orderStatus),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${S.t(context, 'Customer')}: '
                      '${(order.customerName?.isNotEmpty ?? false) ? order.customerName : S.t(context, 'Walk-in')}',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  StatusBadge(
                    paymentStatusLabel(context, order.paymentStatus),
                    tone: toneForPaymentStatus(order.paymentStatus),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      '${order.items?.length ?? 0} ${S.t(context, 'item')} · ${Fmt.dateTime(order.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    Fmt.rupiah(order.totalAmount),
                    style: TextStyle(
                      fontSize: 15,
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
    );
  }
}

/// Label status pesanan dalam Bahasa Indonesia.
String orderStatusLabel(BuildContext context, String status) {
  switch (status) {
    case 'completed':
      return S.t(context, 'Selesai');
    case 'pending':
      return S.t(context, 'Menunggu');
    case 'processing':
      return S.t(context, 'Diproses');
    case 'cancelled':
      return S.t(context, 'Dibatalkan');
    default:
      return status;
  }
}

/// Label status pembayaran dalam Bahasa Indonesia.
String paymentStatusLabel(BuildContext context, String status) {
  switch (status) {
    case 'paid':
      return S.t(context, 'Lunas');
    case 'partial':
      return S.t(context, 'Sebagian');
    case 'pending':
      return S.t(context, 'Belum Bayar');
    case 'refunded':
      return S.t(context, 'Dikembalikan');
    default:
      return status;
  }
}
