// lib/screens/map_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:maps_toolkit/maps_toolkit.dart' as mp;

import '../models/polygon_model.dart';
import '../services/api_service.dart';

// ใช้องค์ประกอบที่คุณมีอยู่แล้ว
import '../map/map_layers.dart'; // ชั้นแผนที่ + การเรนเดอร์ polygon/markers
import '../widgets/map_floating_toolbar.dart'; // ปุ่มลอย Undo/Save/Clear/Toggle
import '../widgets/working_panel.dart'; // แผงฝั่งขวาส่วน Working
import '../widgets/saved_polygons_panel.dart'; // รายการที่บันทึก

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // ----- Map & UI state -----
  final MapController _mapController = MapController();
  bool _showSidebar = true;
  bool _loadingSaved = false;
  bool _saving = false;

  // ----- Working polygon -----
  final List<LatLng> _working = <LatLng>[];
  String _workingName = '';
  double? _workingArea; // m²
  int? _editingId; // null = create, not null = edit
  bool _showWorking = true;

  // ----- Saved polygons -----
  final List<PolygonModel> _saved = <PolygonModel>[];
  final Map<int, bool> _visibleSaved = <int, bool>{};

  // ----- Overlap analysis -----
  String _areaUnit = 'm2'; // 'm2' | 'km2'
  List<OverlapItem> _overlap = [];
  bool _analyzing = false;

  @override
  void initState() {
    super.initState();
    _fetchPolygons();
  }

  // ---------- Data ----------
  Future<void> _fetchPolygons() async {
    setState(() => _loadingSaved = true);
    try {
      final list = await ApiService.getPolygons();
      setState(() {
        _saved
          ..clear()
          ..addAll(list);
        for (final p in _saved) {
          if (p.id != null) {
            _visibleSaved[p.id!] = _visibleSaved[p.id!] ?? true;
          }
        }
      });
    } catch (e) {
      _snack('โหลดข้อมูลไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loadingSaved = false);
    }
  }

  // ---------- Helpers ----------
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  List<LatLng> _latLngFromPoints(List<Map<String, double>> pts) => pts
      .map(
        (e) =>
            LatLng((e['lat'] as num).toDouble(), (e['lng'] as num).toDouble()),
      )
      .toList(growable: false);

  Color _colorForSaved(int id, {double alpha = 1.0}) {
    final hue = (id * 47) % 360;
    final hsl = HSLColor.fromAHSL(1.0, hue.toDouble(), 0.60, 0.50);
    return hsl.toColor().withValues(alpha: alpha.clamp(0.0, 1.0));
  }

  void _recomputeArea() {
    if (_working.length < 3) {
      _workingArea = null;
      return;
    }
    final pts =
        _working.map((p) => mp.LatLng(p.latitude, p.longitude)).toList();
    final num area = mp.SphericalUtil.computeArea(pts);
    _workingArea = area.toDouble();
  }

  String _formatArea(double? a) {
    if (a == null) return '-';
    if (a >= 1_000_000) return '${(a / 1_000_000).toStringAsFixed(2)} km²';
    return '${a.toStringAsFixed(2)} m²';
  }

  // ---------- Working ops ----------
  void _addPoint(LatLng p) {
    _working.add(p);
    _recomputeArea();
    setState(() {});
  }

  void _undoLastPoint() {
    if (_working.isNotEmpty) {
      _working.removeLast();
      _recomputeArea();
      setState(() {});
    }
  }

  void _clearWorking() {
    _working.clear();
    _workingName = '';
    _workingArea = null;
    _editingId = null;
    setState(() {});
  }

  Future<void> _copyCoords(List<LatLng> pts) async {
    final text = pts.map((p) => '${p.latitude}, ${p.longitude}').join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    _snack('คัดลอกพิกัดแล้ว');
  }

  Future<void> _exportWorkingAsGeoJSON() async {
    if (_working.length < 3) {
      _snack('ยังไม่มีโพลิกอนที่สมบูรณ์');
      return;
    }
    final coords = _working.map((p) => [p.longitude, p.latitude]).toList();
    final ring = [...coords, coords.first];
    final geojson = {
      'type': 'Feature',
      'properties': {'name': _workingName, 'area_sq_m': _workingArea ?? 0},
      'geometry': {
        'type': 'Polygon',
        'coordinates': [ring],
      },
    };
    final text = const JsonEncoder.withIndent('  ').convert(geojson);
    await Clipboard.setData(ClipboardData(text: text));
    _snack('คัดลอก GeoJSON แล้ว');
  }

  Future<void> _saveWorking() async {
    if (_working.length < 3) {
      _snack('ต้องมีอย่างน้อย 3 จุด');
      return;
    }
    if (_workingName.trim().isEmpty) {
      final name = await _promptText(
        context,
        'ตั้งชื่อชุดพื้นที่',
        hint: 'เช่น แปลงนา 1',
      );
      if (name == null || name.isEmpty) return;
      _workingName = name;
    }

    final pointsJson = _working
        .map((p) => <String, double>{'lat': p.latitude, 'lng': p.longitude})
        .toList(growable: false);
    final area = _workingArea;

    setState(() => _saving = true);
    try {
      if (_editingId != null) {
        final updated = PolygonModel(
          id: _editingId,
          name: _workingName,
          points: pointsJson,
          areaSqM: area,
        );
        await ApiService.updatePolygon(updated);
        _snack('บันทึกการแก้ไขแล้ว');
      } else {
        final newItem = PolygonModel(
          name: _workingName,
          points: pointsJson,
          areaSqM: area,
        );
        await ApiService.createPolygon(newItem);
        _snack('บันทึกชุดพื้นที่แล้ว');
      }
      await _fetchPolygons();
      _clearWorking();
    } catch (e) {
      _snack('บันทึกล้มเหลว: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- Saved ops ----------
  Future<void> _startEditPolygon(PolygonModel p) async {
    _working
      ..clear()
      ..addAll(_latLngFromPoints(p.points));
    _workingName = p.name;
    _recomputeArea();
    _editingId = p.id;
    setState(() {
      _showSidebar = true;
      _showWorking = true;
    });
    _focusPolygon(p);
  }

  Future<void> _renamePolygon(PolygonModel p) async {
    final name = await _promptText(context, 'เปลี่ยนชื่อ', initial: p.name);
    if (name == null || name.isEmpty) return;
    try {
      final updated = PolygonModel(
        id: p.id,
        name: name,
        points: p.points,
        areaSqM: p.areaSqM,
      );
      await ApiService.updatePolygon(updated);
      _snack('เปลี่ยนชื่อแล้ว');
      await _fetchPolygons();
    } catch (e) {
      _snack('เปลี่ยนชื่อล้มเหลว: $e');
    }
  }

  Future<void> _deletePolygon(PolygonModel p) async {
    final yes = await _confirm(context, 'ลบชุดพื้นที่นี้หรือไม่?');
    if (yes != true) return;
    try {
      await ApiService.deletePolygon(p.id!);
      _visibleSaved.remove(p.id!);
      _snack('ลบแล้ว');
      await _fetchPolygons();
    } catch (e) {
      _snack('ลบล้มเหลว: $e');
    }
  }

  void _toggleVisible(PolygonModel p, bool v) {
    if (p.id != null) {
      _visibleSaved[p.id!] = v;
      setState(() {});
    }
  }

  void _focusPolygon(PolygonModel p) {
    final pts = _latLngFromPoints(p.points);
    if (pts.isEmpty) return;
    final latitudes = pts.map((e) => e.latitude).toList();
    final longitudes = pts.map((e) => e.longitude).toList();
    final sw = LatLng(
      latitudes.reduce((a, b) => a < b ? a : b),
      longitudes.reduce((a, b) => a < b ? a : b),
    );
    final ne = LatLng(
      latitudes.reduce((a, b) => a > b ? a : b),
      longitudes.reduce((a, b) => a > b ? a : b),
    );
    final bounds = LatLngBounds.fromPoints([sw, ne]);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(36)),
    );
  }

  // ---------- Overlap analysis ----------
  Future<void> _analyzeOverlap() async {
    if (_working.length < 3) {
      _snack('ต้องมีอย่างน้อย 3 จุด');
      return;
    }
    final pointsJson = _working
        .map((p) => <String, double>{'lat': p.latitude, 'lng': p.longitude})
        .toList(growable: false);

    setState(() {
      _analyzing = true;
      _overlap = [];
    });
    try {
      // ✅ ใช้ local Laos dataset ก่อน
      final items = await ApiService.analyzeOverlapLocalLao(
        points: pointsJson,
        unit: _areaUnit,
        levels: const [1, 2],
      );

      // ถ้าอยากทำ fallback ไป Overpass: เปิดคอมเมนต์ 3 บรรทัดถัดไป
      // if (items.isEmpty) {
      //   items = await ApiService.analyzeOverlap(points: pointsJson, unit: _areaUnit);
      // }

      setState(() => _overlap = items);

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder:
            (_) => SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: _buildOverlapResult(),
              ),
            ),
      );
    } catch (e) {
      _snack('วิเคราะห์ไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Widget _buildOverlapResult() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'ผลการครอบคลุมพื้นที่',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              // ใช้ Dropdown เพื่อรองรับทุกธีม
              DropdownButton<String>(
                value: _areaUnit,
                items: const [
                  DropdownMenuItem(value: 'm2', child: Text('m²')),
                  DropdownMenuItem(value: 'km2', child: Text('km²')),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  setState(() => _areaUnit = v);
                  Navigator.of(context).pop(); // ปิด panel เดิม
                  await _analyzeOverlap(); // คำนวณใหม่ด้วยหน่วยใหม่
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_overlap.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Text('ไม่พบการทับซ้อนกับเขตการปกครองในบริเวณนี้'),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _overlap.length,
                separatorBuilder: (_, __) => const Divider(height: 0),
                itemBuilder: (_, i) {
                  final it = _overlap[i];
                  return ListTile(
                    dense: true,
                    title: Text(
                      '${it.name}  •  ${it.label} (${it.adminLevel})',
                    ),
                    subtitle: Text(
                      'ซ้อนทับ ~ ${it.overlapArea.toStringAsFixed(2)} ${it.unit} '
                      'จากทั้งหมด ${it.areaOfAdmin.toStringAsFixed(2)} ${it.unit} '
                      '(${it.percent.toStringAsFixed(2)}%)',
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;

    final List<Marker> numberMarkers = List<Marker>.generate(_working.length, (
      i,
    ) {
      final p = _working[i];
      return Marker(
        point: p,
        width: 28,
        height: 28,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            '${i + 1}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map & Polygons'),
        actions: [
          // toggle show working
          IconButton(
            tooltip: _showWorking ? 'ซ่อนชุดที่กำลังทำ' : 'แสดงชุดที่กำลังทำ',
            icon: Icon(_showWorking ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _showWorking = !_showWorking),
          ),
          // toggle sidebar
          IconButton(
            tooltip: _showSidebar ? 'ซ่อนแผงเครื่องมือ' : 'แสดงแผงเครื่องมือ',
            icon: Icon(
              _showSidebar ? Icons.close_fullscreen : Icons.open_in_full,
            ),
            onPressed: () {
              if (!wide) {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder:
                      (_) => SafeArea(
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height * 0.85,
                          child: _buildSidePanel(scrollable: true),
                        ),
                      ),
                );
              } else {
                setState(() => _showSidebar = !_showSidebar);
              }
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Row(
        children: [
          // map + floating toolbar
          Expanded(
            child: Stack(
              children: [
                MapLayers(
                  controller: _mapController,
                  saved: _saved,
                  visibleSaved: _visibleSaved,
                  working: _working,
                  showWorking: _showWorking,
                  editingId: _editingId,
                  workingNumberMarkers: numberMarkers,
                  colorForSaved: _colorForSaved,
                  onTapAddPoint: (tap, latLng) => _addPoint(latLng),
                  onDragUpdate: (idx, newPoint) {
                    _working[idx] = newPoint;
                    _recomputeArea();
                    setState(() {});
                  },
                  onRemoveIndex: (idx) {
                    _working.removeAt(idx);
                    _recomputeArea();
                    setState(() {});
                  },
                ),
                MapFloatingToolbar(
                  saving: _saving || _analyzing,
                  isEditing: _editingId != null,
                  showWorking: _showWorking,
                  onToggleShowWorking:
                      () => setState(() => _showWorking = !_showWorking),
                  onUndo: _undoLastPoint,
                  onSave: _saveWorking,
                  onClear: _clearWorking,
                ),
                // ปุ่มวิเคราะห์ลอย
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.extended(
                    onPressed: _analyzing ? null : _analyzeOverlap,
                    icon: const Icon(Icons.analytics_outlined),
                    label: const Text('วิเคราะห์'),
                  ),
                ),
                if (_loadingSaved || _saving || _analyzing)
                  const Positioned.fill(
                    child: IgnorePointer(
                      ignoring: true,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
          ),

          // sidebar (บนหน้าจอกว้าง)
          if (wide)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              width: _showSidebar ? 380 : 0,
              child:
                  _showSidebar
                      ? Container(
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          color: Theme.of(context).colorScheme.surface,
                        ),
                        child: _buildSidePanel(),
                      )
                      : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  Widget _buildSidePanel({bool scrollable = false}) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: ListView(
        children: [
          Row(
            children: [
              Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'เครื่องมือจัดการ',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'ซ่อนแผงเครื่องมือ',
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() => _showSidebar = false);
                  Navigator.of(context).maybePop();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Working panel
          WorkingPanel(
            showWorking: _showWorking,
            onToggleShowWorking: (v) => setState(() => _showWorking = v),
            workingName: _workingName,
            onNameChanged: (v) => _workingName = v,
            areaText: _formatArea(_workingArea),
            pointCount: _working.length,
            onSave: _saveWorking,
            onUndo: _undoLastPoint,
            onClear: _clearWorking,
            onCopyCoords: () => _copyCoords(_working),
            onExportGeoJSON: _exportWorkingAsGeoJSON,
            saving: _saving || _analyzing,
            isEditing: _editingId != null,
          ),
          const SizedBox(height: 12),

          // เลือกหน่วยพื้นที่สำหรับการวิเคราะห์
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Text('หน่วยพื้นที่วิเคราะห์:'),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _areaUnit,
                    items: const [
                      DropdownMenuItem(value: 'm2', child: Text('m²')),
                      DropdownMenuItem(value: 'km2', child: Text('km²')),
                    ],
                    onChanged: (v) => setState(() => _areaUnit = v ?? 'm2'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _analyzing ? null : _analyzeOverlap,
                    icon: const Icon(Icons.analytics_outlined),
                    label: const Text('วิเคราะห์'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Saved list
          SavedPolygonsPanel(
            items: _saved,
            visibleMap: _visibleSaved,
            areaTextOf: (p) => _formatArea(p.areaSqM),
            pointCountOf: (p) => p.points.length,
            onFocus: _focusPolygon,
            onStartEdit: _startEditPolygon,
            onRename: _renamePolygon,
            onDelete: _deletePolygon,
            onToggleVisible: _toggleVisible,
            colorOf:
                (p) =>
                    p.id != null
                        ? _colorForSaved(p.id!, alpha: .9)
                        : Colors.indigo.withValues(alpha: .9),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );

    if (scrollable) return content;
    return SafeArea(child: content);
  }

  // ---------- Dialog helpers ----------
  Future<bool?> _confirm(BuildContext context, String msg) {
    return showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('ยืนยัน'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('ตกลง'),
              ),
            ],
          ),
    );
  }

  Future<String?> _promptText(
    BuildContext context,
    String title, {
    String? initial,
    String? hint,
  }) async {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String?>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('ตกลง'),
              ),
            ],
          ),
    );
  }
}
