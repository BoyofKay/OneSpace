import 'task_editor_sheet.dart';

/// A malformed server row must not crash the whole To-do and Checklists page.
/// This is a view adapter, not an authorization boundary; database RLS still
/// determines which rows are returned to the current signed-in account.
class ChecklistListLoadResult {
  const ChecklistListLoadResult(this.items, this.skippedRows);
  final List<SharedTask> items;
  final int skippedRows;
}

class ChecklistListLoader {
  const ChecklistListLoader._();

  static ChecklistListLoadResult fromRows(
    Iterable<Map<String,dynamic>> rows,
  ) {
    final tasks=<SharedTask>[];
    var invalid=0;
    for (final row in rows) {
      if(row['migrated_to_list']!=null)continue;
      final id=row['id'];
      if (id is! String || id.trim().isEmpty) {
        invalid++;
        continue;
      }
      try {
        tasks.add(SharedTask.fromMap(row));
      } catch (_) {
        invalid++;
        // One incompatible legacy object is isolated, not fatal.
      }
    }
    return ChecklistListLoadResult(tasks,invalid);
  }
}
