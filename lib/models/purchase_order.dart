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
      // Backend: `quantity` / `unit_price` (`qty` / `cost_price` lama
      // dipertahankan sebagai fallback toleran).
      qty: safeInt(json['quantity'] ?? json['qty'], 1),
      costPrice: safeDouble(json['unit_price'] ?? json['cost_price']),
    );
  }

  /// Kontrak backend: `quantity` + `unit_price`.
  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'quantity': qty,
    'unit_price': costPrice,
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
    // Backend mengirim `purchaseOrderItems` (nama relasi Eloquent);
    // `items` lama dipertahankan sebagai fallback toleran.
    final rawItems = json['purchaseOrderItems'] ?? json['items'];
    return PurchaseOrder(
      id: safeInt(json['id']),
      // Backend: `po_number` (`number` lama jadi fallback).
      number: (json['po_number'] ?? json['number'])?.toString(),
      supplierId: safeInt(json['supplier_id']),
      supplierName:
          json['supplier_name']?.toString() ??
          (supplier is Map ? safeString(supplier['name'], '') : null),
      outletId: safeInt(json['outlet_id']),
      status: safeString(json['status'], 'draft'),
      // Backend: `total_amount` (`total_cost`/`total` lama jadi fallback).
      totalCost: safeDouble(
        json['total_amount'] ?? json['total_cost'] ?? json['total'],
      ),
      items: rawItems is List
          ? (rawItems)
                .whereType<Map<String, dynamic>>()
                .map(PoItem.fromJson)
                .toList()
          : null,
      // Backend: `notes` (`note` lama jadi fallback).
      note: (json['notes'] ?? json['note'])?.toString(),
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

/// Status persis backend (Inggris — JANGAN ubah, backend produksi live):
/// `draft`, `ordered`, `received`, `cancelled`.
/// Nilai Indonesia lama (`dipesan`/`dikirim`/`diterima`) dipetakan toleran
/// agar respons lama/cache tidak merusak UI.
String _normalizePoStatus(String status) {
  switch (status) {
    case 'dipesan':
      return 'ordered';
    case 'dikirim':
      return 'ordered';
    case 'diterima':
      return 'received';
    default:
      return status;
  }
}

/// Label Bahasa Indonesia untuk status PO (kunci Inggris backend).
String poStatusLabel(String status) {
  switch (_normalizePoStatus(status)) {
    case 'draft':
      return 'Draft';
    case 'ordered':
      return 'Dipesan';
    case 'received':
      return 'Diterima';
    case 'cancelled':
      return 'Dibatalkan';
    default:
      return status.isEmpty ? 'Draft' : status;
  }
}

BadgeTone toneForPoStatus(String status) {
  switch (_normalizePoStatus(status)) {
    case 'received':
      return BadgeTone.success;
    case 'ordered':
      return BadgeTone.info;
    case 'cancelled':
      return BadgeTone.error;
    case 'draft':
    default:
      return BadgeTone.neutral;
  }
}
