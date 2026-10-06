import '../utils/safe_parse.dart';
import 'outlet.dart';

class User {
  final int id;
  final String name;
  final String email;
  final String? role;
  final List<Outlet> outlets;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.role,
    this.outlets = const [],
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final rawOutlets = json['outlets'];
    return User(
      id: safeInt(json['id']),
      name: safeString(json['name']),
      email: safeString(json['email']),
      role: json['role']?.toString(),
      outlets: rawOutlets is List
          ? rawOutlets
              .whereType<Map<String, dynamic>>()
              .map(Outlet.fromJson)
              .toList()
          : const [],
    );
  }
}
