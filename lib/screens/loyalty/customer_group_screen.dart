import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../models/loyalty.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';

/// Daftar grup pelanggan (GET /customer-groups): info diskon per grup
/// + syarat auto-upgrade (min_spent).
///
/// Kontrak hanya mendefinisikan GET untuk grup ini, jadi layar bersifat
/// read-only yang jujur: tambah/ubah grup hanya dicoba bila server
/// mendukung POST/PUT; bila 404/405, tampilkan pesan read-only yang jujur.
class CustomerGroupScreen extends StatefulWidget {
  const CustomerGroupScreen({super.key});

  @override
  State<CustomerGroupScreen> createState() => _CustomerGroupScreenState();
}

class _CustomerGroupScreenState extends State<CustomerGroupScreen> {
  final ApiService _api = ApiService();

  List<CustomerGroup> _groups = [];
  bool _loading = true;
  String? _error;
  bool _writeSupported = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  static List<CustomerGroup> parseList(dynamic data) {
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
        .map(CustomerGroup.fromJson)
        .toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.get('/customer-groups');
      final data = response is Map ? response['data'] : response;
      if (!mounted) return;
      setState(() {
        _groups = parseList(data);
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
        _error = S.tn(context, 'Gagal memuat grup pelanggan.');
      });
    }
  }

  Future<void> _tryWrite() async {
    // Backend kontrak grup 9 hanya GET — coba POST probe yang jujur.
    // Bila server menolak (404/405), tandai read-only dan beri tahu user.
    try {
      await _api.post(
        '/customer-groups',
        body: const {'name': '__probe__', 'discount_percent': 0},
      );
      // Bila 2xx (backend mendukung tulis), langsung refresh.
      if (!mounted) return;
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 404 || e.statusCode == 405) {
        setState(() => _writeSupported = false);
        showAppSnackbar(
          context,
          S.tn(
            context,
            'Grup pelanggan read-only di server (hanya tampil + refresh).',
          ),
          type: SnackType.info,
        );
      } else {
        showAppSnackbar(context, e.message, type: SnackType.error);
      }
    } catch (_) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        S.tn(context, 'Gagal menghubungi server.'),
        type: SnackType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Grup Pelanggan')),
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
          if (!_writeSupported)
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
                  'Grup pelanggan dikelola dari web admin (read-only di aplikasi). Data diskon dan syarat upgrade tampil di bawah.',
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingSkeleton(items: 4, itemHeight: 72);
    if (_error != null) return ErrorState(message: _error!, onRetry: _refresh);
    if (_groups.isEmpty) {
      return EmptyState(
        icon: Icons.group_outlined,
        title: S.t(context, 'Tidak ada grup pelanggan'),
        message: S.t(
          context,
          'Grup (Regular/Member/Reseller) dibuat dari web admin.',
        ),
        actionLabel: S.t(context, 'Coba Lagi'),
        onAction: _refresh,
      );
    }
    // Urutkan menaik berdasar min_spent agar alur upgrade terbaca.
    final sorted = [..._groups]
      ..sort((a, b) => a.minSpent.compareTo(b.minSpent));
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: sorted.length + 1,
        itemBuilder: (_, i) {
          if (i == sorted.length) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: _tryWrite,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(
                    _writeSupported
                        ? S.t(context, 'Kelola grup (cek dukungan server)')
                        : S.t(context, 'Muat ulang'),
                  ),
                ),
              ),
            );
          }
          return _groupCard(sorted[i], i, sorted);
        },
      ),
    );
  }

  Widget _groupCard(
    CustomerGroup group,
    int index,
    List<CustomerGroup> sorted,
  ) {
    final theme = Theme.of(context);
    final next = index + 1 < sorted.length ? sorted[index + 1] : null;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    group.name.isEmpty
                        ? '?'
                        : group.name.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (group.memberCount > 0)
                        Text(
                          '${group.memberCount} ${S.t(context, 'anggota')}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11.5,
                          ),
                        ),
                    ],
                  ),
                ),
                StatusBadge(
                  '${group.discountPercent.toStringAsFixed(group.discountPercent.truncateToDouble() == group.discountPercent ? 0 : 1)}% ${S.t(context, 'diskon')}',
                  tone: BadgeTone.success,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${S.t(context, 'Syarat upgrade')}: ${S.t(context, 'belanja min')} ${Fmt.rupiah(group.minSpent)}',
              style: const TextStyle(fontSize: 12),
            ),
            if (next != null)
              Text(
                '${S.t(context, 'Naik ke')} ${next.name} ${S.t(context, 'saat belanja mencapai')} ${Fmt.rupiah(next.minSpent)}.',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
              )
            else
              Text(
                S.t(context, 'Level tertinggi — tidak ada upgrade lanjutan.'),
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
              ),
          ],
        ),
      ),
    );
  }
}
