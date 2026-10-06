import '../utils/safe_parse.dart';

class Outlet {
  final int id;
  final String name;
  final String? code;

  Outlet({required this.id, required this.name, this.code});

  factory Outlet.fromJson(Map<String, dynamic> json) {
    return Outlet(
      id: safeInt(json['id']),
      name: safeString(json['name'], 'Outlet'),
      code: json['code']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'code': code};
}
