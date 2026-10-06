import '../utils/safe_parse.dart';

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
  final bool hasVariants;

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
    this.hasVariants = false,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    final variants = json['variants'];
    return Product(
      id: safeInt(json['id']),
      name: safeString(json['name']),
      sku: json['sku']?.toString(),
      barcode: json['barcode']?.toString(),
      sellingPrice: safeDouble(json['selling_price']),
      memberPrice: json['member_price'] != null ? safeDouble(json['member_price']) : null,
      wholesalePrice: json['wholesale_price'] != null ? safeDouble(json['wholesale_price']) : null,
      currentStock: safeInt(json['current_stock']),
      image: json['image']?.toString(),
      categoryName: json['category'] is Map
          ? safeString(json['category']['name'], '')
          : (json['category_name'] != null ? safeString(json['category_name']) : null),
      unitName: json['unit'] is Map
          ? safeString(json['unit']['name'], '')
          : (json['unit_name'] != null ? safeString(json['unit_name']) : null),
      // Backend tidak mengirim has_variants — turunkan dari relasi variants bila ada.
      hasVariants: json['has_variants'] == true ||
          json['has_variants'] == 1 ||
          (variants is List && variants.isNotEmpty),
    );
  }

  Map<String, dynamic> toCartItem() => {
    'id': id,
    'name': name,
    'price': sellingPrice,
    'quantity': 1,
  };
}
