/// A small, privacy-aware dashboard summary built only from rows
/// already authorized by Supabase Row Level Security.
class SpaceTaskSummary {
  const SpaceTaskSummary({
    required this.openShared,
    required this.myPrivate,
    required this.assignedToMe,
    required this.completedShared,
  });

  final int openShared;
  final int myPrivate;
  final int assignedToMe;
  final int completedShared;

  factory SpaceTaskSummary.fromRows(
    List<Map<String, dynamic>> rows,
    String currentUserId,
  ) {
    var openShared = 0;
    var myPrivate = 0;
    var assignedToMe = 0;
    var completedShared = 0;
    for (final row in rows) {
      final shared = (row['visibility'] as String? ?? 'shared') == 'shared';
      final open = row['status'] == 'open';
      if (shared && open) openShared++;
      if (!shared && open) myPrivate++;
      if (shared && open && row['assigned_to'] == currentUserId) {
        assignedToMe++;
      }
      if (shared && row['status'] == 'completed') completedShared++;
    }
    return SpaceTaskSummary(
      openShared: openShared,
      myPrivate: myPrivate,
      assignedToMe: assignedToMe,
      completedShared: completedShared,
    );
  }
}
