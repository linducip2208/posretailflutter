import '../utils/safe_parse.dart';
import '../widgets/common/status_badge.dart';

// ---------------------------------------------------------------------------
// Stock Opname (grup 3 kontrak): buka sesi → isi qty fisik → approve.
// ---------------------------------------------------------------------------

/// Satu baris hasil opname: difference = actual - system (negatif = defisit).
///
/// Backend (StockOpnameItem): `{product_id, system_stock, actual_stock,
/// difference}`. Kunci lama (`system_qty`/`physical_qty`/`diff`) tetap
/// dibaca agar cache lama tidak crash.
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
    final system = safeDouble(
      json['system_stock'] ?? json['system_qty'] ?? json['systemQty'],
    );
    final physical = safeDouble(
      json['actual_stock'] ?? json['physical_qty'] ?? json['physicalQty'],
    );
    final rawDiff =
        json['difference'] ?? json['diff'] ?? json['selisih'];
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

  /// Payload POST /stock-opnames items: `{product_id, actual_stock}`.
  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'actual_stock': physicalQty == physicalQty.toInt()
        ? physicalQty.toInt()
        : physicalQty,
  };
}

class StockOpname {
  final int id;
  final String? opnameNumber;
  final int outletId;
  final String status;
  final String? note;
  final List<OpnameItem>? items;
  final String? createdAt;

  StockOpname({
    required this.id,
    this.opnameNumber,
    required this.outletId,
    required this.status,
    this.note,
    this.items,
    this.createdAt,
  });

  String get displayTitle =>
      (opnameNumber?.isNotEmpty ?? false) ? opnameNumber! : 'Opname #$id';

  /// Ringkasan selisih untuk badge: total surplus & defisit.
  double get totalSurplus => (items ?? const <OpnameItem>[])
      .where((e) => e.diff > 0)
      .fold<double>(0, (s, e) => s + e.diff);

  double get totalDeficit => (items ?? const <OpnameItem>[])
      .where((e) => e.diff < 0)
      .fold<double>(0, (s, e) => s + e.diff);

  factory StockOpname.fromJson(Map<String, dynamic> json) {
    final rawItems =
        json['stockOpnameItems'] ??
        json['stock_opname_items'] ??
        json['items'];
    return StockOpname(
      id: safeInt(json['id']),
      opnameNumber:
          json['opname_number']?.toString() ?? json['number']?.toString(),
      outletId: safeInt(json['outlet_id']),
      status: safeString(json['status'], 'pending'),
      note: json['notes']?.toString() ?? json['note']?.toString(),
      items: rawItems is List
          ? (rawItems)
                .whereType<Map<String, dynamic>>()
                .map(OpnameItem.fromJson)
                .toList()
          : null,
      createdAt: json['created_at']?.toString(),
    );
  }
}

/// Label Bahasa Indonesia untuk status opname.
///
/// Backend live: `pending` → `completed` (POST .../approve).
/// Status lama (`draft|counted|approved|cancelled`) tetap dipetakan
/// agar tidak crash bila muncul dari cache.
String opnameStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Menunggu';
    case 'completed':
    case 'approved':
      return 'Selesai';
    case 'draft':
      return 'Draft';
    case 'counted':
      return 'Dihitung';
    case 'cancelled':
      return 'Dibatalkan';
    default:
      return status.isEmpty ? 'Menunggu' : status;
  }
}

BadgeTone toneForOpnameStatus(String status) {
  switch (status) {
    case 'completed':
    case 'approved':
      return BadgeTone.success;
    case 'pending':
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
      qty: safeInt(json['quantity'] ?? json['qty'], 1),
    );
  }

  /// Payload POST /stock-transfers items: `{product_id, quantity}`.
  Map<String, dynamic> toJson() => {'product_id': productId, 'quantity': qty};
}

class StockTransfer {
  final int id;
  final String? transferNumber;
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
    this.transferNumber,
    required this.fromOutletId,
    required this.toOutletId,
    this.fromName,
    this.toName,
    required this.status,
    this.items,
    this.note,
    this.createdAt,
  });

  String get displayTitle => (transferNumber?.isNotEmpty ?? false)
      ? transferNumber!
      : 'Transfer #$id';

  String routeLabel() {
    final from = (fromName?.isNotEmpty ?? false) ? fromName! : 'Outlet #$fromOutletId';
    final to = (toName?.isNotEmpty ?? false) ? toName! : 'Outlet #$toOutletId';
    return '$from → $to';
  }

  int get totalQty =>
      (items ?? const <TransferItem>[]).fold<int>(0, (s, e) => s + e.qty);

  factory StockTransfer.fromJson(Map<String, dynamic> json) {
    final from =
        json['fromOutlet'] ?? json['from_outlet'] ?? json['fromOutlet'];
    final to = json['toOutlet'] ?? json['to_outlet'] ?? json['toOutlet'];
    final rawItems =
        json['stockTransferItems'] ??
        json['stock_transfer_items'] ??
        json['items'];
    return StockTransfer(
      id: safeInt(json['id']),
      transferNumber:
          json['transfer_number']?.toString() ?? json['number']?.toString(),
      fromOutletId: safeInt(json['from_outlet_id']),
      toOutletId: safeInt(json['to_outlet_id']),
      fromName:
          json['from_name']?.toString() ??
          (from is Map ? safeString(from['name'], '') : null),
      toName:
          json['to_name']?.toString() ??
          (to is Map ? safeString(to['name'], '') : null),
      status: safeString(json['status'], 'draft'),
      items: rawItems is List
          ? (rawItems)
                .whereType<Map<String, dynamic>>()
                .map(TransferItem.fromJson)
                .toList()
          : null,
      note: json['notes']?.toString() ?? json['note']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }
}

/// Backend live: `draft` → `sent` (POST .../send) → `received`
/// (POST .../receive). Kunci lama (`dikirim`/`diterima`) tetap dipetakan.
String transferStatusLabel(String status) {
  switch (status) {
    case 'draft':
      return 'Draft';
    case 'sent':
    case 'dikirim':
      return 'Dikirim';
    case 'received':
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
    case 'received':
    case 'diterima':
      return BadgeTone.success;
    case 'sent':
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
  final String? code;
  final int? outletId;
  final int? unitId;
  final String? unit;
  final double stock;
  final double minStock;
  final double costPerUnit;

  RawMaterial({
    required this.id,
    required this.name,
    this.code,
    this.outletId,
    this.unitId,
    this.unit,
    required this.stock,
    required this.minStock,
    required this.costPerUnit,
  });

  bool get isLow => stock <= minStock;

  /// Backend (RawMaterial): `{name, code, outlet_id, unit_id,
  /// cost_per_unit, current_stock, min_stock}` + relasi `unit: {name}`.
  /// Kunci lama (`unit` string, `stock`) tetap dibaca.
  factory RawMaterial.fromJson(Map<String, dynamic> json) {
    final unit = json['unit'];
    return RawMaterial(
      id: safeInt(json['id']),
      name: safeString(json['name'], 'Bahan #${safeInt(json['id'])}'),
      code: json['code']?.toString(),
      outletId: json['outlet_id'] == null
          ? null
          : safeInt(json['outlet_id']),
      unitId: json['unit_id'] == null ? null : safeInt(json['unit_id']),
      unit:
          json['unit_name']?.toString() ??
          (unit is Map
              ? safeString(unit['name'], '')
              : unit?.toString()),
      stock: safeDouble(
        json['current_stock'] ?? json['stock'] ?? json['quantity'],
      ),
      minStock: safeDouble(json['min_stock'] ?? json['minStock']),
      costPerUnit: safeDouble(
        json['cost_per_unit'] ?? json['costPerUnit'] ?? json['cost'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (code != null && code!.isNotEmpty) 'code': code,
    if (outletId != null) 'outlet_id': outletId,
    if (unitId != null) 'unit_id': unitId,
    'current_stock': stock,
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
    final material =
        json['rawMaterial'] ?? json['raw_material'] ?? json['material'];
    return RecipeItem(
      rawMaterialId: safeInt(json['raw_material_id']),
      rawMaterialName:
          json['raw_material_name']?.toString() ??
          (material is Map ? safeString(material['name'], '') : null),
      qty: safeDouble(json['quantity'] ?? json['qty']),
    );
  }

  /// Payload resep: `{raw_material_id, quantity}` (kolom recipe_items).
  Map<String, dynamic> toJson() =>
      {'raw_material_id': rawMaterialId, 'quantity': qty};
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
