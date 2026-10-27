import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';

/// Layar generik untuk modul yang sudah ada di web admin
/// (`posretail.whitelabel.co.id`) tapi endpoint API mobile-nya belum tersedia.
///
/// Prinsip kejujuran data: layar ini TIDAK memalsukan data.
/// Ia mencoba memanggil [apiEndpoints] satu per satu:
/// - 200 → tampilkan pratinjau data nyata (daftar mentah).
/// - 401/403 → tampilkan status akses.
/// - 404 → tampilkan status "belum tersedia di API mobile" + arahan
///   kelola via web admin di [webPath].
class WebModuleScreen extends StatefulWidget {
  final String title;
  final String description;
  final String webPath;
  final List<String> apiEndpoints;

  const WebModuleScreen({
    super.key,
    required this.title,
    required this.description,
    required this.webPath,
    this.apiEndpoints = const [],
  });

  @override
  State<WebModuleScreen> createState() => _WebModuleScreenState();
}

class _WebModuleScreenState extends State<WebModuleScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _status;
  List<Map<String, dynamic>> _preview = [];
  String? _matchedEndpoint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _probe());
  }

  Future<void> _probe() async {
    setState(() {
      _loading = true;
      _status = null;
      _preview = [];
      _matchedEndpoint = null;
    });

    if (widget.apiEndpoints.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'not_mapped';
      });
      return;
    }

    String? lastStatus;
    for (final ep in widget.apiEndpoints) {
      try {
        final res = await _api.get(ep);
        final list = _toList(res);
        if (!mounted) return;
        setState(() {
          _loading = false;
          _status = 'ok';
          _matchedEndpoint = ep;
          _preview = list.take(20).toList();
        });
        return;
      } on ApiException catch (e) {
        if (e.statusCode == 404) {
          lastStatus = 'not_found';
          continue;
        }
        if (!mounted) return;
        setState(() {
          _loading = false;
          _status = e.statusCode == 403 ? 'forbidden' : 'error:${e.statusCode}';
        });
        return;
      } catch (_) {
        lastStatus = 'network';
        break;
      }
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _status = lastStatus ?? 'not_found';
    });
  }

  List<Map<String, dynamic>> _toList(dynamic res) {
    final dynamic data = res is Map ? (res['data'] ?? res) : res;
    if (data is List) return data.whereType<Map<String, dynamic>>().toList();
    if (data is Map) {
      for (final k in ['items', 'rows', 'list', 'results']) {
        if (data[k] is List) {
          return (data[k] as List).whereType<Map<String, dynamic>>().toList();
        }
      }
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Muat ulang'),
            onPressed: _loading ? null : _probe,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingSkeleton(items: 5, itemHeight: 64);

    if (_status == 'ok') {
      if (_preview.isEmpty) {
        return EmptyState(
          icon: Icons.check_circle_outline,
          title: S.t(context, 'API tersedia, belum ada data'),
          message:
              '${S.t(context, 'Endpoint')} ${_matchedEndpoint ?? ''} '
              '${S.t(context, 'berhasil dihubungi tapi tidak mengembalikan daftar.')}',
        );
      }
      return RefreshIndicator(
        onRefresh: _probe,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            StatusBadge(
              '${S.t(context, 'Terhubung')}: ${_matchedEndpoint ?? ''}',
              tone: BadgeTone.success,
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Column(
                children: [
                  for (final item in _preview)
                    ListTile(
                      dense: true,
                      title: Text(
                        _labelFor(item),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        _subFor(item),
                        style: const TextStyle(fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              S.t(
                context,
                'Tampilan penuh (filter, aksi, approval) menyusul setelah kontrak API modul ini stabil.',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    final isForbidden = _status == 'forbidden';
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusBadge(
                  isForbidden
                      ? S.t(context, 'Tidak ada akses (403)')
                      : S.t(context, 'Belum tersedia di API mobile (404)'),
                  tone: isForbidden ? BadgeTone.error : BadgeTone.warning,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  widget.description,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '${S.t(context, 'Kelola sementara via web admin')}:',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SelectableText(
                  'posretail.whitelabel.co.id${widget.webPath}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.apiEndpoints.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${S.t(context, 'Endpoint yang dicoba')}: ${widget.apiEndpoints.join(', ')}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: _probe,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(S.t(context, 'Coba lagi')),
        ),
        if (_status != null && _status!.startsWith('error:'))
          ErrorState(message: _status!, onRetry: _probe),
      ],
    );
  }

  String _labelFor(Map<String, dynamic> item) {
    for (final k in ['name', 'title', 'number', 'no', 'code', 'sku']) {
      final v = item[k]?.toString();
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return '#${item['id'] ?? '-'}';
  }

  String _subFor(Map<String, dynamic> item) {
    final parts = <String>[];
    for (final k in ['status', 'outlet_name', 'supplier_name', 'total', 'created_at']) {
      final v = item[k]?.toString();
      if (v != null && v.isNotEmpty && v != 'null') parts.add(v);
    }
    return parts.take(3).join(' · ');
  }
}
