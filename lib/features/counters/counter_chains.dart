/// Timeline rules shared by the counter screens (26 Nov 2026).
/// Timelines themselves are named and stored in the database (counter_timelines, D100).
class CounterChains {
  const CounterChains._();

  /// Show "Today" on a timeline only when it falls strictly between the first and last point.
  static bool showToday(List<DateTime> sorted, DateTime today) {
    if (sorted.length < 2) return false;
    final t = DateTime(today.year, today.month, today.day);
    DateTime d(DateTime x) => DateTime(x.year, x.month, x.day);
    return t.isAfter(d(sorted.first)) && t.isBefore(d(sorted.last));
  }
}
