import '../utils/safe_parse.dart';

class OrderItem {
  final int id;
  final int productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double subtotal;

  OrderItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: safeInt(json['id']),
      productId: safeInt(json['product_id']),
      productName: json['product'] is Map ? safeString(json['product']['name']) : '',
      quantity: safeInt(json['quantity']),
      unitPrice: safeDouble(json['unit_price']),
      subtotal: safeDouble(json['subtotal']),
    );
  }
}

class Order {
  final int id;
  final String orderNumber;
  final int? customerId;
  final String? customerName;
  final int outletId;
  final String? outletName;
  final String? queueNumber;
  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double totalAmount;
  final String paymentStatus;
  final String orderStatus;
  final String createdAt;
  final List<OrderItem>? items;
  final List<Payment>? payments;

  Order({
    required this.id,
    required this.orderNumber,
    this.customerId,
    this.customerName,
    required this.outletId,
    this.outletName,
    this.queueNumber,
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.totalAmount,
    required this.paymentStatus,
    required this.orderStatus,
    required this.createdAt,
    this.items,
    this.payments,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: safeInt(json['id']),
      orderNumber: safeString(json['order_number']),
      customerId: json['customer_id'] == null ? null : safeInt(json['customer_id']),
      customerName: json['customer_name']?.toString() ??
          (json['customer'] is Map ? safeString(json['customer']['name'], '') : null),
      outletId: safeInt(json['outlet_id']),
      outletName: json['outlet_name']?.toString() ??
          (json['outlet'] is Map ? safeString(json['outlet']['name'], '') : null),
      queueNumber: json['queue_number']?.toString(),
      subtotal: safeDouble(json['subtotal']),
      discountAmount: safeDouble(json['discount_amount']),
      taxAmount: safeDouble(json['tax_amount']),
      totalAmount: safeDouble(json['total_amount']),
      paymentStatus: safeString(json['payment_status'], 'unpaid'),
      orderStatus: safeString(json['order_status'], 'pending'),
      createdAt: safeString(json['created_at']),
      items: json['items'] is List
          ? (json['items'] as List)
              .whereType<Map<String, dynamic>>()
              .map(OrderItem.fromJson)
              .toList()
          : null,
      payments: json['payments'] is List
          ? (json['payments'] as List)
              .whereType<Map<String, dynamic>>()
              .map(Payment.fromJson)
              .toList()
          : null,
    );
  }
}

class Payment {
  final int id;
  final int paymentMethodId;
  final String? methodName;
  final double amount;
  final String status;
  final String? paidAt;

  Payment({
    required this.id,
    required this.paymentMethodId,
    this.methodName,
    required this.amount,
    required this.status,
    this.paidAt,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: safeInt(json['id']),
      paymentMethodId: safeInt(json['payment_method_id']),
      methodName: json['payment_method'] is Map
          ? safeString(json['payment_method']['name'], '')
          : null,
      amount: safeDouble(json['amount']),
      status: safeString(json['status'], 'pending'),
      paidAt: json['paid_at']?.toString(),
    );
  }
}
