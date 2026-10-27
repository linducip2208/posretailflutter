import '../utils/safe_parse.dart';

/// Mutasi stok — read-only, ditulis server dari
/// penjualan/pembelian/transfer/opname/penyesuaian.
///
/// Kontrak: `GET /stock-movements` →
/// `{id, product_id, outlet_id, type, qty_before, qty_after,
/// qty_change, reference_type, reference_id, created_at}`.
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
  final String? createdAt;

  static const types = [
    'sale',
    'purchase',
    'transfer_in',
    'transfer_out',
    'opname',
    'adjustment',
  ];

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
    this.createdAt,
  });

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    final product = json['product'];
    return StockMovement(
      id: safeInt(json['id']),
      productId: safeInt(json['product_id']),
      productName: json['product_name']?.toString() ??
          (product is Map ? product['name']?.toString() : null),
      outletId:
          json['outlet_id'] == null ? null : safeInt(json['outlet_id']),
      type: safeString(json['type'], 'adjustment'),
      qtyBefore: json['qty_before'] == null
          ? null
          : safeDouble(json['qty_before']),
      qtyAfter:
          json['qty_after'] == null ? null : safeDouble(json['qty_after']),
      qtyChange: json['qty_change'] == null
          ? null
          : safeDouble(json['qty_change']),
      referenceType: json['reference_type']?.toString(),
      referenceId: json['reference_id']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }

  /// Selisih: pakai `qty_change` bila ada, jika tidak hitung
  /// `qty_after - qty_before`, jika tidak ada keduanya bernilai 0.
  double get delta {
    if (qtyChange != null) return qtyChange!;
    return (qtyAfter ?? 0) - (qtyBefore ?? 0);
  }

  /// Label Bahasa Indonesia per type.
  String get labelId {
    switch (type) {
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
