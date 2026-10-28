import '../utils/safe_parse.dart';
import '../widgets/common/status_badge.dart';

/// Item retur: backend memakai `quantity` (+ `unit_price`, `subtotal`) dan
/// relasi bernama `returnItems`. Alias lama (`qty`, `items`) tetap dibaca
/// agar payload lama tidak pecah.
class ReturnItem {
  final int productId;
  final String? productName;
  final int qty;
  final double? unitPrice;
  final double? subtotal;

  ReturnItem({
    required this.productId,
    this.productName,
    required this.qty,
    this.unitPrice,
    this.subtotal,
  });

  factory ReturnItem.fromJson(Map<String, dynamic> json) {
    final product = json['product'];
    double? optDouble(dynamic v) {
      if (v == null) return null;
      final parsed = double.tryParse(v.toString());
      return parsed;
    }

    return ReturnItem(
      productId: safeInt(json['product_id']),
      productName:
          json['product_name']?.toString() ??
          (product is Map ? safeString(product['name'], '') : null),
      qty: safeInt(json['quantity'] ?? json['qty'], 1),
      unitPrice: optDouble(json['unit_price']),
      subtotal: optDouble(json['subtotal']),
    );
  }

  /// Backend: `items.*.quantity` (bukan `qty`).
  Map<String, dynamic> toJson() => {'product_id': productId, 'quantity': qty};
}

/// Retur penjualan.
///
/// Backend: `POST /returns` membuat status `pending`,
/// `POST /returns/{id}/approve` → `completed`,
/// `POST /returns/{id}/reject {reason?}` → `rejected`.
/// Filter status `index` generik (`where status`), jadi `rejected`
/// didukung server; daftar juga memakainya sebagai filter.
class ReturnOrder {
  final int id;
  final int? orderId;
  final String? orderNumber;
  final String? returnNumber;
  final int outletId;
  final String status;
  final double totalAmount;
  final List<ReturnItem>? items;
  final String? reason;
  final String? createdAt;

  ReturnOrder({
    required this.id,
    this.orderId,
    this.orderNumber,
    this.returnNumber,
    required this.outletId,
    required this.status,
    this.totalAmount = 0,
    this.items,
    this.reason,
    this.createdAt,
  });

  String get displayNumber =>
      (returnNumber != null && returnNumber!.isNotEmpty)
      ? returnNumber!
      : 'RET #$id';

  factory ReturnOrder.fromJson(Map<String, dynamic> json) {
    final order = json['order'];
    final rawItems = json['returnItems'] ?? json['return_items'] ?? json['items'];
    return ReturnOrder(
      id: safeInt(json['id']),
      orderId: json['order_id'] == null
          ? null
          : safeInt(json['order_id']),
      orderNumber:
          json['order_number']?.toString() ??
          (order is Map
              ? (order['order_number'] ?? order['number'])?.toString()
              : null),
      returnNumber: json['return_number']?.toString(),
      outletId: safeInt(json['outlet_id']),
      status: safeString(json['status'], 'pending'),
      totalAmount: safeDouble(json['total_amount']),
      items: rawItems is List
          ? rawItems
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
    case 'completed':
      return 'Selesai';
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
    case 'completed':
    case 'approved':
      return BadgeTone.success;
    case 'rejected':
      return BadgeTone.error;
    case 'pending':
    default:
      return BadgeTone.warning;
  }
}

/// Satu baris item keranjang yang ditahan.
/// Backend tidak memvalidasi isi tiap item; terima varian bentuk umum.
class HeldItem {
  final int productId;
  final String? name;
  final double price;
  final int qty;

  HeldItem({
    required this.productId,
    this.name,
    this.price = 0,
    required this.qty,
  });

  factory HeldItem.fromJson(Map<String, dynamic> json) {
    return HeldItem(
      productId: safeInt(json['product_id'] ?? json['id']),
      name: (json['name'] ?? json['product_name'])?.toString(),
      price: safeDouble(json['price'] ?? json['unit_price']),
      qty: safeInt(json['qty'] ?? json['quantity'], 1),
    );
  }

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    if (name != null && name!.isNotEmpty) 'name': name,
    'price': price,
    'qty': qty,
  };
}

/// Transaksi yang ditahan (hold).
///
/// Backend (produksi): `GET|POST /held-carts`, body `{outlet_id,
/// customer_id?, label?, items[]}`, respons `{data}` berisi `items`
/// (array top-level, bukan `cart`) dan TANPA `expires_at`.
/// Bentuk lama (`cart: {items: [...]}`) tetap dibaca sebagai fallback.
class HeldOrder {
  final int id;
  final int outletId;
  final int? customerId;
  final String label;
  final List<HeldItem> items;
  final String? createdAt;
  final String? expiresAt;

  HeldOrder({
    required this.id,
    required this.outletId,
    this.customerId,
    required this.label,
    this.items = const [],
    this.createdAt,
    this.expiresAt,
  });

  int get itemCount => items.fold(0, (s, e) => s + e.qty);

  factory HeldOrder.fromJson(Map<String, dynamic> json) {
    final dynamic rawItems = json['items'];
    final dynamic rawCart = json['cart'];
    List<HeldItem> items = const [];
    if (rawItems is List) {
      items = rawItems
          .whereType<Map<String, dynamic>>()
          .map(HeldItem.fromJson)
          .toList();
    } else if (rawCart is Map) {
      final inner = rawCart['items'];
      if (inner is List) {
        items = inner
            .whereType<Map<String, dynamic>>()
            .map(HeldItem.fromJson)
            .toList();
      }
    }
    final dynamic rawCustomer = json['customer'];
    return HeldOrder(
      id: safeInt(json['id']),
      outletId: safeInt(json['outlet_id']),
      customerId: json['customer_id'] == null
          ? (rawCustomer is Map ? safeInt(rawCustomer['id']) : null)
          : safeInt(json['customer_id']),
      label: safeString(json['label'], 'Hold #${safeInt(json['id'])}'),
      items: items,
      createdAt: json['created_at']?.toString(),
      expiresAt: json['expires_at']?.toString(),
    );
  }
}

/// Satu cicilan milik sebuah order.
///
/// Backend (produksi, tabel `installments`):
/// `order_id, installment_number, amount, due_date, paid_date`,
/// `status: pending|paid|overdue`. Tidak ada konsep plan/count/DP di
/// tabel ini; pembayaran via `POST /installments/{id}/pay`
/// (`amount` + `payment_method_id` wajib) yang mencatat ke `payments`
/// dan menggeser `payment_status` order (`paid|partial`).
class Installment {
  final int id;
  final int? orderId;
  final String? orderNumber;
  final int installmentNumber;
  final double amount;
  final String? dueDate;
  final String? paidDate;
  final String status;

  Installment({
    required this.id,
    this.orderId,
    this.orderNumber,
    required this.installmentNumber,
    required this.amount,
    this.dueDate,
    this.paidDate,
    required this.status,
  });

  bool get isPaid => status == 'paid';

  factory Installment.fromJson(Map<String, dynamic> json) {
    final order = json['order'];
    return Installment(
      id: safeInt(json['id']),
      orderId: json['order_id'] == null
          ? null
          : safeInt(json['order_id']),
      orderNumber: (order is Map ? order['number']?.toString() : null),
      installmentNumber: safeInt(
        json['installment_number'] ?? json['sequence'],
        1,
      ),
      amount: safeDouble(json['amount']),
      dueDate: (json['due_date'] ?? json['dueDate'])?.toString(),
      paidDate: (json['paid_date'] ?? json['paidDate'])?.toString(),
      status: safeString(json['status'], 'pending'),
    );
  }
}

/// Label Bahasa Indonesia untuk status cicilan (`pending|paid|overdue`).
String installmentStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Menunggu';
    case 'paid':
      return 'Lunas';
    case 'overdue':
      return 'Jatuh Tempo';
    default:
      return status.isEmpty ? 'Menunggu' : status;
  }
}

BadgeTone toneForInstallmentStatus(String status) {
  switch (status) {
    case 'paid':
      return BadgeTone.success;
    case 'overdue':
      return BadgeTone.error;
    case 'pending':
    default:
      return BadgeTone.warning;
  }
}
