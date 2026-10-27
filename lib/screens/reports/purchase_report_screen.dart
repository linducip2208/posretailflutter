import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/s.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/safe_parse.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/metric_card.dart';
import '../../widgets/common/section_header.dart';

class _SupplierStat {
  final String name;
  final double total;
  _SupplierStat({required this.name, required this.total});
}

class _TrendPoint {
  final String date;
  final double total;
  _TrendPoint({required this.date, required this.total});
}

/// Laporan pembelian (kontrak grup 14):
/// GET /reports/purchases?start_date=&end_date=&outlet_id=
/// → {total_cost, po_count, outstanding_po, top_suppliers[], trend[]}.
/// Catatan jujur: export PDF/Excel tetap via web.
class PurchaseReportScreen extends StatefulWidget {
  const PurchaseReportScreen({super.key});

  @override
  State<PurchaseReportScreen> createState() => _PurchaseReportScreenState();
}

class _PurchaseReportScreenState extends State<PurchaseReportScreen> {
  final ApiService _api = ApiService();
  int _periodIndex = 0;
  DateTimeRange? _customRange;

  bool _loading = true;
  String? _error;
  double _totalCost = 0;
  int _poCount = 0;
  int _outstandingPo = 0;
  List<_SupplierStat> _topSuppliers = [];
  List<_TrendPoint> _trend = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final range = _range();
      final outletId = context.read<AuthProvider>().currentOutletId;
      final response = await _api.get(
        '/reports/purchases',
        query: {
          'start_date': Fmt.dateForApi(range.start),
          'end_date': Fmt.dateForApi(range.end),
          if (outletId != null) 'outlet_id': '$outletId',
        },
      );
      final data = response is Map ? response['data'] : null;
      final m = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final suppliersRaw = m['top_suppliers'];
      final trendRaw = m['trend'];
      if (!mounted) return;
      setState(() {
        _totalCost = safeDouble(m['total_cost']);
        _poCount = safeInt(m['po_count']);
        _outstandingPo = safeInt(m['outstanding_po']);
        _topSuppliers = suppliersRaw is List
            ? suppliersRaw.whereType<Map<String, dynamic>>().map((e) {
                return _SupplierStat(
                  name: safeString(
                    e['name'] ?? e['supplier_name'],
                    S.tn(context, 'Tanpa nama'),
                  ),
                  total: safeDouble(e['total'] ?? e['total_cost']),
                );
              }).toList()
            : [];
        _trend = trendRaw is List
            ? trendRaw.whereType<Map<String, dynamic>>().map((e) {
                return _TrendPoint(
                  date: safeString(e['date']),
                  total: safeDouble(e['total'] ?? e['total_cost']),
                );
              }).toList()
            : [];
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
        _error = S.tn(context, 'Gagal memuat laporan pembelian.');
      });
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
    setState(() {
      _customRange = picked;
      _periodIndex = 3;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Laporan Pembelian')),
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
    if (_loading) return const LoadingSkeleton(items: 6, itemHeight: 64);
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    final theme = Theme.of(context);
    final maxTrend = _trend.fold<double>(
      0,
      (p, e) => e.total > p ? e.total : p,
    );

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
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  label: S.t(context, 'Total Belanja'),
                  value: Fmt.rupiah(_totalCost),
                  icon: Icons.shopping_cart_outlined,
                  color: AppColors.primary,
                  compact: true,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: MetricCard(
                  label: S.t(context, 'Jumlah PO'),
                  value: '$_poCount',
                  icon: Icons.receipt_long_outlined,
                  color: AppColors.success,
                  compact: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          MetricCard(
            label: S.t(context, 'PO Belum Selesai'),
            value: '$_outstandingPo',
            icon: Icons.pending_actions_outlined,
            color: _outstandingPo > 0
                ? AppColors.warning
                : AppColors.success,
            caption: S.t(context, 'Draft + dipesan + dikirim'),
            compact: true,
          ),
          SectionHeader(S.t(context, 'Tren Belanja Harian')),
          if (_trend.isEmpty)
            Text(
              S.t(context, 'Belum ada tren pada periode ini.'),
              style: theme.textTheme.bodySmall,
            )
          else
            Card(
              child: Column(
                children: [
                  for (final t in _trend)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 92,
                            child: Text(
                              t.date,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: maxTrend <= 0
                                    ? 0
                                    : (t.total / maxTrend).clamp(0.0, 1.0),
                                minHeight: 8,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          SizedBox(
                            width: 96,
                            child: Text(
                              Fmt.rupiah(t.total),
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ),
            ),
          SectionHeader(S.t(context, 'Supplier Teratas')),
          if (_topSuppliers.isEmpty)
            Text(
              S.t(context, 'Belum ada pembelian supplier pada periode ini.'),
              style: theme.textTheme.bodySmall,
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < _topSuppliers.length; i++)
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
                        _topSuppliers[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Text(
                        Fmt.rupiah(_topSuppliers[i].total),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    S.t(
                      context,
                      'Unduh PDF/Excel tersedia di web admin. Mobile menampilkan ringkasan saja.',
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => showAppSnackbar(
                    context,
                    S.tn(
                      context,
                      'Buka web admin untuk mengunduh PDF/Excel.',
                    ),
                  ),
                  child: Text(S.t(context, 'Info')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
