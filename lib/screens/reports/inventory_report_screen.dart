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
import '../../widgets/common/status_badge.dart';

class _StockRow {
  final String name;
  final double qty;
  final String? extra;
  _StockRow({required this.name, required this.qty, this.extra});
}

class _Movement {
  final String label;
  final String type;
  final double change;
  final String date;
  _Movement({
    required this.label,
    required this.type,
    required this.change,
    required this.date,
  });
}

/// Laporan inventori (kontrak grup 14):
/// GET /reports/inventory?outlet_id=
/// → {low_stock[], overstock[], opname_accuracy, total_value, movements[]}.
/// Catatan jujur: export PDF/Excel tetap via web.
class InventoryReportScreen extends StatefulWidget {
  const InventoryReportScreen({super.key});

  @override
  State<InventoryReportScreen> createState() => _InventoryReportScreenState();
}

class _InventoryReportScreenState extends State<InventoryReportScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  double _totalValue = 0;
  double? _opnameAccuracy;
  List<_StockRow> _lowStock = [];
  List<_StockRow> _overstock = [];
  List<_Movement> _movements = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  static List<_StockRow> _parseStockRows(dynamic raw) {
    if (raw is! List) return [];
    return raw.whereType<Map<String, dynamic>>().map((e) {
      return _StockRow(
        name: safeString(e['name'] ?? e['product_name'], '-'),
        qty: safeDouble(e['qty'] ?? e['stock'] ?? e['quantity']),
        extra: (e['sku'] ?? e['unit'])?.toString(),
      );
    }).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final outletId = context.read<AuthProvider>().currentOutletId;
      final response = await _api.get(
        '/reports/inventory',
        query: {if (outletId != null) 'outlet_id': '$outletId'},
      );
      final data = response is Map ? response['data'] : null;
      final m = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final movRaw = m['movements'];
      if (!mounted) return;
      setState(() {
        _totalValue = safeDouble(m['total_value']);
        _opnameAccuracy = m['opname_accuracy'] == null
            ? null
            : safeDouble(m['opname_accuracy']);
        _lowStock = _parseStockRows(m['low_stock']);
        _overstock = _parseStockRows(m['overstock']);
        _movements = movRaw is List
            ? movRaw.whereType<Map<String, dynamic>>().map((e) {
                return _Movement(
                  label: safeString(
                    e['product_name'] ?? e['name'] ?? e['reference_type'],
                    '-',
                  ),
                  type: safeString(e['type'], '-'),
                  change: safeDouble(e['qty_change'] ?? e['change']),
                  date: safeString(
                    e['created_at'] ?? e['date'],
                    '',
                  ),
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
        _error = S.tn(context, 'Gagal memuat laporan inventori.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Laporan Inventori')),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Muat ulang'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: LoadingSkeleton(items: 6, itemHeight: 64),
      );
    }
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    final theme = Theme.of(context);

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
                  label: S.t(context, 'Nilai Stok'),
                  value: Fmt.rupiah(_totalValue),
                  icon: Icons.inventory_2_outlined,
                  color: AppColors.primary,
                  compact: true,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: MetricCard(
                  label: S.t(context, 'Akurasi Opname'),
                  value: _opnameAccuracy == null
                      ? '-'
                      : '${_opnameAccuracy!.toStringAsFixed(1)}%',
                  icon: Icons.fact_check_outlined,
                  color: AppColors.success,
                  caption: _opnameAccuracy == null
                      ? S.t(context, 'Belum ada opname')
                      : null,
                  compact: true,
                ),
              ),
            ],
          ),
          SectionHeader(S.t(context, 'Stok Menipis')),
          if (_lowStock.isEmpty)
            Text(
              S.t(context, 'Tidak ada produk stok menipis.'),
              style: theme.textTheme.bodySmall,
            )
          else
            Card(
              child: Column(
                children: [
                  for (final s in _lowStock)
                    ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: Color(0xFFB45309),
                      ),
                      title: Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: s.extra == null
                          ? null
                          : Text(
                              s.extra!,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                      trailing: StatusBadge(
                        Fmt.thousand(s.qty),
                        tone: BadgeTone.warning,
                      ),
                    ),
                ],
              ),
            ),
          SectionHeader(S.t(context, 'Stok Berlebih')),
          if (_overstock.isEmpty)
            Text(
              S.t(context, 'Tidak ada produk stok berlebih.'),
              style: theme.textTheme.bodySmall,
            )
          else
            Card(
              child: Column(
                children: [
                  for (final s in _overstock)
                    ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.inventory_outlined,
                        size: 18,
                      ),
                      title: Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Text(
                        Fmt.thousand(s.qty),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          SectionHeader(S.t(context, 'Mutasi Terakhir')),
          if (_movements.isEmpty)
            Text(
              S.t(context, 'Belum ada mutasi tercatat.'),
              style: theme.textTheme.bodySmall,
            )
          else
            Card(
              child: Column(
                children: [
                  for (final mv in _movements.take(15))
                    ListTile(
                      dense: true,
                      title: Text(
                        mv.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        mv.date.isEmpty ? mv.type : '${mv.type} · ${mv.date}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: Text(
                        '${mv.change > 0 ? '+' : ''}${Fmt.thousand(mv.change)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: mv.change >= 0
                              ? AppColors.success
                              : AppColors.error,
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
