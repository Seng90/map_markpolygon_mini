import 'package:flutter/material.dart';
import '../models/polygon_model.dart';

class SavedPolygonsPanel extends StatelessWidget {
  final List<PolygonModel> items;
  final Map<int, bool> visibleMap; // id -> visible
  final String Function(PolygonModel)
  areaTextOf; // คืน "xx.xx m²" หรือ "x.xx km²"
  final int Function(PolygonModel) pointCountOf;
  final void Function(PolygonModel) onFocus;
  final void Function(PolygonModel) onStartEdit;
  final void Function(PolygonModel) onRename;
  final void Function(PolygonModel) onDelete;
  final void Function(PolygonModel, bool) onToggleVisible;
  final Color Function(PolygonModel) colorOf;

  const SavedPolygonsPanel({
    super.key,
    required this.items,
    required this.visibleMap,
    required this.areaTextOf,
    required this.pointCountOf,
    required this.onFocus,
    required this.onStartEdit,
    required this.onRename,
    required this.onDelete,
    required this.onToggleVisible,
    required this.colorOf,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'รายการที่บันทึกไว้',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),

            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('ยังไม่มีข้อมูล'),
              )
            else
              ...items.map((p) {
                final id = p.id;
                final visible = (id != null) ? (visibleMap[id] ?? true) : true;
                final colorDot = colorOf(p);
                final areaStr = areaTextOf(p);
                final ptsCount = pointCountOf(p);

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ปุ่มด้านบน
                      Row(
                        children: [
                          CircleAvatar(radius: 10, backgroundColor: colorDot),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              p.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'แก้ไข',
                            icon: const Icon(Icons.edit),
                            onPressed: () => onStartEdit(p),
                          ),
                          IconButton(
                            tooltip: 'เปลี่ยนชื่อ',
                            icon: const Icon(Icons.drive_file_rename_outline),
                            onPressed: () => onRename(p),
                          ),
                          IconButton(
                            tooltip: 'ลบ',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => onDelete(p),
                          ),
                          Switch(
                            value: visible,
                            onChanged: (v) => onToggleVisible(p, v),
                          ),
                        ],
                      ),

                      // กลาง: ข้อมูล
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 28,
                          top: 2,
                          bottom: 4,
                        ),
                        child: Row(
                          children: [
                            Text('จุด: $ptsCount'),
                            const SizedBox(width: 12),
                            TextButton.icon(
                              onPressed: () => onFocus(p),
                              icon: const Icon(Icons.center_focus_strong),
                              label: const Text('โฟกัส'),
                            ),
                          ],
                        ),
                      ),

                      // ล่าง: พื้นที่
                      Padding(
                        padding: const EdgeInsets.only(left: 28),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Chip(label: Text('พื้นที่ ~ $areaStr')),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
