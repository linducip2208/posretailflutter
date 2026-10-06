import 'package:flutter/material.dart';
import '../../models/product.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = product.image != null && product.image!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.all(4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 80,
              child: hasImage
                  ? Image.network(
                      product.image!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, error, stackTrace) => Container(
                        color: Colors.grey.shade100,
                        child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 32),
                      ),
                    )
                  : Container(
                      color: Colors.grey.shade100,
                      child: const Icon(Icons.inventory_2, color: Colors.grey, size: 32),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Rp ${product.sellingPrice.toStringAsFixed(0)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        product.sku ?? '',
                        style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: product.currentStock > 10 ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${product.currentStock}',
                          style: TextStyle(
                            fontSize: 10,
                            color: product.currentStock > 10 ? Colors.green.shade700 : Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
