import '../utils/safe_parse.dart';
import '../widgets/common/status_badge.dart';

// ---------------------------------------------------------------------------
// Stock Opname (grup 3 kontrak): buka sesi → isi qty fisik → approve.
// ---------------------------------------------------------------------------

/// Satu baris hasil opname: selisih = fisik - sistem (negatif = defisit).
class OpnameItem {
  final int productId;
  final String? productName;
  final double systemQty;
  final double physicalQty;
  final double diff;

  OpnameItem({
    required this.productId,
    this.productName,
    required this.systemQty,
    required this.physicalQty,
    required this.diff,
  });

  factory OpnameItem.fromJson(Map<String, dynamic> json) {
    final product = json['product'];
    final system = safeDouble(json['system_qty'] ?? json['systemQty']);
    final physical = safeDouble(json['physical_qty'] ?? json['physicalQty']);
    final rawDiff = json['diff'] ?? json['selisih'];
    return OpnameItem(
      productId: safeInt(json['product_id']),
      productName:
          json['product_name']?.toString() ??
          (product is Map ? safeString(product['name'], '') : null),
      systemQty: system,
      physicalQty: physical,
      diff: rawDiff == null ? physical - system : safeDouble(rawDiff),
    );
  }

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'physical_qty': physicalQty,
  };
}

class StockOpname {
  final int id;
  final int outletId;
  final String status;
  final String? note;
  final List<OpnameItem>? items;
  final String? createdAt;

  StockOpname({
    required this.id,
    required this.outletId,
    required this.status,
    this.note,
    this.items,
    this.createdAt,
  });

  String get displayTitle => 'Opname #$id';

  /// Ringkasan selisih untuk badge: total surplus & defisit.
  double get totalSurplus => (items ?? const <OpnameItem>[])
      .where((e) => e.diff > 0)
      .fold<double>(0, (s, e) => s + e.diff);

  double get totalDeficit => (items ?? const <OpnameItem>[])
      .where((e) => e.diff < 0)
      .fold<double>(0, (s, e) => s + e.diff);

  factory StockOpname.fromJson(Map<String, dynamic> json) {
    return StockOpname(
      id: safeInt(json['id']),
      outletId: safeInt(json['outlet_id']),
      status: safeString(json['status'], 'draft'),
      note: json['note']?.toString(),
      items: json['items'] is List
          ? (json['items'] as List)
                .whereType<Map<String, dynamic>>()
                .map(OpnameItem.fromJson)
                .toList()
          : null,
      createdAt: json['created_at']?.toString(),
    );
  }
}

/// Label Bahasa Indonesia untuk status opname.
String opnameStatusLabel(String status) {
  switch (status) {
    case 'draft':
      return 'Draft';
    case 'counted':
      return 'Dihitung';
    case 'approved':
      return 'Disetujui';
    case 'cancelled':
      return 'Dibatalkan';
    default:
      return status.isEmpty ? 'Draft' : status;
  }
}

BadgeTone toneForOpnameStatus(String status) {
  switch (status) {
    case 'approved':
      return BadgeTone.success;
    case 'counted':
      return BadgeTone.info;
    case 'cancelled':
      return BadgeTone.error;
    case 'draft':
    default:
      return BadgeTone.neutral;
  }
}

// ---------------------------------------------------------------------------
// Transfer Stok (grup 4 kontrak): draft → dikirim → diterima.
// ---------------------------------------------------------------------------

class TransferItem {
  final int productId;
  final String? productName;
  final int qty;

  TransferItem({required this.productId, this.productName, required this.qty});

  factory TransferItem.fromJson(Map<String, dynamic> json) {
    final product = json['product'];
    return TransferItem(
      productId: safeInt(json['product_id']),
      productName:
          json['product_name']?.toString() ??
          (product is Map ? safeString(product['name'], '') : null),
      qty: safeInt(json['qty'] ?? json['quantity'], 1),
    );
  }

  Map<String, dynamic> toJson() => {'product_id': productId, 'qty': qty};
}

class StockTransfer {
  final int id;
  final int fromOutletId;
  final int toOutletId;
  final String? fromName;
  final String? toName;
  final String status;
  final List<TransferItem>? items;
  final String? note;
  final String? createdAt;

  StockTransfer({
    required this.id,
    required this.fromOutletId,
    required this.toOutletId,
    this.fromName,
    this.toName,
    required this.status,
    this.items,
    this.note,
    this.createdAt,
  });

  String get displayTitle => 'Transfer #$id';

  String routeLabel() {
    final from = (fromName?.isNotEmpty ?? false) ? fromName! : 'Outlet #$fromOutletId';
    final to = (toName?.isNotEmpty ?? false) ? toName! : 'Outlet #$toOutletId';
    return '$from → $to';
  }

  int get totalQty =>
      (items ?? const <TransferItem>[]).fold<int>(0, (s, e) => s + e.qty);

  factory StockTransfer.fromJson(Map<String, dynamic> json) {
    final from = json['from_outlet'] ?? json['fromOutlet'];
    final to = json['to_outlet'] ?? json['toOutlet'];
    return StockTransfer(
      id: safeInt(json['id']),
      fromOutletId: safeInt(json['from_outlet_id']),
      toOutletId: safeInt(json['to_outlet_id']),
      fromName:
          json['from_name']?.toString() ??
          (from is Map ? safeString(from['name'], '') : null),
      toName:
          json['to_name']?.toString() ??
          (to is Map ? safeString(to['name'], '') : null),
      status: safeString(json['status'], 'draft'),
      items: json['items'] is List
          ? (json['items'] as List)
                .whereType<Map<String, dynamic>>()
                .map(TransferItem.fromJson)
                .toList()
          : null,
      note: json['note']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }
}

String transferStatusLabel(String status) {
  switch (status) {
    case 'draft':
      return 'Draft';
    case 'dikirim':
      return 'Dikirim';
    case 'diterima':
      return 'Diterima';
    case 'cancelled':
      return 'Dibatalkan';
    default:
      return status.isEmpty ? 'Draft' : status;
  }
}

BadgeTone toneForTransferStatus(String status) {
  switch (status) {
    case 'diterima':
      return BadgeTone.success;
    case 'dikirim':
      return BadgeTone.warning;
    case 'cancelled':
      return BadgeTone.error;
    case 'draft':
    default:
      return BadgeTone.neutral;
  }
}

// ---------------------------------------------------------------------------
// Bahan Baku & Resep (grup 10 kontrak).
// ---------------------------------------------------------------------------

class RawMaterial {
  final int id;
  final String name;
  final String? unit;
  final double stock;
  final double minStock;
  final double costPerUnit;

  RawMaterial({
    required this.id,
    required this.name,
    this.unit,
    required this.stock,
    required this.minStock,
    required this.costPerUnit,
  });

  bool get isLow => stock <= minStock;

  factory RawMaterial.fromJson(Map<String, dynamic> json) {
    return RawMaterial(
      id: safeInt(json['id']),
      name: safeString(json['name'], 'Bahan #${safeInt(json['id'])}'),
      unit: json['unit']?.toString(),
      stock: safeDouble(json['stock']),
      minStock: safeDouble(json['min_stock'] ?? json['minStock']),
      costPerUnit: safeDouble(
        json['cost_per_unit'] ?? json['costPerUnit'] ?? json['cost'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (unit != null && unit!.isNotEmpty) 'unit': unit,
    'stock': stock,
    'min_stock': minStock,
    'cost_per_unit': costPerUnit,
  };
}

class RecipeItem {
  final int rawMaterialId;
  final String? rawMaterialName;
  final double qty;

  RecipeItem({required this.rawMaterialId, this.rawMaterialName, required this.qty});

  factory RecipeItem.fromJson(Map<String, dynamic> json) {
    final material = json['raw_material'] ?? json['material'];
    return RecipeItem(
      rawMaterialId: safeInt(json['raw_material_id']),
      rawMaterialName:
          json['raw_material_name']?.toString() ??
          (material is Map ? safeString(material['name'], '') : null),
      qty: safeDouble(json['qty'] ?? json['quantity']),
    );
  }

  Map<String, dynamic> toJson() => {'raw_material_id': rawMaterialId, 'qty': qty};
}

class Recipe {
  final int? productId;
  final String? productName;
  final List<RecipeItem> items;

  Recipe({this.productId, this.productName, required this.items});

  factory Recipe.fromJson(Map<String, dynamic> json) {
    final product = json['product'];
    final rawItems = json['items'];
    return Recipe(
      productId: json['product_id'] == null
          ? null
          : safeInt(json['product_id']),
      productName:
          json['product_name']?.toString() ??
          (product is Map ? safeString(product['name'], '') : null),
      items: rawItems is List
          ? rawItems
                .whereType<Map<String, dynamic>>()
                .map(RecipeItem.fromJson)
                .toList()
          : const [],
    );
  }
}
