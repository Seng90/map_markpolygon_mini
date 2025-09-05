import 'package:flutter/material.dart';

class WorkingPanel extends StatelessWidget {
  final bool showWorking;
  final ValueChanged<bool> onToggleShowWorking;
  final String workingName;
  final ValueChanged<String> onNameChanged;
  final String areaText; // เช่น "123.45 m²"
  final int pointCount;
  final VoidCallback onSave;
  final VoidCallback onUndo;
  final VoidCallback onClear;
  final VoidCallback onCopyCoords;
  final VoidCallback onExportGeoJSON;
  final bool saving;
  final bool isEditing;

  const WorkingPanel({
    super.key,
    required this.showWorking,
    required this.onToggleShowWorking,
    required this.workingName,
    required this.onNameChanged,
    required this.areaText,
    required this.pointCount,
    required this.onSave,
    required this.onUndo,
    required this.onClear,
    required this.onCopyCoords,
    required this.onExportGeoJSON,
    required this.saving,
    required this.isEditing,
  });

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(text: workingName)
      ..selection = TextSelection.collapsed(offset: workingName.length);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ชุดที่กำลังทำงาน',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                const Icon(Icons.visibility),
                const SizedBox(width: 6),
                const Text('แสดงชุดที่กำลังทำ'),
                const Spacer(),
                Switch(value: showWorking, onChanged: onToggleShowWorking),
              ],
            ),
            const SizedBox(height: 8),

            TextField(
              controller: controller,
              onChanged: onNameChanged,
              decoration: const InputDecoration(
                labelText: 'ชื่อชุดพื้นที่',
                hintText: 'เช่น แปลงนา 1',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                const Icon(Icons.straighten),
                const SizedBox(width: 6),
                Chip(label: Text('พื้นที่: $areaText')),
                const SizedBox(width: 8),
                Text('จุด: $pointCount'),
              ],
            ),
            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: saving ? null : onSave,
                  icon: const Icon(Icons.save),
                  label: Text(isEditing ? 'Save Update' : 'Save'),
                ),
                OutlinedButton.icon(
                  onPressed: onUndo,
                  icon: const Icon(Icons.undo),
                  label: const Text('Undo'),
                ),
                OutlinedButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Clear'),
                ),
                OutlinedButton.icon(
                  onPressed: onCopyCoords,
                  icon: const Icon(Icons.copy_all),
                  label: const Text('Copy Coords'),
                ),
                OutlinedButton.icon(
                  onPressed: onExportGeoJSON,
                  icon: const Icon(Icons.data_object),
                  label: const Text('Export GeoJSON'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
