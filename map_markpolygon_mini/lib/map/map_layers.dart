import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:latlong2/latlong.dart';

import '../models/polygon_model.dart';

typedef DragUpdate = void Function(int index, LatLng newPoint);
typedef RemoveAt = void Function(int index);

class MapLayers extends StatelessWidget {
  final MapController controller;
  final List<PolygonModel> saved;
  final Map<int, bool> visibleSaved;
  final List<LatLng> working;
  final bool showWorking;
  final int? editingId;

  final List<Marker> workingNumberMarkers; // ป้ายเลขลำดับจุด
  final Color Function(int id, {double alpha}) colorForSaved;

  final void Function(TapPosition tap, LatLng latLng) onTapAddPoint;
  final DragUpdate onDragUpdate;
  final RemoveAt onRemoveIndex;

  const MapLayers({
    super.key,
    required this.controller,
    required this.saved,
    required this.visibleSaved,
    required this.working,
    required this.showWorking,
    required this.editingId,
    required this.workingNumberMarkers,
    required this.colorForSaved,
    required this.onTapAddPoint,
    required this.onDragUpdate,
    required this.onRemoveIndex,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        onTap: onTapAddPoint, // (tapPosition, latLng)
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c'],
          retinaMode: true,
          userAgentPackageName: 'com.example.app',
        ),

        // Saved polygons
        PolygonLayer(
          polygons: saved
              .where((p) => p.id != null && (visibleSaved[p.id!] ?? true))
              .map((p) {
                final pts = p.points
                    .map((m) => LatLng(m['lat']!, m['lng']!))
                    .toList(growable: false);
                final id = p.id!;
                final fill = colorForSaved(id, alpha: .18);
                final stroke = colorForSaved(id, alpha: .9);
                return Polygon(
                  points: pts,
                  color: fill,
                  borderColor: stroke,
                  borderStrokeWidth: 2.0,
                );
              })
              .toList(growable: false),
        ),

        // Working polygon
        if (showWorking && working.length >= 3)
          PolygonLayer(
            polygons: [
              Polygon(
                points: working,
                color: Colors.indigo.withValues(alpha: .14),
                borderColor: Colors.indigo.withValues(alpha: .92),
                borderStrokeWidth: 2.2,
              ),
            ],
          ),

        // Working markers & numbering (normal mode)
        if (showWorking && editingId == null && working.isNotEmpty) ...[
          MarkerLayer(
            markers: working
                .map(
                  (p) => Marker(
                    point: p,
                    width: 16,
                    height: 16,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.indigo,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          MarkerLayer(markers: workingNumberMarkers),
        ],

        // Edit mode: drag + numbering
        if (showWorking && editingId != null && working.isNotEmpty) ...[
          DragMarkers(
            markers: List.generate(working.length, (i) {
              final p = working[i];
              return DragMarker(
                point: p,
                size: const Size(22, 22),
                offset: Offset.zero,
                builder: (ctx, pos, isDragging) {
                  return Container(
                    decoration: BoxDecoration(
                      color: isDragging ? Colors.orange : Colors.indigo,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  );
                },
                onDragUpdate: (details, newPoint) => onDragUpdate(i, newPoint),
                onLongPress: (LatLng _) => onRemoveIndex(i),
              );
            }),
          ),
          MarkerLayer(markers: workingNumberMarkers),
        ],
      ],
    );
  }
}
