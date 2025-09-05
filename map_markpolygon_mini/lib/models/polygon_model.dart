class PolygonModel {
  final int? id;
  final String name;
  final List<Map<String, double>> points;
  final double? areaSqM;

  PolygonModel({
    this.id,
    required this.name,
    required this.points,
    this.areaSqM,
  });

  factory PolygonModel.fromJson(Map<String, dynamic> json) {
    // ✅ รองรับ id เป็น int หรือ string
    int? parseId(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is String) return int.tryParse(v);
      if (v is num) return v.toInt();
      return null;
    }

    final pts =
        (json['points'] as List)
            .map(
              (e) => {
                'lat': (e['lat'] as num).toDouble(),
                'lng': (e['lng'] as num).toDouble(),
              },
            )
            .toList();

    return PolygonModel(
      id: parseId(json['id']),
      name: json['name'] as String,
      points: pts,
      areaSqM:
          (json['area_sq_m'] is num)
              ? (json['area_sq_m'] as num).toDouble()
              : (json['area_sq_m'] is String)
              ? double.tryParse(json['area_sq_m'])
              : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'points': points,
    'area_sq_m': areaSqM,
  };
}
