import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../theme/app_theme.dart';

/// Tampilan gagal memuat — pesan manusiawi + tombol coba lagi.
class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.wifi_off_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              S.t(context, 'Gagal memuat data'),
              style: theme.textTheme.titleSmall?.copyWith(fontSize: 15),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(S.t(context, 'Coba Lagi')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
