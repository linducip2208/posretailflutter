import 'package:flutter/material.dart';

import '../l10n/s.dart';
import '../providers/cart_provider.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'common/quantity_stepper.dart';

/// Baris item keranjang: nama (+varian), harga, kuantitas, diskon per item.
class CartItemTile extends StatefulWidget {
  final CartItem item;
  final int index;
  final Function(int, int) onQuantityChanged;
  final Function(int, double) onDiscountChanged;
  final VoidCallback onRemove;

  const CartItemTile({
    super.key,
    required this.item,
    required this.index,
    required this.onQuantityChanged,
    required this.onDiscountChanged,
    required this.onRemove,
  });

  @override
  State<CartItemTile> createState() => _CartItemTileState();
}

class _CartItemTileState extends State<CartItemTile> {
  bool _showDiscount = false;
  late final TextEditingController _discountCtrl;

  @override
  void initState() {
    super.initState();
    _discountCtrl = TextEditingController(
      text: _formatPercent(widget.item.discountPercent),
    );
  }

  @override
  void didUpdateWidget(covariant CartItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.discountPercent != widget.item.discountPercent &&
        _discountCtrl.text != _formatPercent(widget.item.discountPercent)) {
      _discountCtrl.text = _formatPercent(widget.item.discountPercent);
    }
  }

  @override
  void dispose() {
    _discountCtrl.dispose();
    super.dispose();
  }

  String _formatPercent(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}' : '$value';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final hasDiscount = item.discountPercent > 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.product.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.variant != null)
                        Text(
                          '${S.t(context, 'Varian')}: ${item.variant!.name}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: widget.onRemove,
                  tooltip: S.t(context, 'Hapus item'),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  visualDensity: VisualDensity.compact,
                  color: AppColors.error,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${Fmt.rupiah(item.unitPrice)} × ${item.quantity}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                        ),
                      ),
                      Text(
                        Fmt.rupiah(item.subtotal),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      setState(() => _showDiscount = !_showDiscount),
                  tooltip: S.t(context, 'Diskon item'),
                  icon: Icon(
                    Icons.percent,
                    size: 16,
                    color: hasDiscount ? AppColors.error : null,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                QuantityStepper(
                  value: item.quantity,
                  min: 0,
                  max: CartProvider.maxQuantity,
                  compact: true,
                  onChanged: (qty) =>
                      widget.onQuantityChanged(widget.index, qty),
                ),
              ],
            ),
            if (_showDiscount) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Text(
                    '${S.t(context, 'Diskon')} (%)',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 72,
                    height: 34,
                    child: TextField(
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 0,
                        ),
                        suffixText: '%',
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12),
                      controller: _discountCtrl,
                      onChanged: (v) {
                        final pct = (double.tryParse(v) ?? 0)
                            .clamp(0, 100)
                            .toDouble();
                        widget.onDiscountChanged(widget.index, pct);
                      },
                    ),
                  ),
                  const Spacer(),
                  if (hasDiscount)
                    Text(
                      '-${Fmt.rupiah(item.discountAmount)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
