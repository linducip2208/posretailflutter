class Customer {
  final int id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final int? totalPoints;
  final String? groupName;

  Customer({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.totalPoints,
    this.groupName,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      phone: json['phone'],
      email: json['email'],
      address: json['address'],
      totalPoints: json['total_points'],
      groupName: json['customer_group'] != null ? json['customer_group']['name'] : null,
    );
  }
}
