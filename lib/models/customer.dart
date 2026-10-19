import '../utils/safe_parse.dart';

class Customer {
  final int id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final int? totalPoints;
  final String? groupName;
  final double depositBalance;
  final double? creditLimit;
  final double? outstandingBalance;

  Customer({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.totalPoints,
    this.groupName,
    this.depositBalance = 0,
    this.creditLimit,
    this.outstandingBalance,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: safeInt(json['id']),
      name: safeString(json['name']),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      address: json['address']?.toString(),
      totalPoints: json['total_points'] == null
          ? null
          : safeInt(json['total_points']),
      groupName: json['customer_group'] is Map
          ? safeString(json['customer_group']['name'], '')
          : null,
      depositBalance: safeDouble(json['deposit_balance']),
      creditLimit: json['credit_limit'] == null
          ? null
          : safeDouble(json['credit_limit']),
      outstandingBalance: json['outstanding_balance'] == null
          ? null
          : safeDouble(json['outstanding_balance']),
    );
  }
}
