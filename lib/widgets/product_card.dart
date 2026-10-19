import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// Kartu produk untuk grid POS/katalog.
/// Gambar diambil dari `<host>/storage/<path>` (backend mengirim path
/// relatif) dan selalu punya placeholder saat gagal/kosong.
class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final bool showStock;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.showStock = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = Fmt.productImageUrl(product.image);
    final hasVariants = product.hasVariants;
    final stock = product.sellableStock;
    final outOfStock = !hasVariants && product.currentStock <= 0;
    final lowStock = !hasVariants && !outOfStock && stock <= 10;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _image(imageUrl, theme),
                  if (outOfStock)
                    Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      alignment: Alignment.center,
                      child: Text(
                        'Stok habis',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  if (showStock && !outOfStock)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: hasVariants
                              ? AppColors.primarySoft
                              : lowStock
                              ? AppColors.warningSoft
                              : Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(
                            color: hasVariants
                                ? AppColors.primary
                                : lowStock
                                ? AppColors.warning
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Text(
                          hasVariants
                              ? '${product.variants.length} varian'
                              : '$stock',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: hasVariants
                                ? AppColors.primaryDark
                                : lowStock
                                ? const Color(0xFFB45309)
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      Fmt.rupiah(product.sellingPrice),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _image(String? url, ThemeData theme) {
    if (url == null) return _placeholder(theme);
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _placeholder(theme),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return _placeholder(theme);
      },
    );
  }

  Widget _placeholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      alignment: Alignment.center,
      child: Icon(
        Icons.inventory_2_outlined,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        size: 26,
      ),
    );
  }
}
