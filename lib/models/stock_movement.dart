import '../utils/safe_parse.dart';

/// Mutasi stok — read-only, ditulis server dari
/// penjualan/pembelian/transfer/opname.
///
/// Kontrak backend live (`GET /stock-movements`):
/// `{id, product_id, outlet_id, type: in|out, quantity,
/// reference_type, reference_id, notes, created_at}` + relasi
/// `product`/`outlet`. Filter: `product_id`, `type=in|out`,
/// `outlet_id`, `per_page`.
///
/// Kunci lama (`qty_change`/`qty_before`/`qty_after`, type
/// `sale|purchase|...`) tetap dibaca agar tidak crash.
class StockMovement {
  final int id;
  final int productId;
  final String? productName;
  final int? outletId;
  final String type;
  final double? qtyBefore;
  final double? qtyAfter;
  final double? qtyChange;
  final String? referenceType;
  final String? referenceId;
  final String? notes;
  final String? createdAt;

  /// Type yang didukung backend sebagai filter.
  static const types = ['in', 'out'];

  StockMovement({
    required this.id,
    required this.productId,
    this.productName,
    this.outletId,
    required this.type,
    this.qtyBefore,
    this.qtyAfter,
    this.qtyChange,
    this.referenceType,
    this.referenceId,
    this.notes,
    this.createdAt,
  });

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    final product = json['product'];
    final change =
        json['qty_change'] ??
        json['quantity'] ??
        json['qty'] ??
        json['qtyChange'];
    return StockMovement(
      id: safeInt(json['id']),
      productId: safeInt(json['product_id']),
      productName: json['product_name']?.toString() ??
          (product is Map ? product['name']?.toString() : null),
      outletId:
          json['outlet_id'] == null ? null : safeInt(json['outlet_id']),
      type: safeString(json['type'], 'in'),
      qtyBefore: json['qty_before'] == null
          ? null
          : safeDouble(json['qty_before']),
      qtyAfter:
          json['qty_after'] == null ? null : safeDouble(json['qty_after']),
      qtyChange: change == null ? null : safeDouble(change),
      referenceType: json['reference_type']?.toString(),
      referenceId: json['reference_id']?.toString(),
      notes: json['notes']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }

  /// Selisih bertanda: pakai `qty_after - qty_before` bila rentang
  /// tersedia; jika tidak, pakai `qty_change`/`quantity` (dinegatifkan
  /// untuk type `out` bila nilainya positif).
  double get delta {
    if (qtyAfter != null || qtyBefore != null) {
      return (qtyAfter ?? 0) - (qtyBefore ?? 0);
    }
    final v = qtyChange ?? 0;
    return (type == 'out' && v > 0) ? -v : v;
  }

  /// Label Bahasa Indonesia per type.
  String get labelId {
    switch (type) {
      case 'in':
        return 'Masuk';
      case 'out':
        return 'Keluar';
      case 'sale':
        return 'Penjualan';
      case 'purchase':
        return 'Pembelian';
      case 'transfer_in':
        return 'Transfer Masuk';
      case 'transfer_out':
        return 'Transfer Keluar';
      case 'opname':
        return 'Opname';
      case 'adjustment':
        return 'Penyesuaian';
      default:
        return type;
    }
  }
}
