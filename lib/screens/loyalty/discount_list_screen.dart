import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../models/loyalty.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';

/// Daftar template diskon — backend nyata (produksi, READ-ONLY):
/// GET /discounts (envelope `{data: [...]}`) → {id, name, type, value,
/// min_purchase, buy_quantity, get_quantity, start_date, end_date,
/// active, outlet_id}. Server tidak mendukung filter type/active dan
/// tidak menyediakan POST/PUT, jadi layar ini read-only yang jujur:
/// tambah/ubah/toggle hanya dari web admin.
class DiscountListScreen extends StatefulWidget {
  const DiscountListScreen({super.key});

  @override
  State<DiscountListScreen> createState() => _DiscountListScreenState();
}

class _DiscountListScreenState extends State<DiscountListScreen> {
  final ApiService _api = ApiService();

  List<DiscountTemplate> _items = [];
  bool _loading = true;
  String? _error;
  String? _typeFilter; // null = semua (filter client-side)
  String? _activeFilter; // null = semua (filter client-side)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  static List<DiscountTemplate> parseList(dynamic data) {
    final List<dynamic> rows;
    if (data is List) {
      rows = data;
    } else if (data is Map && data['data'] is List) {
      rows = data['data'] as List;
    } else {
      return [];
    }
    return rows
        .whereType<Map<String, dynamic>>()
        .map(DiscountTemplate.fromJson)
        .toList();
  }

  /// Terapkan filter tampilan client-side (server mengabaikan type/active).
  List<DiscountTemplate> _filtered() {
    return _items.where((d) {
      if (_typeFilter != null && d.type != _typeFilter) return false;
      if (_activeFilter == '1' && !d.active) return false;
      if (_activeFilter == '0' && d.active) return false;
      return true;
    }).toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.get('/discounts');
      final data = response is Map ? response['data'] : response;
      if (!mounted) return;
      setState(() {
        _items = parseList(data);
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
        _error = S.tn(context, 'Gagal memuat template diskon.');
      });
    }
  }

  String _valueLabel(DiscountTemplate d) {
    switch (d.type) {
      case 'percent':
        return '${d.value.toStringAsFixed(d.value.truncateToDouble() == d.value ? 0 : 1)}%';
      case 'fixed':
        return Fmt.rupiah(d.value);
      case 'buy_x_get_y':
        return '${S.t(context, 'Beli')} ${d.buyQty} ${S.t(context, 'gratis')} ${d.getQty}';
      default:
        return '${d.value}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Template Diskon')),
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
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              0,
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              S.t(
                context,
                'Kelola dari web admin (read-only di aplikasi).',
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _typeFilter,
                    decoration: InputDecoration(
                      labelText: S.t(context, 'Tipe'),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(S.t(context, 'Semua tipe')),
                      ),
                      DropdownMenuItem(
                        value: 'percent',
                        child: Text(discountTypeLabel('percent')),
                      ),
                      DropdownMenuItem(
                        value: 'fixed',
                        child: Text(discountTypeLabel('fixed')),
                      ),
                      DropdownMenuItem(
                        value: 'buy_x_get_y',
                        child: Text(discountTypeLabel('buy_x_get_y')),
                      ),
                    ],
                    onChanged: (v) => setState(() => _typeFilter = v),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _activeFilter,
                    decoration: InputDecoration(
                      labelText: S.t(context, 'Status'),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(S.t(context, 'Semua')),
                      ),
                      DropdownMenuItem(
                        value: '1',
                        child: Text(S.t(context, 'Aktif')),
                      ),
                      DropdownMenuItem(
                        value: '0',
                        child: Text(S.t(context, 'Nonaktif')),
                      ),
                    ],
                    onChanged: (v) => setState(() => _activeFilter = v),
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

  Widget _buildBody() {
    if (_loading) return const LoadingSkeleton(items: 6, itemHeight: 64);
    if (_error != null) return ErrorState(message: _error!, onRetry: _refresh);
    final rows = _filtered();
    if (rows.isEmpty) {
      return EmptyState(
        icon: Icons.discount_outlined,
        title: S.t(context, 'Tidak ada template diskon'),
        message: S.t(
          context,
          'Template baru dibuat dari web admin.',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        itemCount: rows.length,
        itemBuilder: (_, i) => _discountCard(rows[i]),
      ),
    );
  }

  Widget _discountCard(DiscountTemplate d) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primaryContainer,
          child: Icon(
            Icons.discount,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          d.name,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${discountTypeLabel(d.type)} · ${_valueLabel(d)}'
          '${d.minPurchase > 0 ? ' · min ${Fmt.rupiah(d.minPurchase)}' : ''}'
          '${d.active ? '' : ' · ${S.t(context, 'Nonaktif')}'}',
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: Icon(
          d.active ? Icons.check_circle : Icons.cancel,
          color: d.active ? AppColors.success : AppColors.textSecondary,
          size: 20,
        ),
      ),
    );
  }
}
