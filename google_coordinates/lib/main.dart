import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:maps_toolkit/maps_toolkit.dart' as mp;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Marker & Polygon (maps_toolkit)',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  final List<LatLng> _points = [];
  bool _showPolygon = false;

  // เริ่มที่เวียงจันทน์
  static const LatLng _initialCenter = LatLng(17.975705, 102.633103);

  bool get _canDraw => _points.length >= 3;

  // แปลงไปเป็นชนิดของ maps_toolkit
  List<mp.LatLng> _asMp(List<LatLng> pts) =>
      pts.map((p) => mp.LatLng(p.latitude, p.longitude)).toList();

  // ความยาวเส้นทาง/เส้นรอบรูป (m) — ใช้ SphericalUtil (แม่นยำบนทรงกลม)
  double get _lengthMeters {
    if (_points.length < 2) return 0;
    final path = _asMp(_points);
    if (_showPolygon && _canDraw) {
      final closed = [...path, path.first];
      return mp.SphericalUtil.computeLength(closed).toDouble();
    } else {
      return mp.SphericalUtil.computeLength(path).toDouble();
    }
  }

  // พื้นที่ (m²) — คิดเมื่อวาด polygon เท่านั้น
  double? get _areaSqMeters {
    if (!_showPolygon || !_canDraw) return null;
    final ring = _asMp(_points);
    final closed = [...ring, ring.first]; // ปิดรูปเพื่อความชัวร์
    return mp.SphericalUtil.computeArea(closed).toDouble();
  }

  // centroid แบบง่าย (เฉลี่ยพิกัด) — ใช้เพื่อแปะ label กลางพื้นที่
  LatLng? get _centroid {
    if (!_showPolygon || !_canDraw) return null;
    final lat =
        _points.fold<double>(0, (a, p) => a + p.latitude) / _points.length;
    final lng =
        _points.fold<double>(0, (a, p) => a + p.longitude) / _points.length;
    return LatLng(lat, lng);
  }

  String _fmtMeters(double m) {
    if (m < 1000) return '${m.toStringAsFixed(1)} m';
    return '${(m / 1000).toStringAsFixed(3)} km';
  }

  String _fmtArea(double m2) {
    if (m2 < 10000) return '${m2.toStringAsFixed(1)} m²';
    final ha = m2 / 10000.0;
    if (ha < 100) return '${ha.toStringAsFixed(2)} ha';
    final km2 = m2 / 1e6;
    return '${km2.toStringAsFixed(3)} km²';
  }

  // -------- Actions --------
  void _addPoint(LatLng p) {
    setState(() => _points.add(p));
  }

  void _togglePolygon() {
    if (!_canDraw) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ຕ້ອງມີຢ່າງນ້ອຍ 3 ຈຸດເພື່ອແຕ້ມ Polygon')),
      );
      return;
    }
    setState(() => _showPolygon = !_showPolygon);
  }

  void _undoLast() {
    if (_points.isEmpty) return;
    setState(() {
      _points.removeLast();
      if (_points.length < 3) _showPolygon = false;
    });
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('ລ້າງທັ້ງຫມົດ'),
            content: const Text('ທ່ານຕ້ອງການລົບຈຸດທັ້ງຫມົດຫຼືບໍ່'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ຍົກເລີກ'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('ລ້າງ'),
              ),
            ],
          ),
    );
    if (ok == true) {
      setState(() {
        _points.clear();
        _showPolygon = false;
      });
    }
  }

  Future<void> _copyLatLng(LatLng p) async {
    final text =
        '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ຄັດລອກແລ້ວ: $text')));
    }
  }

  Future<void> _copyAllLatLng() async {
    if (_points.isEmpty) return;
    final lines = <String>[];
    for (var i = 0; i < _points.length; i++) {
      final p = _points[i];
      lines.add(
        'P${i + 1}: ${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}',
      );
    }
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ຄັດລອກພິກັດທັ້ງຫມົດແລ້ວ')));
    }
  }

  Future<void> _exportGeoJSON() async {
    if (_points.isEmpty) return;
    Map<String, dynamic> geometry;

    if (_points.length >= 3) {
      final ring = _points.map((p) => [p.longitude, p.latitude]).toList();
      if (ring.first[0] != ring.last[0] || ring.first[1] != ring.last[1]) {
        ring.add(ring.first); // ปิดห่วง
      }
      geometry = {
        "type": "Polygon",
        "coordinates": [ring],
      };
    } else if (_points.length == 2) {
      geometry = {
        "type": "LineString",
        "coordinates": _points.map((p) => [p.longitude, p.latitude]).toList(),
      };
    } else {
      geometry = {
        "type": "Point",
        "coordinates": [_points.first.longitude, _points.first.latitude],
      };
    }

    final feature = {
      "type": "Feature",
      "geometry": geometry,
      "properties": {
        "name": "MyShape",
        "created_at": DateTime.now().toIso8601String(),
      },
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(feature);
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ຄັດລອກ GeoJSON ຈຸດນີ້ແລ້ວ')),
      );
    }
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    for (var i = 0; i < _points.length; i++) {
      final p = _points[i];
      final label = 'P${i + 1}';
      markers.add(
        Marker(
          point: p,
          width: 44,
          height: 44,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const SizedBox(height: 4),
              const Icon(Icons.location_on, size: 28, color: Colors.red),
            ],
          ),
        ),
      );
    }

    final c = _centroid;
    if (c != null) {
      markers.add(
        Marker(
          point: c,
          width: 100,
          height: 60,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.my_location, size: 22, color: Colors.blueGrey),
              SizedBox(height: 2),
              Text('Centroid', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final lenText = _fmtMeters(_lengthMeters);
    final area = _areaSqMeters;
    final areaText = area != null ? _fmtArea(area) : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map: Mark & Polygon'),
        actions: [
          IconButton(
            tooltip: 'ຄັດລອກພິກັດທັ້ງຫມົດ',
            onPressed: _points.isNotEmpty ? _copyAllLatLng : null,
            icon: const Icon(Icons.content_copy),
          ),
          IconButton(
            tooltip: 'Export GeoJSON',
            onPressed: _points.isNotEmpty ? _exportGeoJSON : null,
            icon: const Icon(Icons.data_object),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: 13,
              // ถ้าอยากกันการแตะพลาด ใช้ onLongPress แทน onTap ได้
              onTap: (tapPos, latLng) => _addPoint(latLng),
              // onLongPress: (tapPos, latLng) => _addPoint(latLng),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.app',
              ),
              if (_showPolygon && _canDraw)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _points,
                      color: Colors.indigo.withOpacity(0.18),
                      borderColor: Colors.indigo,
                      borderStrokeWidth: 2.5,
                    ),
                  ],
                ),
              if (_points.isNotEmpty) MarkerLayer(markers: _buildMarkers()),
            ],
          ),

          // แผงควบคุมล่าง
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: const [
                  BoxShadow(blurRadius: 12, color: Colors.black26),
                ],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              height: 260,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Marked Points',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      FilledButton.tonalIcon(
                        onPressed: _canDraw ? _togglePolygon : null,
                        icon: Icon(
                          _showPolygon ? Icons.hide_source : Icons.polyline,
                        ),
                        label: Text(
                          _showPolygon ? 'Hide Polygon' : 'Draw Polygon',
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Undo',
                        onPressed: _points.isNotEmpty ? _undoLast : null,
                        icon: const Icon(Icons.undo),
                      ),
                      IconButton(
                        tooltip: 'Clear all',
                        onPressed: _points.isNotEmpty ? _clearAll : null,
                        icon: const Icon(Icons.delete_sweep),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Chip(
                        label: Text(
                          _showPolygon && _canDraw
                              ? 'Perimeter: $lenText'
                              : 'Path: $lenText',
                        ),
                      ),
                      if (areaText != null)
                        Chip(label: Text('Area: $areaText')),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child:
                        _points.isEmpty
                            ? const Center(
                              child: Text(
                                'ກົດເທິງພື້ນທີ່ທີ່ຕ້ອງການເພື່ອເພີ່ມຈຸດ (P1, P2, …)',
                              ),
                            )
                            : ListView.separated(
                              itemBuilder: (context, i) {
                                final p = _points[i];
                                final label = 'P${i + 1}';
                                final lat = p.latitude.toStringAsFixed(6);
                                final lng = p.longitude.toStringAsFixed(6);
                                return Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.75),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        label,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Lat: $lat, Lng: $lng',
                                        style: const TextStyle(fontSize: 13.5),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Copy',
                                      onPressed: () => _copyLatLng(p),
                                      icon: const Icon(Icons.copy),
                                    ),
                                    IconButton(
                                      tooltip: 'Remove',
                                      onPressed: () {
                                        setState(() {
                                          _points.removeAt(i);
                                          if (_points.length < 3) {
                                            _showPolygon = false;
                                          }
                                        });
                                      },
                                      icon: const Icon(Icons.close),
                                    ),
                                  ],
                                );
                              },
                              separatorBuilder:
                                  (_, __) => const Divider(height: 10),
                              itemCount: _points.length,
                            ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
