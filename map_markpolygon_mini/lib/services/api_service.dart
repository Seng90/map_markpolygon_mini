// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/polygon_model.dart';

/// ---------- Helpers: แปลงชนิดแบบยืดหยุ่น ----------
double? _toDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }
  return null;
}

double _toDouble(dynamic v, {double fallback = 0}) {
  return _toDoubleOrNull(v) ?? fallback;
}

int? _toIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    final i = int.tryParse(s);
    if (i != null) return i;
    final d = double.tryParse(s);
    if (d != null) return d.toInt();
  }
  return null;
}

int _toInt(dynamic v, {int fallback = 0}) {
  return _toIntOrNull(v) ?? fallback;
}

/// ---------- Overlap model ----------
class OverlapItem {
  final int id;
  final String name;
  final String label; // เช่น Province/District
  final String adminLevel; // ADM1/ADM2 หรือ OSM admin_level
  final double areaOfAdmin;
  final double overlapArea;
  final double percent;
  final String unit; // 'm²' หรือ 'km²'

  OverlapItem({
    required this.id,
    required this.name,
    required this.label,
    required this.adminLevel,
    required this.areaOfAdmin,
    required this.overlapArea,
    required this.percent,
    required this.unit,
  });

  factory OverlapItem.fromJson(Map<String, dynamic> j) {
    return OverlapItem(
      id: _toInt(j['id']),
      name: (j['name'] ?? '').toString(),
      label: (j['label'] ?? '').toString(),
      adminLevel: (j['adminLevel'] ?? '').toString(),
      areaOfAdmin: _toDouble(j['areaOfAdmin']),
      overlapArea: _toDouble(j['overlapArea']),
      percent: _toDouble(j['percent']),
      unit: (j['unit'] ?? '').toString(),
    );
  }
}

class ApiService {
  // ตั้งค่า base URL ผ่าน --dart-define=API_BASE_URL=... ได้
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  // -------- Polygons CRUD --------

  static Future<List<PolygonModel>> getPolygons() async {
    final url = Uri.parse('$baseUrl/polygons');
    final resp = await http.get(url);
    if (resp.statusCode != 200) {
      throw Exception('GET /polygons failed: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map((e) => _polygonFromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<PolygonModel> createPolygon(PolygonModel p) async {
    final url = Uri.parse('$baseUrl/polygons');
    final payload = {
      'name': p.name,
      'points': p.points,
      'area_sq_m': p.areaSqM,
    };
    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (resp.statusCode != 200) {
      throw Exception('POST /polygons failed: ${resp.statusCode} ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return _polygonFromJson(json);
  }

  static Future<PolygonModel> updatePolygon(PolygonModel p) async {
    if (p.id == null) {
      throw Exception('updatePolygon: id is required');
    }
    final url = Uri.parse('$baseUrl/polygons/${p.id}');
    final payload = {
      'name': p.name,
      'points': p.points,
      'area_sq_m': p.areaSqM,
    };
    final resp = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (resp.statusCode != 200) {
      throw Exception('PUT /polygons failed: ${resp.statusCode} ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return _polygonFromJson(json);
  }

  static Future<void> deletePolygon(int id) async {
    final url = Uri.parse('$baseUrl/polygons/$id');
    final resp = await http.delete(url);
    if (resp.statusCode != 200) {
      throw Exception(
        'DELETE /polygons failed: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  static PolygonModel _polygonFromJson(Map<String, dynamic> j) {
    // points อาจเป็น List หรือ String(JSON) → รองรับทั้งสองแบบ
    dynamic pointsRaw = j['points'];
    if (pointsRaw is String) {
      try {
        pointsRaw = jsonDecode(pointsRaw);
      } catch (_) {
        pointsRaw = const <dynamic>[];
      }
    }

    final pts = <Map<String, double>>[];
    if (pointsRaw is List) {
      for (final e in pointsRaw) {
        try {
          final lat = _toDoubleOrNull(e['lat']);
          final lng = _toDoubleOrNull(e['lng']);
          if (lat != null && lng != null) {
            pts.add({'lat': lat, 'lng': lng});
          }
        } catch (_) {
          // ถ้าแปลงไม่ได้ ข้ามจุดนั้น
        }
      }
    }

    return PolygonModel(
      id: _toIntOrNull(j['id']),
      name: (j['name'] ?? '').toString(),
      points: pts,
      areaSqM: _toDoubleOrNull(j['area_sq_m']),
    );
  }

  // -------- Overlap Analysis --------

  /// ใช้ชุดข้อมูลลาว (ADM1/ADM2) จากไฟล์ในเครื่อง
  static Future<List<OverlapItem>> analyzeOverlapLocalLao({
    required List<Map<String, double>> points, // [{'lat':..,'lng':..}]
    String unit = 'm2', // 'm2' | 'km2'
    List<int> levels = const [1, 2], // เลือก ADM level
  }) async {
    final url = Uri.parse('$baseUrl/analyze-overlap-local-lao');
    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'points': points, 'unit': unit, 'levels': levels}),
    );
    if (resp.statusCode != 200) {
      throw Exception('Analyze local failed: ${resp.statusCode} ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final items =
        (json['items'] as List<dynamic>)
            .map((e) => OverlapItem.fromJson(e as Map<String, dynamic>))
            .toList();
    return items;
  }

  /// สำรอง: ใช้ Overpass (ช้ากว่า/ไม่เสถียรกว่า)
  static Future<List<OverlapItem>> analyzeOverlap({
    required List<Map<String, double>> points,
    String unit = 'm2',
  }) async {
    final url = Uri.parse('$baseUrl/analyze-overlap');
    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'points': points, 'unit': unit}),
    );
    if (resp.statusCode != 200) {
      throw Exception('Analyze failed: ${resp.statusCode} ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final items =
        (json['items'] as List<dynamic>)
            .map((e) => OverlapItem.fromJson(e as Map<String, dynamic>))
            .toList();
    return items;
  }
}
