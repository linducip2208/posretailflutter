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
    double asDouble(dynamic value) => double.tryParse(value?.toString() ?? '') ?? 0;

    return Product(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      sku: json['sku'],
      barcode: json['barcode'],
      sellingPrice: asDouble(json['selling_price']),
      memberPrice: json['member_price'] != null ? asDouble(json['member_price']) : null,
      wholesalePrice: json['wholesale_price'] != null ? asDouble(json['wholesale_price']) : null,
      currentStock: int.tryParse(json['current_stock']?.toString() ?? '0') ?? 0,
      image: json['image'],
      categoryName: json['category'] != null ? json['category']['name'] : null,
      unitName: json['unit'] != null ? json['unit']['name'] : null,
      hasVariants: json['has_variants'] == true || json['has_variants'] == 1,
    );
  }

  Map<String, dynamic> toCartItem() => {
    'id': id,
    'name': name,
    'price': sellingPrice,
    'quantity': 1,
  };
}
