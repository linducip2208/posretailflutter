import '../utils/safe_parse.dart';
import '../widgets/common/status_badge.dart';

/// Item purchase order: produk + qty + harga beli per unit.
class PoItem {
  final int productId;
  final String? productName;
  final int qty;
  final double costPrice;

  PoItem({
    required this.productId,
    this.productName,
    required this.qty,
    required this.costPrice,
  });

  double get subtotal => qty * costPrice;

  factory PoItem.fromJson(Map<String, dynamic> json) {
    final product = json['product'];
    return PoItem(
      productId: safeInt(json['product_id']),
      productName:
          json['product_name']?.toString() ??
          (product is Map ? safeString(product['name'], '') : null),
      qty: safeInt(json['qty'] ?? json['quantity'], 1),
      costPrice: safeDouble(json['cost_price'] ?? json['unit_price']),
    );
  }

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'qty': qty,
    'cost_price': costPrice,
  };
}

/// Satu entri riwayat status PO (toleran: field boleh hilang).
class PoStatusEntry {
  final String status;
  final String? at;
  final String? by;
  final String? note;

  PoStatusEntry({required this.status, this.at, this.by, this.note});

  factory PoStatusEntry.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    return PoStatusEntry(
      status: safeString(json['status'], 'draft'),
      at: (json['created_at'] ?? json['at'])?.toString(),
      by:
          json['by']?.toString() ??
          (user is Map ? safeString(user['name'], '') : null),
      note: json['note']?.toString(),
    );
  }
}

class PurchaseOrder {
  final int id;
  final String? number;
  final int supplierId;
  final String? supplierName;
  final int outletId;
  final String status;
  final double totalCost;
  final List<PoItem>? items;
  final String? note;
  final String? createdAt;
  final List<PoStatusEntry>? history;

  PurchaseOrder({
    required this.id,
    this.number,
    required this.supplierId,
    this.supplierName,
    required this.outletId,
    required this.status,
    required this.totalCost,
    this.items,
    this.note,
    this.createdAt,
    this.history,
  });

  /// Nomor tampil: pakai `number` bila ada, fallback `PO #id`.
  String get displayNumber =>
      (number == null || number!.isEmpty) ? 'PO #$id' : number!;

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    final supplier = json['supplier'];
    final rawHistory = json['history'] ?? json['status_history'];
    return PurchaseOrder(
      id: safeInt(json['id']),
      number: json['number']?.toString(),
      supplierId: safeInt(json['supplier_id']),
      supplierName:
          json['supplier_name']?.toString() ??
          (supplier is Map ? safeString(supplier['name'], '') : null),
      outletId: safeInt(json['outlet_id']),
      status: safeString(json['status'], 'draft'),
      totalCost: safeDouble(json['total_cost'] ?? json['total']),
      items: json['items'] is List
          ? (json['items'] as List)
                .whereType<Map<String, dynamic>>()
                .map(PoItem.fromJson)
                .toList()
          : null,
      note: json['note']?.toString(),
      createdAt: json['created_at']?.toString(),
      history: rawHistory is List
          ? rawHistory
                .whereType<Map<String, dynamic>>()
                .map(PoStatusEntry.fromJson)
                .toList()
          : null,
    );
  }
}

/// Label Bahasa Indonesia untuk status PO.
String poStatusLabel(String status) {
  switch (status) {
    case 'draft':
      return 'Draft';
    case 'dipesan':
      return 'Dipesan';
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

BadgeTone toneForPoStatus(String status) {
  switch (status) {
    case 'diterima':
      return BadgeTone.success;
    case 'dipesan':
      return BadgeTone.info;
    case 'dikirim':
      return BadgeTone.warning;
    case 'cancelled':
      return BadgeTone.error;
    case 'draft':
    default:
      return BadgeTone.neutral;
  }
}
