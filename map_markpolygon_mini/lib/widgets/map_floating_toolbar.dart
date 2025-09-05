import 'package:flutter/material.dart';

class MapFloatingToolbar extends StatelessWidget {
  final bool saving;
  final bool isEditing;
  final bool showWorking;
  final VoidCallback onToggleShowWorking;
  final VoidCallback onUndo;
  final VoidCallback onSave;
  final VoidCallback onClear;

  const MapFloatingToolbar({
    super.key,
    required this.saving,
    required this.isEditing,
    required this.showWorking,
    required this.onToggleShowWorking,
    required this.onUndo,
    required this.onSave,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      bottom: 12,
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Wrap(
            spacing: 6,
            children: [
              Tooltip(
                message:
                    showWorking ? 'ซ่อนชุดที่กำลังทำ' : 'แสดงชุดที่กำลังทำ',
                child: IconButton(
                  onPressed: onToggleShowWorking,
                  icon: Icon(
                    showWorking ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
              Tooltip(
                message: 'Undo จุดล่าสุด',
                child: IconButton(
                  onPressed: onUndo,
                  icon: const Icon(Icons.undo),
                ),
              ),
              Tooltip(
                message: isEditing ? 'บันทึกการแก้ไข' : 'บันทึกชุดพื้นที่',
                child: FilledButton.icon(
                  onPressed: saving ? null : onSave,
                  icon: const Icon(Icons.save),
                  label: Text(isEditing ? 'Save Update' : 'Save'),
                ),
              ),
              Tooltip(
                message: 'ล้างชุดที่กำลังทำ',
                child: IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.clear_all),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
