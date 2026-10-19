import '../utils/safe_parse.dart';

/// Varian produk (mis. ukuran/rasa) — harga & stok per varian dipakai
/// server saat checkout (`product_variant_id`).
class ProductVariant {
  final int id;
  final String name;
  final String? sku;
  final String? barcode;
  final double sellingPrice;
  final int currentStock;

  ProductVariant({
    required this.id,
    required this.name,
    this.sku,
    this.barcode,
    required this.sellingPrice,
    required this.currentStock,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: safeInt(json['id']),
      name: safeString(json['name'], 'Varian'),
      sku: json['sku']?.toString(),
      barcode: json['barcode']?.toString(),
      sellingPrice: safeDouble(json['selling_price']),
      currentStock: safeInt(json['current_stock']),
    );
  }
}

class Product {
  final int id;
  final String name;
  final String? sku;
  final String? barcode;
  final double sellingPrice;
  final double? memberPrice;
  final double? wholesalePrice;
  final int currentStock;
  final String? image;
  final String? categoryName;
  final String? unitName;
  final List<ProductVariant> variants;

  Product({
    required this.id,
    required this.name,
    this.sku,
    this.barcode,
    required this.sellingPrice,
    this.memberPrice,
    this.wholesalePrice,
    required this.currentStock,
    this.image,
    this.categoryName,
    this.unitName,
    this.variants = const [],
  });

  /// Produk dianggap bervarian bila server mengirim daftar varian.
  bool get hasVariants => variants.isNotEmpty;

  /// Total stok yang bisa dijual: varian (bila ada) atau stok produk.
  int get sellableStock => hasVariants
      ? variants.fold(0, (sum, v) => sum + v.currentStock)
      : currentStock;

  factory Product.fromJson(Map<String, dynamic> json) {
    final rawVariants = json['variants'];
    return Product(
      id: safeInt(json['id']),
      name: safeString(json['name']),
      sku: json['sku']?.toString(),
      barcode: json['barcode']?.toString(),
      sellingPrice: safeDouble(json['selling_price']),
      memberPrice: json['member_price'] != null
          ? safeDouble(json['member_price'])
          : null,
      wholesalePrice: json['wholesale_price'] != null
          ? safeDouble(json['wholesale_price'])
          : null,
      currentStock: safeInt(json['current_stock']),
      image: json['image']?.toString(),
      categoryName: json['category'] is Map
          ? safeString(json['category']['name'], '')
          : json['category_name']?.toString(),
      unitName: json['unit'] is Map
          ? safeString(json['unit']['name'], '')
          : json['unit_name']?.toString(),
      variants: rawVariants is List
          ? rawVariants
                .whereType<Map<String, dynamic>>()
                .map(ProductVariant.fromJson)
                .toList()
          : const [],
    );
  }
}
