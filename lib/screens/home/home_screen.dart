import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/s.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../services/api_service.dart';
import '../../services/offline_sync_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/metric_card.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/common/sync_status_card.dart';
import '../customers/customer_list_screen.dart';
import '../more/stock_alert_screen.dart';
import '../more/sync_screen.dart';
import '../orders/order_detail_screen.dart';
import '../orders/orders_screen.dart';
import '../outlet/outlet_selection_screen.dart';

/// Beranda: ringkasan operasional hari ini untuk outlet aktif.
///
/// Semua angka berasal dari endpoint nyata (`/orders/today`,
/// `/inventory/forecast`). Bila data belum tersedia, UI menampilkan
/// status kosong/error yang jujur — bukan angka contoh.
class HomeScreen extends StatefulWidget {
  /// Pindah ke tab lain pada shell utama (0=Beranda, 1=Transaksi, dst).
  final void Function(int tab)? onOpenTab;

  const HomeScreen({super.key, this.onOpenTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _api = ApiService();
  final OfflineSyncService _offline = OfflineSyncService();

  List<Map<String, dynamic>> _lowStock = [];
  bool _lowStockLoading = true;
  String? _lowStockError;

  bool _online = true;
  int _pendingCount = 0;
  int _failedCount = 0;
  bool _syncing = false;

  int? _lastOutletId;
  late final void Function(bool) _connectivityListener;

  @override
  void initState() {
    super.initState();
    _lastOutletId = context.read<AuthProvider>().currentOutletId;
    _online = _offline.isOnline;
    _connectivityListener = (online) {
      if (!mounted || !context.mounted) return;
      setState(() => _online = online);
      _refreshQueueCounts();
    };
    _offline.addListener(_connectivityListener);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _offline.removeListener(_connectivityListener);
    super.dispose();
  }

  Future<void> _load() async {
    final outletId = context.read<AuthProvider>().currentOutletId;
    setState(() {
      _lowStockLoading = true;
      _lowStockError = null;
    });
    await Future.wait([
      context.read<OrderProvider>().fetchTodayOrders(outletId: outletId),
      _loadLowStock(outletId),
      _refreshQueueCounts(),
    ]);
  }

  Future<void> _refreshQueueCounts() async {
    final pending = await _offline.getPendingCount();
    final failed = await _offline.getFailedCount();
    if (!mounted || !context.mounted) return;
    setState(() {
      _pendingCount = pending;
      _failedCount = failed;
      _online = _offline.isOnline;
    });
  }

  Future<void> _loadLowStock(int? outletId) async {
    try {
      final response = await _api.get(
        '/inventory/forecast',
        query: {'weeks': '4', 'outlet_id': outletId?.toString()},
      );
      final dynamic data = response is Map
          ? (response['data'] ?? response)
          : response;
      final low = data is Map && data['low_stock'] is List
          ? (data['low_stock'] as List)
                .whereType<Map<String, dynamic>>()
                .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _lowStock = low;
        _lowStockLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _lowStockLoading = false;
        _lowStockError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lowStockLoading = false;
        _lowStockError = S.tn(context, 'Gagal memuat info stok.');
      });
    }
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final sent = await _offline.syncPendingOrders(force: true);
    await _refreshQueueCounts();
    if (!mounted) return;
    setState(() => _syncing = false);
    showAppSnackbar(
      context,
      sent > 0
          ? '$sent ${S.tn(context, 'transaksi berhasil dikirim ke server.')}'
          : S.tn(context, 'Belum ada transaksi yang berhasil dikirim.'),
      type: sent > 0 ? SnackType.success : SnackType.warning,
    );
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final outletId = context.watch<AuthProvider>().currentOutletId;
    if (_lastOutletId != outletId) {
      _lastOutletId = outletId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }

    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final orders = context.watch<OrderProvider>().orders;

    double safeNum(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0;
    }

    final revenue = orders.fold<double>(
      0,
      (sum, o) => sum + safeNum(o.totalAmount),
    );
    final paidCount = orders.where((o) => o.paymentStatus == 'paid').length;
    final unpaidCount = orders.length - paidCount;
    final avg = orders.isEmpty ? 0.0 : revenue / orders.length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${S.t(context, 'Halo')}, ${auth.user?.name.split(' ').first ?? 'Kasir'}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              auth.currentOutlet?.name ?? S.t(context, 'Outlet belum dipilih'),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Ganti outlet'),
            onPressed: () => _open(const OutletSelectionScreen()),
            icon: const Icon(Icons.storefront_outlined),
          ),
          IconButton(
            tooltip: S.t(context, 'Muat ulang'),
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              children: [
                SyncStatusCard(
                  online: _online,
                  pendingCount: _pendingCount,
                  failedCount: _failedCount,
                  syncing: _syncing,
                  onSync: _syncNow,
                  onOpenSyncSettings: () => _open(const SyncScreen()),
                ),
                const SizedBox(height: AppSpacing.lg),

                Text(
                  S.t(context, 'Ringkasan Hari Ini'),
                  style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        label: S.t(context, 'Omzet'),
                        value: Fmt.rupiah(revenue),
                        icon: Icons.payments_outlined,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: MetricCard(
                        label: S.t(context, 'Transaksi'),
                        value: '${orders.length}',
                        icon: Icons.receipt_long_outlined,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        label: S.t(context, 'Rata-rata / Transaksi'),
                        value: Fmt.rupiah(avg),
                        icon: Icons.trending_up,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: MetricCard(
                        label: S.t(context, 'Belum Lunas'),
                        value: '$unpaidCount',
                        caption: '$paidCount ${S.t(context, 'lunas')}',
                        icon: Icons.pending_actions_outlined,
                        color: unpaidCount > 0
                            ? AppColors.warning
                            : AppColors.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                Text(
                  S.t(context, 'Aksi Cepat'),
                  style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
                ),
                const SizedBox(height: AppSpacing.sm),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth < 420 ? 2 : 4;
                    return GridView.count(
                      crossAxisCount: columns,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: AppSpacing.md,
                      crossAxisSpacing: AppSpacing.md,
                      childAspectRatio: 1.16,
                      children: [
                        _quickAction(
                          icon: Icons.point_of_sale_outlined,
                          color: AppColors.primary,
                          label: S.t(context, 'Transaksi Baru'),
                          onTap: () => widget.onOpenTab?.call(1),
                        ),
                        _quickAction(
                          icon: Icons.history,
                          color: AppColors.textSecondary,
                          label: S.t(context, 'Riwayat'),
                          onTap: () => _open(const OrdersScreen()),
                        ),
                        _quickAction(
                          icon: Icons.people_outline,
                          color: AppColors.success,
                          label: S.t(context, 'Pelanggan'),
                          onTap: () => _open(const CustomerListScreen()),
                        ),
                        _quickAction(
                          icon: Icons.warning_amber_rounded,
                          color: AppColors.warning,
                          label: S.t(context, 'Peringatan Stok'),
                          onTap: () => _open(const StockAlertScreen()),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.lg),

                SectionHeader(
                  _lowStock.isEmpty
                      ? S.t(context, 'Stok Minimum')
                      : '${S.t(context, 'Stok Menipis')} (${_lowStock.length})',
                  actionLabel: _lowStock.isEmpty
                      ? null
                      : S.t(context, 'Lihat Semua'),
                  onAction: _lowStock.isEmpty
                      ? null
                      : () => _open(const StockAlertScreen()),
                ),
                _buildLowStock(theme),
                const SizedBox(height: AppSpacing.lg),

                SectionHeader(
                  S.t(context, 'Transaksi Terakhir'),
                  actionLabel: orders.isEmpty
                      ? null
                      : S.t(context, 'Lihat Semua'),
                  onAction: orders.isEmpty
                      ? null
                      : () => _open(const OrdersScreen()),
                ),
                _buildRecentOrders(orders),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickAction({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: AppSpacing.sm),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLowStock(ThemeData theme) {
    if (_lowStockLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_lowStockError != null) {
      return Text(
        _lowStockError!,
        style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
      );
    }
    if (_lowStock.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(
            Icons.check_circle_outline,
            color: AppColors.success,
          ),
          title: Text(
            S.t(context, 'Semua stok di atas batas minimum.'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          for (final item in _lowStock.take(3))
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: AppColors.warning,
              ),
              title: Text(
                item['name']?.toString() ?? '-',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                item['sku'] != null && item['sku'].toString().isNotEmpty
                    ? 'SKU ${item['sku']}'
                    : '',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: StatusBadge(
                '${S.t(context, 'Sisa')} ${item['current_stock'] ?? 0}'
                ' / ${item['min_stock'] ?? 0}',
                tone: BadgeTone.error,
              ),
            ),
          if (_lowStock.length > 3)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                '+${_lowStock.length - 3} ${S.t(context, 'produk lainnya')}',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentOrders(List<Order> orders) {
    if (orders.isEmpty) {
      final op = context.watch<OrderProvider>();
      if (op.isLoading) {
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
        );
      }
      return Card(
        child: ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text(
            op.error ?? S.t(context, 'Belum ada transaksi hari ini.'),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: op.error != null
              ? Text(
                  S.t(context, 'Tarik ke bawah untuk mencoba lagi.'),
                  style: const TextStyle(fontSize: 11.5),
                )
              : null,
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          for (final order in orders.take(5))
            ListTile(
              dense: true,
              leading: const Icon(Icons.receipt_long_outlined, size: 20),
              title: Text(
                order.orderNumber,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '${Fmt.dateTime(order.createdAt)} · '
                '${order.items?.length ?? 0} ${S.t(context, 'item')}',
                style: const TextStyle(fontSize: 11.5),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Fmt.rupiah(order.totalAmount),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  if (order.paymentStatus != 'paid')
                    Text(
                      order.paymentStatus == 'partial'
                          ? S.t(context, 'Sebagian')
                          : S.t(context, 'Belum Bayar'),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              onTap: () => _open(
                OrderDetailScreen(orderId: order.id, initialOrder: order),
              ),
            ),
        ],
      ),
    );
  }
}
