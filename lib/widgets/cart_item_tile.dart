import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../l10n/s.dart';
import '../../providers/cart_provider.dart';

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
    _discountCtrl =
        TextEditingController(text: '${widget.item.discountPercent}');
  }

  @override
  void didUpdateWidget(covariant CartItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.discountPercent != widget.item.discountPercent &&
        _discountCtrl.text != '${widget.item.discountPercent}') {
      _discountCtrl.text = '${widget.item.discountPercent}';
    }
  }

  @override
  void dispose() {
    _discountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
    final hasDiscount = widget.item.discountPercent > 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.item.product.name,
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: widget.onRemove,
                  child: Icon(Icons.close, size: 16, color: Colors.red.shade300),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(format.format(widget.item.unitPrice), style: theme.textTheme.bodySmall),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => widget.onQuantityChanged(widget.index, widget.item.quantity - 1),
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.dividerColor),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.remove, size: 16),
                      ),
                    ),
                    Container(
                      width: 32,
                      alignment: Alignment.center,
                      child: Text('${widget.item.quantity}', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    InkWell(
                      onTap: () => widget.onQuantityChanged(widget.index, widget.item.quantity + 1),
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.dividerColor),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.add, size: 16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => setState(() => _showDiscount = !_showDiscount),
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          border: Border.all(color: hasDiscount ? Colors.red.shade300 : theme.dividerColor),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(Icons.percent, size: 14, color: hasDiscount ? Colors.red.shade400 : Colors.grey),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (_showDiscount) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('${S.t(context, 'Diskon')}:', style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 60,
                    height: 28,
                    child: TextField(
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                        border: OutlineInputBorder(),
                        suffixText: '%',
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 11),
                      controller: _discountCtrl,
                      onChanged: (v) {
                        final pct = double.tryParse(v) ?? 0;
                        widget.onDiscountChanged(widget.index, pct);
                      },
                    ),
                  ),
                  const Spacer(),
                  Text(format.format(widget.item.subtotal),
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
