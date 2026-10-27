import '../utils/safe_parse.dart';
import '../widgets/common/status_badge.dart';

/// Item retur: produk + qty yang dikembalikan.
class ReturnItem {
  final int productId;
  final String? productName;
  final int qty;

  ReturnItem({required this.productId, this.productName, required this.qty});

  factory ReturnItem.fromJson(Map<String, dynamic> json) {
    final product = json['product'];
    return ReturnItem(
      productId: safeInt(json['product_id']),
      productName:
          json['product_name']?.toString() ??
          (product is Map ? safeString(product['name'], '') : null),
      qty: safeInt(json['qty'] ?? json['quantity'], 1),
    );
  }

  Map<String, dynamic> toJson() => {'product_id': productId, 'qty': qty};
}

/// Retur penjualan: status pending|approved|rejected.
class ReturnOrder {
  final int id;
  final int? orderId;
  final String? orderNumber;
  final int outletId;
  final String status;
  final List<ReturnItem>? items;
  final String? reason;
  final String? createdAt;

  ReturnOrder({
    required this.id,
    this.orderId,
    this.orderNumber,
    required this.outletId,
    required this.status,
    this.items,
    this.reason,
    this.createdAt,
  });

  String get displayNumber => 'RET #$id';

  factory ReturnOrder.fromJson(Map<String, dynamic> json) {
    final order = json['order'];
    return ReturnOrder(
      id: safeInt(json['id']),
      orderId: json['order_id'] == null
          ? null
          : safeInt(json['order_id']),
      orderNumber:
          json['order_number']?.toString() ??
          (order is Map ? order['number']?.toString() : null),
      outletId: safeInt(json['outlet_id']),
      status: safeString(json['status'], 'pending'),
      items: json['items'] is List
          ? (json['items'] as List)
                .whereType<Map<String, dynamic>>()
                .map(ReturnItem.fromJson)
                .toList()
          : null,
      reason: json['reason']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }
}

/// Label Bahasa Indonesia untuk status retur.
String returnStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Menunggu';
    case 'approved':
      return 'Disetujui';
    case 'rejected':
      return 'Ditolak';
    default:
      return status.isEmpty ? 'Menunggu' : status;
  }
}

BadgeTone toneForReturnStatus(String status) {
  switch (status) {
    case 'approved':
      return BadgeTone.success;
    case 'rejected':
      return BadgeTone.error;
    case 'pending':
    default:
      return BadgeTone.warning;
  }
}

/// Transaksi yang ditahan (hold): label + cart JSON + expiry 24 jam.
class HeldOrder {
  final int id;
  final int outletId;
  final String label;
  final Map<String, dynamic>? cart;
  final String? createdAt;
  final String? expiresAt;

  HeldOrder({
    required this.id,
    required this.outletId,
    required this.label,
    this.cart,
    this.createdAt,
    this.expiresAt,
  });

  int get itemCount {
    final c = cart;
    if (c == null) return 0;
    final items = c['items'];
    if (items is List) {
      var total = 0;
      for (final e in items) {
        if (e is Map) {
          final q = e['qty'] ?? e['quantity'];
          if (q is num) {
            total += q.toInt();
          } else {
            total += int.tryParse(q?.toString() ?? '') ?? 0;
          }
        }
      }
      return total;
    }
    return 0;
  }

  factory HeldOrder.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? cart;
    final rawCart = json['cart'];
    if (rawCart is Map<String, dynamic>) {
      cart = rawCart;
    } else if (rawCart is Map) {
      cart = Map<String, dynamic>.from(rawCart);
    }
    return HeldOrder(
      id: safeInt(json['id']),
      outletId: safeInt(json['outlet_id']),
      label: safeString(json['label'], 'Hold #${safeInt(json['id'])}'),
      cart: cart,
      createdAt: json['created_at']?.toString(),
      expiresAt: json['expires_at']?.toString(),
    );
  }
}

/// Jadwal cicilan/DP untuk satu order.
class Installment {
  final int id;
  final int? orderId;
  final String plan;
  final int count;
  final double downPayment;
  final double dueAmount;
  final String? paymentStatus;

  Installment({
    required this.id,
    this.orderId,
    required this.plan,
    required this.count,
    required this.downPayment,
    required this.dueAmount,
    this.paymentStatus,
  });

  factory Installment.fromJson(Map<String, dynamic> json) {
    return Installment(
      id: safeInt(json['id']),
      orderId: json['order_id'] == null
          ? null
          : safeInt(json['order_id']),
      plan: safeString(json['plan'], 'monthly'),
      count: safeInt(json['count'] ?? json['tenor'], 1),
      downPayment: safeDouble(json['down_payment']),
      dueAmount: safeDouble(json['due_amount'] ?? json['remaining']),
      paymentStatus:
          (json['payment_status'] ?? json['status'])?.toString(),
    );
  }
}

/// Label Bahasa Indonesia untuk plan cicilan.
String installmentPlanLabel(String plan) {
  switch (plan) {
    case 'weekly':
      return 'Mingguan';
    case 'biweekly':
      return 'Dua Mingguan';
    case 'monthly':
      return 'Bulanan';
    default:
      return plan.isEmpty ? 'Bulanan' : plan;
  }
}

/// Label Bahasa Indonesia untuk status bayar order.
String paymentStatusLabel(String? status) {
  switch (status) {
    case 'paid':
      return 'Lunas';
    case 'partial':
      return 'Sebagian';
    case 'pending':
      return 'Belum Bayar';
    default:
      return (status == null || status.isEmpty) ? '-' : status;
  }
}
