/// Read-only selection rules for planning a shared experience.
///
/// This does not update Supabase, contact external recommendation services,
/// or expose private content. Only the already-authorized experience rows
/// passed by the current screen are considered.
class ExperiencePickerRules {
  static List<Map<String, dynamic>> shortlist(
    Iterable<Map<String, dynamic>> experiences, {
    String category = 'all',
  }) {
    final result = experiences.where((item) {
      if (item['archived_at'] != null) return false;
      if (item['status'] == 'enjoyed') return false;
      if (category != 'all' && item['category'] != category) return false;
      return (item['title'] ?? '').toString().trim().isNotEmpty;
    }).toList();

    result.sort((left, right) {
      // Already-planned experiences come first. Their actual dates are
      // ordered rather than guessed from the phone's current timezone.
      final leftPriority = left['status'] == 'planned' ? 0 : 1;
      final rightPriority = right['status'] == 'planned' ? 0 : 1;
      if (leftPriority != rightPriority) {
        return leftPriority.compareTo(rightPriority);
      }

      final leftDate = DateTime.tryParse((left['planned_on'] ?? '').toString());
      final rightDate = DateTime.tryParse((right['planned_on'] ?? '').toString());
      if (leftDate != null && rightDate != null) {
        final comparison = leftDate.compareTo(rightDate);
        if (comparison != 0) return comparison;
      } else if (leftDate != null) {
        return -1;
      } else if (rightDate != null) {
        return 1;
      }

      final byTitle = left['title'].toString().toLowerCase().compareTo(
        right['title'].toString().toLowerCase(),
      );
      if (byTitle != 0) return byTitle;
      return (left['id'] ?? '').toString().compareTo(
        (right['id'] ?? '').toString(),
      );
    });
    return result;
  }

  /// A stable day-based starting point, so partners have a consistent
  /// suggestion even in different local timezones. "Another idea" cycles
  /// without storing a vote or secretly changing a shared record.
  static Map<String, dynamic>? pick(
    List<Map<String, dynamic>> candidates, {
    DateTime? now,
    int offset = 0,
  }) {
    if (candidates.isEmpty) return null;
    final current = (now ?? DateTime.now()).toUtc();
    final day = DateTime.utc(current.year, current.month, current.day)
            .millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
    final position = (day + offset) % candidates.length;
    return candidates[position];
  }

  /// Use vocabulary that fits each collection, rather than saying
  /// someone "watched" a book or a board game.
  static String completionAction(String category) => switch (category) {
    'movie' || 'show' => 'Mark watched',
    'music' => 'Mark listened',
    'book' => 'Mark read',
    'game' => 'Mark played',
    _ => 'Mark enjoyed',
  };

  static String completionState(String category) => switch (category) {
    'movie' || 'show' => 'Watched',
    'music' => 'Listened',
    'book' => 'Read',
    'game' => 'Played',
    _ => 'Enjoyed',
  };

  static String dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static int count(
    Iterable<Map<String, dynamic>> experiences,
    String status,
  ) => experiences
      .where((item) => item['archived_at'] == null && item['status'] == status)
      .length;
}
