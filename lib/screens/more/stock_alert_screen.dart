import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/s.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';

/// Peringatan stok menipis + rekomendasi restock.
///
/// Sumber: `/inventory/forecast` (data nyata outlet aktif).
/// Rumus server: rata-rata mingguan dari penjualan `completed` beberapa
/// minggu terakhir; forecast minggu depan = ceil(rata-rata × 1.1);
/// saran order = forecast − stok saat ini (minimal 0).
class StockAlertScreen extends StatefulWidget {
  const StockAlertScreen({super.key});

  @override
  State<StockAlertScreen> createState() => _StockAlertScreenState();
}

class _StockAlertScreenState extends State<StockAlertScreen> {
  final ApiService _api = ApiService();

  List<Map<String, dynamic>> _lowStock = [];
  List<Map<String, dynamic>> _forecast = [];
  static const int _weeks = 12;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final outletId = context.read<AuthProvider>().currentOutletId;
    try {
      final response = await _api.get(
        '/inventory/forecast',
        query: {'weeks': '$_weeks', 'outlet_id': outletId?.toString()},
      );
      final dynamic data = response is Map
          ? (response['data'] ?? response)
          : response;
      final low = data is Map && data['low_stock'] is List
          ? (data['low_stock'] as List)
                .whereType<Map<String, dynamic>>()
                .toList()
          : <Map<String, dynamic>>[];
      final forecast = data is Map && data['forecast'] is List
          ? (data['forecast'] as List)
                .whereType<Map<String, dynamic>>()
                .toList()
          : <Map<String, dynamic>>[];
      // Hanya tampilkan yang benar-benar butuh restock.
      forecast.sort(
        (a, b) =>
            _num(b['suggested_order']).compareTo(_num(a['suggested_order'])),
      );
      if (!mounted) return;
      setState(() {
        _lowStock = low;
        _forecast = forecast
            .where((f) => _num(f['suggested_order']) > 0)
            .toList();
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
        _error = S.tn(context, 'Gagal memuat data stok.');
      });
    }
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  void _showInfo() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t(ctx, 'Cara angka dihitung')),
        content: Text(
          S.t(
            ctx,
            'Penjualan mingguan diambil dari transaksi selesai di outlet ini '
            'selama $_weeks minggu terakhir. Perkiraan minggu depan = '
            'rata-rata × 1,1 (dibulatkan ke atas). Saran order = perkiraan − '
            'stok saat ini. Angka bersifat pendamping keputusan, bukan '
            'kewajiban order.',
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
        title: Text(S.t(context, 'Peringatan Stok')),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Cara angka dihitung'),
            onPressed: _showInfo,
            icon: const Icon(Icons.info_outline),
          ),
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
    if (_loading) return const LoadingSkeleton(items: 6, itemHeight: 64);
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    final theme = Theme.of(context);
    if (_lowStock.isEmpty && _forecast.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: S.t(context, 'Stok aman'),
        message: S.t(
          context,
          'Tidak ada produk di bawah stok minimum dan tidak ada rekomendasi restock saat ini.',
        ),
      );
    }

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
          if (_lowStock.isNotEmpty) ...[
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: Color(0xFFB45309),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${S.t(context, 'Stok Menipis')} (${_lowStock.length})',
                  style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: Column(
                children: [
                  for (final item in _lowStock)
                    ListTile(
                      dense: true,
                      title: Text(
                        item['name']?.toString() ?? '-',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        item['sku'] != null && item['sku'].toString().isNotEmpty
                            ? 'SKU ${item['sku']}'
                            : '',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: StatusBadge(
                        '${S.t(context, 'Sisa')} ${_num(item['current_stock']).toInt()}'
                        ' / min ${_num(item['min_stock']).toInt()}',
                        tone: BadgeTone.error,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (_forecast.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  Icons.trending_up,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${S.t(context, 'Rekomendasi Restock')} (${_forecast.length})',
                  style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${S.t(context, 'Berdasarkan penjualan')} $_weeks '
              '${S.t(context, 'minggu terakhir di outlet aktif.')}',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: Column(
                children: [
                  for (final item in _forecast)
                    ListTile(
                      dense: true,
                      title: Text(
                        item['product_name']?.toString() ?? '-',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${S.t(context, 'Rata-rata')} '
                        '${_num(item['avg_weekly_sold']).toStringAsFixed(1)}/'
                        '${S.t(context, 'minggu')} · '
                        '${S.t(context, 'stok')} ${_num(item['current_stock']).toInt()}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '+${_num(item['suggested_order']).toInt()}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Text(
                            S.t(context, 'saran order'),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            S.t(
              context,
              'Data diperbarui saat server menerima transaksi baru. Restock dilakukan dari panel admin web.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
