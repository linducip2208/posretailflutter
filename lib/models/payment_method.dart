import '../utils/safe_parse.dart';

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
      id: safeInt(json['id']),
      name: safeString(json['name']),
      code: safeString(json['code']),
      type: json['type']?.toString(),
    );
  }
}
