import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/s.dart';
import '../../models/product.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/product_card.dart';

/// Tab Produk: katalog outlet aktif (read-only sesuai kemampuan API).
/// Tambah/ubah/hapus produk dan stok dilakukan dari panel admin web.
class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ProductProvider>();
      provider.setOutletId(context.read<AuthProvider>().currentOutletId);
      provider.loadCategories();
      provider.refresh();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final position = _scrollCtrl.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      context.read<ProductProvider>().loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final provider = context.read<ProductProvider>();
      provider.setSearch(value.trim());
      provider.refresh();
    });
  }

  Future<void> _refresh() async {
    final provider = context.read<ProductProvider>();
    provider.setOutletId(context.read<AuthProvider>().currentOutletId);
    await provider.refresh();
  }

  void _showInfo() {
    showAppSnackbar(
      context,
      S.tn(
        context,
        'Katalog bersifat baca-saja. Tambah/ubah produk dan stok dilakukan dari panel admin web.',
      ),
      type: SnackType.info,
      duration: const Duration(seconds: 5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(S.t(context, 'Produk')),
        actions: [
          IconButton(
            tooltip: S.t(context, 'Info produk'),
            onPressed: _showInfo,
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            tooltip: S.t(context, 'Muat ulang'),
            onPressed: provider.isLoading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: S.t(context, 'Cari produk (nama/SKU/barcode)...'),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          final p = context.read<ProductProvider>();
                          p.setSearch('');
                          p.refresh();
                        },
                      ),
              ),
              onChanged: _onSearchChanged,
              onSubmitted: (v) {
                _debounce?.cancel();
                final p = context.read<ProductProvider>();
                p.setSearch(v.trim());
                p.refresh();
              },
            ),
          ),
          if (provider.categories.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ChoiceChip(
                      label: Text(S.t(context, 'Semua')),
                      selected: provider.categoryId == null,
                      onSelected: (_) => provider.setCategory(null),
                    ),
                  ),
                  for (final category in provider.categories)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: ChoiceChip(
                        label: Text(category.name),
                        selected: provider.categoryId == category.id,
                        onSelected: (_) => provider.setCategory(category.id),
                      ),
                    ),
                ],
              ),
            ),
          if (provider.usingOfflineCache)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                S.t(
                  context,
                  'Menampilkan cache offline. Data bisa belum terbaru.',
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          Expanded(child: _buildBody(provider)),
        ],
      ),
    );
  }

  Widget _buildBody(ProductProvider provider) {
    if (provider.isLoading && provider.products.isEmpty) {
      return const LoadingSkeleton(items: 6, itemHeight: 72);
    }
    if (provider.error != null && provider.products.isEmpty) {
      return ErrorState(
        message: provider.error!,
        icon: Icons.inventory_2_outlined,
        onRetry: _refresh,
      );
    }
    if (provider.products.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: S.t(context, 'Tidak ada produk'),
        message: S.t(
          context,
          'Coba kata kunci lain atau ubah filter kategori.',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(AppSpacing.md),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 170,
                mainAxisExtent: 168,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => ProductCard(
                  product: provider.products[i],
                  onTap: () => _showProductDetail(provider.products[i]),
                ),
                childCount: provider.products.length,
              ),
            ),
          ),
          if (provider.isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (!provider.hasMore && provider.total > 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                child: Center(
                  child: Text(
                    '${provider.total} ${S.t(context, 'produk')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showProductDetail(Product product) async {
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              product.name,
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                if (product.categoryName != null &&
                    product.categoryName!.isNotEmpty)
                  StatusBadge(product.categoryName!, tone: BadgeTone.info),
                if (product.sku != null && product.sku!.isNotEmpty)
                  StatusBadge('SKU ${product.sku}', tone: BadgeTone.neutral),
                if (product.barcode != null && product.barcode!.isNotEmpty)
                  StatusBadge(product.barcode!, tone: BadgeTone.neutral),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _detailRow(
              S.t(sheetContext, 'Harga Jual'),
              Fmt.rupiah(product.sellingPrice),
              emphasize: true,
            ),
            if (product.memberPrice != null && product.memberPrice! > 0)
              _detailRow(
                S.t(sheetContext, 'Harga Member'),
                Fmt.rupiah(product.memberPrice!),
              ),
            if (product.wholesalePrice != null && product.wholesalePrice! > 0)
              _detailRow(
                S.t(sheetContext, 'Harga Grosir'),
                Fmt.rupiah(product.wholesalePrice!),
              ),
            _detailRow(
              S.t(sheetContext, 'Stok'),
              product.hasVariants
                  ? '${product.sellableStock} ${S.t(sheetContext, '(total varian)')}'
                  : '${product.currentStock}${product.unitName != null ? ' ${product.unitName}' : ''}',
            ),
            if (product.hasVariants) ...[
              const Divider(height: AppSpacing.xl),
              Text(
                '${S.t(sheetContext, 'Varian')} (${product.variants.length})',
                style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
              ),
              const SizedBox(height: AppSpacing.sm),
              Card(
                child: Column(
                  children: [
                    for (final v in product.variants)
                      ListTile(
                        dense: true,
                        title: Text(
                          v.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${S.t(sheetContext, 'Stok')}: ${v.currentStock}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        trailing: Text(
                          Fmt.rupiah(
                            v.sellingPrice > 0
                                ? v.sellingPrice
                                : product.sellingPrice,
                          ),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                S.t(
                  sheetContext,
                  'Data bersumber dari server outlet aktif. Perubahan produk/stok hanya dari panel admin web.',
                ),
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool emphasize = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: emphasize ? 15 : 12.5,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              color: emphasize ? theme.colorScheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}
