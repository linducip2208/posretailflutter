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

/// Laporan pembelian — coba endpoint server dulu:
/// GET /reports/purchases?start_date=&end_date=(&outlet_id=) →
/// {data: {start_date, end_date, total_cost, po_count, outstanding_po
/// (draft+ordered), top_suppliers: [{name, total}], trend: [{date, total}]}}.
/// Rentang server maksimal 93 hari (422 bila lebih).
/// Bila server 404 (endpoint belum deploy) → fallback jujur ke agregasi
/// client-side dari GET /purchase-orders + badge "mode lokal".
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
  bool _truncated = false;
  bool _serverMode = false;
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

  /// Status PO yang dianggap belum selesai. Backend memakai
  /// draft → ordered/sent → received (+ cancelled).
  static bool _isOutstanding(String status) {
    switch (status.toLowerCase()) {
      case 'received':
      case 'cancelled':
      case 'canceled':
        return false;
      default:
        return true;
    }
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final range = _range();
    final outletId = context.read<AuthProvider>().currentOutletId;
    final noName = S.tn(context, 'Tanpa nama');
    final loadFail = S.tn(context, 'Gagal memuat laporan pembelian.');
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.get(
        '/reports/purchases',
        query: {
          'start_date': Fmt.dateForApi(range.start),
          'end_date': Fmt.dateForApi(range.end),
          if (outletId != null) 'outlet_id': '$outletId',
        },
      );
      final data = response is Map ? response['data'] : null;
      if (data is! Map<String, dynamic>) {
        throw ApiException(statusCode: 500, message: loadFail);
      }
      final rawSuppliers = data['top_suppliers'];
      final suppliers = <_SupplierStat>[];
      if (rawSuppliers is List) {
        for (final e in rawSuppliers.whereType<Map>()) {
          suppliers.add(
            _SupplierStat(
              name: safeString(e['name'], noName),
              total: safeDouble(e['total']),
            ),
          );
        }
      }
      final rawTrend = data['trend'];
      final trend = <_TrendPoint>[];
      if (rawTrend is List) {
        for (final e in rawTrend.whereType<Map>()) {
          final d = e['date']?.toString() ?? '';
          if (d.isEmpty) continue;
          trend.add(_TrendPoint(date: d, total: safeDouble(e['total'])));
        }
      }
      trend.sort((a, b) => a.date.compareTo(b.date));
      if (!mounted) return;
      setState(() {
        _totalCost = safeDouble(data['total_cost']);
        _poCount = safeInt(data['po_count']);
        _outstandingPo = safeInt(data['outstanding_po']);
        _topSuppliers = suppliers;
        _trend = trend;
        _truncated = false;
        _serverMode = true;
        _loading = false;
      });
    } on ApiException catch (e) {
      // Endpoint belum deploy di server → fallback lokal yang jujur.
      if (e.statusCode == 404) {
        await _loadLocal();
        return;
      }
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

  /// Fallback client-side (dipakai bila GET /reports/purchases 404):
  /// agregasi max 100 PO terbaru lalu disaring rentang tanggal.
  Future<void> _loadLocal() async {
    final noName = S.tn(context, 'Tanpa nama');
    final range = _range();
    final outletId = context.read<AuthProvider>().currentOutletId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.get(
        '/purchase-orders',
        query: {
          'per_page': '100',
          if (outletId != null) 'outlet_id': '$outletId',
        },
      );
      final raw = response is Map ? response['data'] : response;
      final rows = raw is List
          ? raw.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      final start = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      );
      final end = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
        23,
        59,
        59,
      );
      final inRange = rows.where((po) {
        final d = _parseDate(po['created_at']);
        if (d == null) return true;
        return !d.isBefore(start) && !d.isAfter(end);
      }).toList();

      double total = 0;
      int outstanding = 0;
      final bySupplier = <String, double>{};
      final byDay = <String, double>{};
      for (final po in inRange) {
        final amount = safeDouble(po['total_amount']);
        total += amount;
        final status = safeString(po['status'], 'draft');
        if (_isOutstanding(status)) outstanding++;
        final supplier = po['supplier'];
        final name = supplier is Map
            ? safeString(supplier['name'], noName)
            : noName;
        bySupplier[name] = (bySupplier[name] ?? 0) + amount;
        final d = _parseDate(po['created_at']);
        if (d != null) {
          final key = Fmt.dateForApi(d);
          byDay[key] = (byDay[key] ?? 0) + amount;
        }
      }
      final suppliers = bySupplier.entries
          .map((e) => _SupplierStat(name: e.key, total: e.value))
          .toList()
        ..sort((a, b) => b.total.compareTo(a.total));
      final trend = byDay.entries
          .map((e) => _TrendPoint(date: e.key, total: e.value))
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      if (!mounted) return;
      setState(() {
        _totalCost = total;
        _poCount = inRange.length;
        _outstandingPo = outstanding;
        _topSuppliers = suppliers.take(10).toList();
        _trend = trend;
        _truncated = rows.length >= 100;
        _serverMode = false;
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
          if (!_serverMode)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      S.t(
                        context,
                        'Mode lokal (server belum tersedia).',
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (_truncated)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                S.t(
                  context,
                  'Dihitung dari 100 PO terbaru pada outlet ini.',
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
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
            caption: _serverMode
                ? S.t(context, 'Draft + dipesan')
                : S.t(context, 'Draft + dipesan + dikirim'),
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
