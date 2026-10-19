import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

enum SnackType { success, error, warning, info }

/// Snackbar standar dengan ikon + warna sesuai jenis pesan.
void showAppSnackbar(
  BuildContext context,
  String message, {
  SnackType type = SnackType.info,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 3),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  final (Color bg, IconData icon) = switch (type) {
    SnackType.success => (const Color(0xFF065F46), Icons.check_circle_outline),
    SnackType.error => (const Color(0xFF991B1B), Icons.error_outline),
    SnackType.warning => (const Color(0xFF92400E), Icons.warning_amber_rounded),
    SnackType.info => (AppColors.primaryDark, Icons.info_outline),
  };

  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        backgroundColor: bg,
        duration: duration,
        action: action,
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    );
}
