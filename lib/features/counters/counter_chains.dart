/// Connected counters (26 Nov 2026): any number of counters joined on one timeline.
///
/// Storage is unchanged: each counter may point to one other counter through
/// `linked_counter_id`. A timeline is every counter reachable through those links
/// (in either direction), so A→B and C→B put A, B and C on one timeline.
class CounterLink {
  const CounterLink({required this.id, required this.date, this.linkedTo});
  final String id;
  final DateTime date;
  final String? linkedTo;
}

class CounterChains {
  const CounterChains._();

  /// Every counter on the same timeline as [id] (including it), oldest first.
  static List<CounterLink> group(String id, List<CounterLink> all) {
    final byId = {for (final c in all) c.id: c};
    if (!byId.containsKey(id)) return const [];
    final seen = <String>{id};
    final queue = [id];
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      final next = <String>[
        if (byId[cur]?.linkedTo != null && byId.containsKey(byId[cur]!.linkedTo)) byId[cur]!.linkedTo!,
        for (final c in all) if (c.linkedTo == cur) c.id,
      ];
      for (final n in next) { if (seen.add(n)) queue.add(n); }
    }
    final out = [for (final s in seen) byId[s]!]..sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  /// Show "Today" on the line only when it falls strictly between the first and last point.
  static bool showToday(List<DateTime> sorted, DateTime today) {
    if (sorted.length < 2) return false;
    final t = DateTime(today.year, today.month, today.day);
    DateTime d(DateTime x) => DateTime(x.year, x.month, x.day);
    return t.isAfter(d(sorted.first)) && t.isBefore(d(sorted.last));
  }

  /// Link changes that connect [other]'s timeline to [current]'s without cutting
  /// any existing connection. Returns {counter id: new linked_counter_id}.
  static Map<String, String?> connect(String current, String other, List<CounterLink> all) {
    final mine = group(current, all), theirs = group(other, all);
    if (mine.any((c) => c.id == other)) return const {};
    // The "root" of a timeline is a member that points nowhere; pointing it at the
    // other timeline joins both and keeps every existing link.
    final myRoot = mine.where((c) => c.linkedTo == null).firstOrNull;
    if (myRoot != null) return {myRoot.id: other};
    final theirRoot = theirs.where((c) => c.linkedTo == null).firstOrNull;
    if (theirRoot != null) return {theirRoot.id: current};
    // Both timelines are loops: re-pointing one member keeps its own loop connected.
    return {other: current};
  }

  /// Link changes that take [id] off its timeline while the other counters stay joined.
  static Map<String, String?> remove(String id, List<CounterLink> all) {
    final byId = {for (final c in all) c.id: c};
    final me = byId[id];
    if (me == null) return const {};
    final pointingAtMe = [for (final c in all) if (c.linkedTo == id) c.id];
    final changes = <String, String?>{id: null};
    var parent = me.linkedTo;
    if (parent == null && pointingAtMe.isNotEmpty) {
      // I was the root: the first counter that pointed at me becomes the new root.
      parent = pointingAtMe.first;
      changes[pointingAtMe.first] = null;
    }
    for (final child in pointingAtMe) {
      if (child != parent) changes[child] = parent;
    }
    return changes;
  }
}
