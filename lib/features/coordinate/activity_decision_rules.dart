/// Coordinate decision events are append-only; the database atomically
/// updates Activity stage and creates an attributed entry for every outcome.
class ActivityDecisionRules {
  const ActivityDecisionRules._();

  static const actions = [
    'chosen',
    'purchased',
    'delivered',
    'registered',
    'postponed',
    'reopened',
    'cancelled',
  ];

  static String stageFor(String action) => switch (action) {
    'chosen' => 'decided',
    'purchased' => 'purchased',
    'delivered' => 'completed',
    'registered' => 'registered',
    'postponed' => 'on_hold',
    'reopened' => 'exploring',
    'cancelled' => 'cancelled',
    _ => throw ArgumentError.value(action, 'action', 'Unknown decision action'),
  };

  static String titleFor(String action) => switch (action) {
    'chosen' => 'Selected an option',
    'purchased' => 'Purchased',
    'delivered' => 'Delivered',
    'registered' => 'Registered',
    'postponed' => 'Postponed',
    'reopened' => 'Reopened',
    'cancelled' => 'Cancelled',
    _ => 'Updated outcome',
  };

  static bool requiresOption(String action) => action == 'chosen';

  /// Most recent event, independent of the order returned by the server.
  /// Never mutate the source list; it may be owned by a live stream.
  static Map<String, dynamic>? latest(
    List<Map<String, dynamic>> history,
  ) {
    if (history.isEmpty) return null;
    final sorted = [...history]..sort((a, b) {
      final ad = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final bd = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final time = bd.compareTo(ad);
      return time != 0 ? time : (b['id']?.toString() ?? '')
          .compareTo(a['id']?.toString() ?? '');
    });
    return sorted.first;
  }
}
