enum CoordinateActivityView { active, attention, finished, all }

/// Local presentation rules only. Supabase RLS still determines which rows
/// the user may ever receive from the shared workspace.
class CoordinateActivityFilters {
  const CoordinateActivityFilters._();

  static bool finished(Map<String, dynamic> item) =>
      item['stage'] == 'completed' || item['stage'] == 'cancelled';

  static bool archived(Map<String, dynamic> item) =>
      item['archived_at'] != null;

  static bool needsAttention(Map<String, dynamic> item, DateTime today) {
    if (finished(item) || archived(item)) return false;
    if (item['priority'] == 'high' || item['priority'] == 'urgent') return true;
    final due = DateTime.tryParse(item['due_on']?.toString() ?? '');
    if (due == null) return false;
    final dueDay = DateTime.utc(due.year, due.month, due.day);
    final todayDay = DateTime.utc(today.year, today.month, today.day);
    return dueDay.difference(todayDay).inDays <= 7;
  }

  static bool matches(Map<String, dynamic> item,
      CoordinateActivityView view, DateTime now) =>
      switch (view) {
        CoordinateActivityView.active => !archived(item) && !finished(item),
        CoordinateActivityView.attention => needsAttention(item, now),
        CoordinateActivityView.finished => !archived(item) && finished(item),
        CoordinateActivityView.all => true,
      };

  static List<Map<String, dynamic>> visible(
    List<Map<String, dynamic>> items,
    CoordinateActivityView view,
    String search,
    DateTime now,
  ) {
    final query = search.trim().toLowerCase();
    return [
      for (final item in items)
        if (matches(item, view, now) &&
            (query.isEmpty ||
                '${item['title'] ?? ''} ${item['body'] ?? ''}'
                    .toLowerCase().contains(query)))
          item,
    ];
  }

  static int count(List<Map<String, dynamic>> items,
      CoordinateActivityView view, DateTime now) =>
      items.where((item) => matches(item, view, now)).length;
}
