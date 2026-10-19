import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

enum BadgeTone { success, warning, error, info, neutral }

/// Lencana status kecil (lunas/menunggu/gagal, dll).
class StatusBadge extends StatelessWidget {
  final String label;
  final BadgeTone tone;
  final double fontSize;

  const StatusBadge(
    this.label, {
    super.key,
    this.tone = BadgeTone.neutral,
    this.fontSize = 11,
  });

  static (Color bg, Color fg) colorsFor(BadgeTone tone) {
    switch (tone) {
      case BadgeTone.success:
        return (AppColors.successSoft, const Color(0xFF047857));
      case BadgeTone.warning:
        return (AppColors.warningSoft, const Color(0xFFB45309));
      case BadgeTone.error:
        return (AppColors.errorSoft, const Color(0xFFB91C1C));
      case BadgeTone.info:
        return (AppColors.primarySoft, AppColors.primaryDark);
      case BadgeTone.neutral:
        return (const Color(0xFFE2E8F0), const Color(0xFF475569));
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = colorsFor(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

BadgeTone toneForOrderStatus(String status) {
  switch (status) {
    case 'completed':
      return BadgeTone.success;
    case 'processing':
      return BadgeTone.info;
    case 'cancelled':
      return BadgeTone.error;
    case 'pending':
    default:
      return BadgeTone.warning;
  }
}

BadgeTone toneForPaymentStatus(String status) {
  switch (status) {
    case 'paid':
      return BadgeTone.success;
    case 'partial':
      return BadgeTone.warning;
    case 'refunded':
      return BadgeTone.error;
    case 'pending':
    default:
      return BadgeTone.neutral;
  }
}
