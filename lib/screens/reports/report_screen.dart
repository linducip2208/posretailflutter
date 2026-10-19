import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/s.dart';
import '../../providers/auth_provider.dart';
import '../../providers/report_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/metric_card.dart';
import '../../widgets/common/section_header.dart';
import '../orders/orders_screen.dart';
import '../orders/order_detail_screen.dart';

/// Laporan operasional dari data server nyata (`/orders/history`).
///
/// Catatan kejujuran data:
/// - Semua angka dihitung dari pesanan pada outlet aktif.
/// - `payment_method_id` dipetakan ke nama metode via `/payment-methods`.
/// - Backend membatasi 500 pesanan paling baru per rentang — ditandai di UI.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final ReportProvider _report = ReportProvider();
  int _periodIndex = 0;
  DateTimeRange? _customRange;
  bool _loadingBreakdown = false;

  @override
  void initState() {
    super.initState();
    _report.addListener(_onReportChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _report.removeListener(_onReportChanged);
    _report.dispose();
    super.dispose();
  }

  void _onReportChanged() {
    if (!mounted || !context.mounted) return;
    setState(() {});
  }

  DateTimeRange _range() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_periodIndex) {
      case 1:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 6)),
          end: today,
        );
      case 2:
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: today,
        );
      case 3:
        return _customRange ??
            DateTimeRange(
              start: today.subtract(const Duration(days: 29)),
              end: today,
            );
      case 0:
      default:
        return DateTimeRange(start: today, end: today);
    }
  }

  Future<void> _load() async {
    final range = _range();
    final outletId = context.read<AuthProvider>().currentOutletId;
    await _report.load(start: range.start, end: range.end, outletId: outletId);

    if (_report.orders.isNotEmpty) {
      setState(() => _loadingBreakdown = true);
      await _report.loadPaymentBreakdownIfNeeded(outletId: outletId);
      if (mounted) setState(() => _loadingBreakdown = false);
    } else {
      setState(() => _loadingBreakdown = false);
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
    if (picked.end.difference(picked.start).inDays >
        ReportProvider.maxRangeDays) {
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

  void _showInfo() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t(ctx, 'Tentang Laporan')),
        content: Text(
          S.t(
            ctx,
            'Semua angka dihitung dari transaksi outlet aktif pada rentang '
            'yang dipilih. Server membatasi maksimum 500 transaksi per '
            'rentang — bila tercapai, UI menampilkan catatan agar angka '
            'tidak menyesatkan.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t(ctx, 'Mengerti')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Laporan')),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Tentang laporan'),
            onPressed: _showInfo,
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            tooltip: S.t(context, 'Muat ulang'),
            onPressed: _report.isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                _periodChip(0, S.t(context, 'Hari Ini')),
                _periodChip(1, S.t(context, '7 Hari')),
                _periodChip(2, S.t(context, 'Bulan Ini')),
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
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
    if (_report.isLoading) {
      return const LoadingSkeleton(items: 6, itemHeight: 64);
    }
    if (_report.error != null) {
      return ErrorState(message: _report.error!, onRetry: _load);
    }

    final theme = Theme.of(context);
    final bestSellers = _report.bestSellers;
    final payments = _report.paymentBreakdown;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          if (_report.truncated)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFB45309),
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      S.t(
                        context,
                        'Menampilkan maksimum 500 transaksi terbaru. Persempit periode agar total lebih akurat.',
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          Row(
            children: [
              Expanded(
                child: MetricCard(
                  label: S.t(context, 'Omzet'),
                  value: Fmt.rupiah(_report.revenue),
                  icon: Icons.payments_outlined,
                  color: AppColors.primary,
                  compact: true,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: MetricCard(
                  label: S.t(context, 'Transaksi'),
                  value: '${_report.totalOrders}',
                  icon: Icons.receipt_long_outlined,
                  color: AppColors.success,
                  compact: true,
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
                  value: Fmt.rupiah(_report.avgOrder),
                  icon: Icons.trending_up,
                  color: AppColors.accent,
                  compact: true,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: MetricCard(
                  label: S.t(context, 'Belum Lunas'),
                  value: '${_report.unpaidOrders}',
                  icon: Icons.pending_actions_outlined,
                  color: _report.unpaidOrders > 0
                      ? AppColors.warning
                      : AppColors.success,
                  caption: '${_report.paidOrders} ${S.t(context, 'lunas')}',
                  compact: true,
                ),
              ),
            ],
          ),

          SectionHeader(
            S.t(context, 'Metode Pembayaran'),
            actionLabel: _loadingBreakdown ? null : null,
          ),
          if (_loadingBreakdown)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (payments.isEmpty)
            Text(
              S.t(context, 'Belum ada data pembayaran pada periode ini.'),
              style: theme.textTheme.bodySmall,
            )
          else
            Card(
              child: Column(
                children: [
                  for (final p in payments)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.payments_outlined, size: 18),
                      title: Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${p.count} ${S.t(context, 'pembayaran')}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: Text(
                        Fmt.rupiah(p.amount),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),

          SectionHeader(S.t(context, 'Produk Terlaris')),
          if (bestSellers.isEmpty)
            Text(
              S.t(context, 'Belum ada penjualan produk pada periode ini.'),
              style: theme.textTheme.bodySmall,
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < bestSellers.length; i++)
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      title: Text(
                        bestSellers[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${bestSellers[i].qty} ${S.t(context, 'terjual')}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: Text(
                        Fmt.rupiah(bestSellers[i].revenue),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),

          SectionHeader(
            S.t(context, 'Transaksi Terakhir'),
            actionLabel: S.t(context, 'Lihat Semua'),
            onAction: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const OrdersScreen())),
          ),
          if (_report.orders.isEmpty)
            const EmptyState(
              icon: Icons.insert_chart_outlined,
              title: 'Belum ada data',
              message: 'Tidak ada transaksi pada periode ini.',
            )
          else
            Card(
              child: Column(
                children: [
                  for (final order in _report.orders.take(10))
                    ListTile(
                      dense: true,
                      title: Text(
                        order.orderNumber,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        Fmt.dateTime(order.createdAt),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: Text(
                        Fmt.rupiah(order.totalAmount),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OrderDetailScreen(
                            orderId: order.id,
                            initialOrder: order,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
