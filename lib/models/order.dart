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
    double asDouble(dynamic value) => double.tryParse(value?.toString() ?? '') ?? 0;

    return OrderItem(
      id: json['id'] ?? 0,
      productId: json['product_id'] ?? 0,
      productName: json['product'] != null ? json['product']['name'] ?? '' : '',
      quantity: int.tryParse(json['quantity']?.toString() ?? '0') ?? 0,
      unitPrice: asDouble(json['unit_price']),
      subtotal: asDouble(json['subtotal']),
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
    double asDouble(dynamic value) => double.tryParse(value?.toString() ?? '') ?? 0;

    return Order(
      id: json['id'] ?? 0,
      orderNumber: json['order_number'] ?? '',
      customerId: json['customer_id'],
      customerName: json['customer_name'] ?? json['customer']?['name'],
      outletId: json['outlet_id'] ?? 0,
      outletName: json['outlet_name'] ?? json['outlet']?['name'],
      queueNumber: json['queue_number'],
      subtotal: asDouble(json['subtotal']),
      discountAmount: asDouble(json['discount_amount']),
      taxAmount: asDouble(json['tax_amount']),
      totalAmount: asDouble(json['total_amount']),
      paymentStatus: json['payment_status'] ?? 'unpaid',
      orderStatus: json['order_status'] ?? 'pending',
      createdAt: json['created_at'] ?? '',
      items: json['items'] != null
          ? (json['items'] as List).map((e) => OrderItem.fromJson(e)).toList()
          : null,
      payments: json['payments'] != null
          ? (json['payments'] as List).map((e) => Payment.fromJson(e)).toList()
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
    double asDouble(dynamic value) => double.tryParse(value?.toString() ?? '') ?? 0;

    return Payment(
      id: json['id'] ?? 0,
      paymentMethodId: json['payment_method_id'] ?? 0,
      methodName: json['payment_method'] != null ? json['payment_method']['name'] : null,
      amount: asDouble(json['amount']),
      status: json['status'] ?? 'pending',
      paidAt: json['paid_at'],
    );
  }
}
