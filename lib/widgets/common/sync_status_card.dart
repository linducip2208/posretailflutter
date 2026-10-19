import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../theme/app_theme.dart';
import 'status_badge.dart';

/// Ringkasan status koneksi + antrean offline. Dipakai di Beranda/POS.
class SyncStatusCard extends StatelessWidget {
  final bool online;
  final int pendingCount;
  final int failedCount;
  final bool syncing;
  final VoidCallback? onSync;
  final VoidCallback? onOpenQueue;
  final VoidCallback? onOpenSyncSettings;

  const SyncStatusCard({
    super.key,
    required this.online,
    this.pendingCount = 0,
    this.failedCount = 0,
    this.syncing = false,
    this.onSync,
    this.onOpenQueue,
    this.onOpenSyncSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasQueue = pendingCount > 0 || failedCount > 0;

    final (Color tone, IconData icon, String title) = !online
        ? (
            AppColors.warning,
            Icons.cloud_off_rounded,
            S.t(context, 'Mode Offline'),
          )
        : failedCount > 0
        ? (
            AppColors.error,
            Icons.sync_problem_rounded,
            S.t(context, 'Sinkronisasi perlu perhatian'),
          )
        : pendingCount > 0
        ? (
            AppColors.warning,
            Icons.cloud_upload_outlined,
            S.t(context, 'Menunggu kirim'),
          )
        : (
            AppColors.success,
            Icons.cloud_done_rounded,
            S.t(context, 'Semua tersinkron'),
          );

    return Card(
      child: InkWell(
        onTap: onOpenSyncSettings,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: syncing
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(icon, color: tone, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(context),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (hasQueue) ...[
                const SizedBox(width: AppSpacing.sm),
                if (failedCount > 0)
                  StatusBadge(
                    '${S.t(context, 'gagal')} $failedCount',
                    tone: BadgeTone.error,
                  ),
                if (onSync != null)
                  IconButton(
                    tooltip: S.t(context, 'Sinkronkan sekarang'),
                    onPressed: syncing ? null : onSync,
                    icon: const Icon(Icons.sync, size: 20),
                  )
                else if (onOpenQueue != null)
                  IconButton(
                    tooltip: S.t(context, 'Lihat antrean'),
                    onPressed: onOpenQueue,
                    icon: const Icon(Icons.chevron_right),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(BuildContext context) {
    if (!online && pendingCount > 0) {
      return '${S.t(context, 'Tidak ada koneksi.')} $pendingCount ${S.t(context, 'transaksi menunggu dikirim saat online')}.';
    }
    if (!online) {
      return S.t(
        context,
        'Tidak ada koneksi ke server. Transaksi baru akan disimpan di perangkat.',
      );
    }
    if (failedCount > 0) {
      return '$failedCount ${S.t(context, 'transaksi gagal sinkron. Periksa detail lalu coba lagi')}.';
    }
    if (pendingCount > 0) {
      return '$pendingCount ${S.t(context, 'transaksi menunggu dikirim ke server')}.';
    }
    return S.t(context, 'Tidak ada transaksi tertunda.');
  }
}
