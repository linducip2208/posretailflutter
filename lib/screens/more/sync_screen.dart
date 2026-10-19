import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../services/offline_sync_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/confirmation_dialog.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/status_badge.dart';

/// Layar antrean offline: lihat transaksi yang belum terkirim ke server,
/// kirim ulang, atau buang bila memang tidak mungkin (mis. produk dihapus).
///
/// Kejujuran data: transaksi yang masih di antrean BELUM tercatat di server.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final OfflineSyncService _offline = OfflineSyncService();

  List<Map<String, dynamic>> _queue = [];
  int _failedCount = 0;
  bool _loading = true;
  bool _syncing = false;
  bool _online = true;
  late final void Function(bool) _listener;

  static const int _maxAttempts = 10;

  @override
  void initState() {
    super.initState();
    _online = _offline.isOnline;
    _listener = (online) {
      if (!mounted) return;
      setState(() => _online = online);
      if (online) _sync(force: false);
    };
    _offline.addListener(_listener);
    _load();
  }

  @override
  void dispose() {
    _offline.removeListener(_listener);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final queue = await _offline.getPendingOrders();
    final failed = await _offline.getFailedCount();
    if (!mounted) return;
    setState(() {
      _queue = queue;
      _failedCount = failed;
      _loading = false;
    });
  }

  Future<void> _sync({bool force = true}) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final sent = await _offline.syncPendingOrders(force: force);
    await _load();
    if (!mounted) return;
    setState(() => _syncing = false);
    if (sent > 0) {
      showAppSnackbar(
        context,
        '$sent ${S.tn(context, 'transaksi berhasil dikirim ke server.')}',
        type: SnackType.success,
      );
    } else if (_queue.isNotEmpty && _online) {
      showAppSnackbar(
        context,
        S.tn(
          context,
          'Belum ada transaksi yang berhasil dikirim. Periksa detail error di bawah.',
        ),
        type: SnackType.warning,
      );
    }
  }

  Future<void> _retryFailed() async {
    final count = await _offline.resetFailedAttempts();
    if (!mounted) return;
    showAppSnackbar(
      context,
      '$count ${S.tn(context, 'transaksi dijadwalkan ulang untuk dikirim.')}',
      type: SnackType.info,
    );
    await _sync(force: true);
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final ok = await confirmDialog(
      context,
      title: S.tn(context, 'Buang transaksi ini?'),
      message: S.tn(
        context,
        'Transaksi ini akan dihapus permanen dari perangkat dan TIDAK akan tercatat di server. Lakukan hanya jika transaksi memang batal/tidak valid.',
      ),
      confirmLabel: S.tn(context, 'Buang'),
      destructive: true,
    );
    if (!ok) return;
    await _offline.deleteQueueItem((item['id'] as int?) ?? 0);
    await _load();
    if (!mounted) return;
    showAppSnackbar(
      context,
      S.tn(context, 'Transaksi dibuang dari antrean.'),
      type: SnackType.info,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Sinkronisasi')),
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            color: _online ? AppColors.successSoft : AppColors.warningSoft,
            child: Row(
              children: [
                Icon(
                  _online ? Icons.cloud_done_outlined : Icons.cloud_off_rounded,
                  color: _online
                      ? const Color(0xFF047857)
                      : const Color(0xFFB45309),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _online
                            ? S.t(context, 'Terhubung ke server')
                            : S.t(context, 'Tidak ada koneksi'),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${_queue.length} ${S.t(context, 'transaksi di antrean')}'
                        '${_failedCount > 0 ? ' · $_failedCount ${S.t(context, 'gagal')}' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _syncing || !_online || _queue.isEmpty
                        ? null
                        : () => _sync(force: true),
                    icon: _syncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.sync, size: 18),
                    label: Text(S.t(context, 'Sinkronkan Sekarang')),
                  ),
                ),
                if (_failedCount > 0) ...[
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _syncing ? null : _retryFailed,
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: Text(S.t(context, 'Coba Lagi')),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _buildQueue(theme)),
        ],
      ),
    );
  }

  Widget _buildQueue(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_queue.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_done_outlined,
        title: S.t(context, 'Tidak ada antrean'),
        message: S.t(context, 'Semua transaksi sudah terkirim ke server.'),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        itemCount: _queue.length,
        itemBuilder: (_, i) {
          final item = _queue[i];
          final attempts = (item['attempts'] as int?) ?? 0;
          final failed = attempts >= _maxAttempts;
          final error = item['last_error']?.toString();
          final uuid = item['client_uuid']?.toString() ?? '-';
          final createdAt = item['created_at']?.toString();

          return Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          S.t(context, 'Transaksi offline'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      StatusBadge(
                        failed
                            ? S.t(context, 'Gagal')
                            : S.t(context, 'Menunggu'),
                        tone: failed ? BadgeTone.error : BadgeTone.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    Fmt.dateTime(createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
                  ),
                  Text(
                    'ID: ${uuid.length > 8 ? uuid.substring(0, 8) : uuid} · '
                    '${S.t(context, 'percobaan')}: $attempts/$_maxAttempts',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                  if (error != null && error.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: failed
                            ? AppColors.errorSoft
                            : theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        error,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                  ],
                  if (failed)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _deleteItem(item),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: Text(
                          S.t(context, 'Buang dari antrean'),
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.error,
                          minimumSize: const Size(0, 36),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
