import '../utils/safe_parse.dart';

class Category {
  final int id;
  final String name;
  final List<Category> children;

  Category({required this.id, required this.name, this.children = const []});

  factory Category.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'];
    return Category(
      id: safeInt(json['id']),
      name: safeString(json['name']),
      children: rawChildren is List
          ? rawChildren
                .whereType<Map<String, dynamic>>()
                .map(Category.fromJson)
                .toList()
          : const [],
    );
  }
}
