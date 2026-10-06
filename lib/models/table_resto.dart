class TableResto {
  final int id;
  final String name;
  final String code;
  final int capacity;
  final String status;
  final int? tableAreaId;
  final String? areaName;

  TableResto({
    required this.id,
    required this.name,
    required this.code,
    required this.capacity,
    required this.status,
    this.tableAreaId,
    this.areaName,
  });

  factory TableResto.fromJson(Map<String, dynamic> json) {
    return TableResto(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      capacity: json['capacity'] ?? 4,
      status: json['status'] ?? 'available',
      tableAreaId: json['table_area_id'],
      areaName: json['table_area'] != null ? json['table_area']['name'] : null,
    );
  }
}
