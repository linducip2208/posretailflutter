import 'package:flutter/material.dart';

import '../../utils/formatters.dart';

/// Harga konsisten di seluruh aplikasi (Rp tanpa desimal).
class PriceText extends StatelessWidget {
  final num amount;
  final double fontSize;
  final FontWeight fontWeight;
  final Color? color;
  final TextAlign? textAlign;
  final int? maxLines;

  const PriceText(
    this.amount, {
    super.key,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w700,
    this.color,
    this.textAlign,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      Fmt.rupiah(amount),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? Theme.of(context).colorScheme.primary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
