class PaymentMethod {
  final int id;
  final String name;
  final String code;
  final String? type;

  PaymentMethod({
    required this.id,
    required this.name,
    required this.code,
    this.type,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      type: json['type'],
    );
  }
}
