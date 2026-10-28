import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/safe_parse.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/metric_card.dart';
import '../../widgets/common/section_header.dart';

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

/// Laporan inventori — backend nyata (produksi) TIDAK menyediakan
/// GET /reports/inventory. Layar ini memetakan ke endpoint yang ADA:
/// - GET /reports/stock → {inventory_value, low_stock (jumlah),
///   out_of_stock (jumlah), outlet_scope}
/// - GET /stock-movements?per_page= (envelope) → {id, product: {name},
///   type: in|out, quantity, reference_type, created_at}
///
/// Tidak ada sumber server untuk akurasi opname maupun daftar nama
/// produk overstock, jadi kartu tersebut diganti jumlah yang jujur.
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
  int _lowStockCount = 0;
  int _outOfStockCount = 0;
  List<_Movement> _movements = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  static List<_Movement> parseMovements(dynamic raw) {
    if (raw is! List) return [];
    return raw.whereType<Map<String, dynamic>>().map((e) {
      final product = e['product'];
      final qty = safeDouble(e['quantity'] ?? e['qty_change'] ?? e['change']);
      final type = safeString(e['type'], '-').toLowerCase();
      // Arus keluar (out/sale) tampil negatif agar konsisten.
      final signed = (type == 'out' && qty > 0) ? -qty : qty;
      return _Movement(
        label: product is Map
            ? safeString(product['name'], '-')
            : safeString(
                e['product_name'] ?? e['name'] ?? e['reference_type'],
                '-',
              ),
        type: type,
        change: signed,
        date: safeString(e['created_at'] ?? e['date'], ''),
      );
    }).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // GET /reports/stock tidak menerima outlet_id (scope dari token).
      final results = await Future.wait([
        _api.get('/reports/stock'),
        _api.get('/stock-movements', query: {'per_page': '15'}),
      ]);
      final stockData = results[0] is Map
          ? (results[0] as Map)['data']
          : null;
      final stock = stockData is Map<String, dynamic>
          ? stockData
          : <String, dynamic>{};
      final movRaw = results[1] is Map
          ? (results[1] as Map)['data']
          : results[1];
      if (!mounted) return;
      setState(() {
        _totalValue = safeDouble(
          stock['inventory_value'] ?? stock['total_value'],
        );
        _lowStockCount = safeInt(stock['low_stock']);
        _outOfStockCount = safeInt(stock['out_of_stock']);
        _movements = parseMovements(movRaw);
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
          MetricCard(
            label: S.t(context, 'Nilai Stok'),
            value: Fmt.rupiah(_totalValue),
            icon: Icons.inventory_2_outlined,
            color: AppColors.primary,
            caption: S.t(
              context,
              'Angka dihitung server dari seluruh katalog aktif.',
            ),
            compact: true,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  label: S.t(context, 'Stok Menipis'),
                  value: '$_lowStockCount',
                  icon: Icons.warning_amber_rounded,
                  color: _lowStockCount > 0
                      ? AppColors.warning
                      : AppColors.success,
                  caption: S.t(context, 'produk'),
                  compact: true,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: MetricCard(
                  label: S.t(context, 'Stok Habis'),
                  value: '$_outOfStockCount',
                  icon: Icons.remove_shopping_cart_outlined,
                  color: _outOfStockCount > 0
                      ? AppColors.error
                      : AppColors.success,
                  caption: S.t(context, 'produk'),
                  compact: true,
                ),
              ),
            ],
          ),
          SectionHeader(S.t(context, 'Mutasi Terakhir')),
          if (_movements.isEmpty)
            Text(
              S.t(context, 'Belum ada mutasi tercatat.'),
              style: Theme.of(context).textTheme.bodySmall,
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
