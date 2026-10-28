import '../utils/safe_parse.dart';

/// Supplier (pemasok barang): model toleran — field hilang/null
/// dinormalisasi ke nilai aman tanpa throw.
class Supplier {
  final int id;
  final String name;
  final String? contactPerson;
  final String? phone;
  final String? email;
  final String? address;
  final int? poCount;
  final String? createdAt;

  /// Riwayat purchase order bila disertakan server di respons detail.
  /// Kosong bila server tidak mengirimkannya (bukan data palsu).
  final List<SupplierPo> purchaseOrders;

  Supplier({
    required this.id,
    required this.name,
    this.contactPerson,
    this.phone,
    this.email,
    this.address,
    this.poCount,
    this.createdAt,
    this.purchaseOrders = const [],
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    final dynamic posRaw = json['purchase_orders'] ?? json['pos'];
    List<SupplierPo> pos = [];
    if (posRaw is List) {
      pos = posRaw
          .whereType<Map<String, dynamic>>()
          .map(SupplierPo.fromJson)
          .toList();
    }
    int? count;
    // Backend memakai `loadCount(['purchaseOrders as po_count'])` → `po_count`.
    final dynamic countRaw =
        json['po_count'] ??
        json['purchase_orders_count'] ??
        json['pos_count'];
    if (countRaw != null) {
      count = safeInt(countRaw);
    } else if (posRaw is List) {
      count = pos.length;
    }
    return Supplier(
      id: safeInt(json['id']),
      name: safeString(json['name']),
      contactPerson: _optString(json['contact_person']),
      phone: _optString(json['phone']),
      email: _optString(json['email']),
      address: _optString(json['address']),
      poCount: count,
      createdAt: json['created_at']?.toString(),
      purchaseOrders: pos,
    );
  }
}

/// Satu baris riwayat purchase order milik supplier.
/// Semua field opsional — tampilkan '-' bila server tidak mengirimnya.
class SupplierPo {
  final int id;
  final String number;
  final String? status;
  final double? total;
  final String? date;

  SupplierPo({
    required this.id,
    required this.number,
    this.status,
    this.total,
    this.date,
  });

  factory SupplierPo.fromJson(Map<String, dynamic> json) {
    final id = safeInt(json['id']);
    var number = safeString(
      json['number'] ??
          json['po_number'] ??
          json['code'] ??
          json['reference'],
    );
    if (number.isEmpty && id > 0) number = 'PO #$id';
    final dynamic totalRaw =
        json['total'] ?? json['grand_total'] ?? json['total_amount'];
    return SupplierPo(
      id: id,
      number: number,
      status: _optString(json['status']),
      total: totalRaw == null ? null : safeDouble(totalRaw),
      date: _optString(
        json['date'] ?? json['order_date'] ?? json['created_at'],
      ),
    );
  }
}

String? _optString(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}
