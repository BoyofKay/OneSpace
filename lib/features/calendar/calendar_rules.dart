/// Date-only calendar rules: no timezone-induced birthday/date shifts.
class CalendarRules {
  const CalendarRules._();

  static DateTime day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// Convert timed events to the viewer's local clock.
  /// All-day dates deliberately stay independent from time zones.
  static DateTime? eventLocalStart(Object? timestamp){
    if(timestamp==null)return null;
    return DateTime.tryParse(timestamp.toString())?.toLocal();
  }

  static bool isValid(int year, int month, int date) {
    if (year < 1900 || year > 2100 || month < 1 || month > 12 || date < 1) {
      return false;
    }
    final result = DateTime.utc(year, month, date);
    return result.year == year && result.month == month && result.day == date;
  }

  static DateTime? nextOccurrence({
    required DateTime original,
    required String recurrence,
    required DateTime today,
    Object? rule,
  }) {
    final reference = day(today);
    final source = day(original);
    if (rule is Map) {
      var d = source.isBefore(reference) ? reference : source;
      for (var i = 0; i <= 800; i++) {
        if (ruleOccursOn(source, rule, d)) return d;
        final until = DateTime.tryParse(rule['until']?.toString() ?? '');
        if (until != null && d.isAfter(until)) return null;
        d = DateTime(d.year, d.month, d.day + 1);
      }
      return null;
    }
    if (recurrence != 'yearly') {
      return source.isBefore(reference) ? null : source;
    }
    for (var year = reference.year; year <= 2100; year++) {
      if (!isValid(year, source.month, source.day)) continue;
      final candidate = DateTime(year, source.month, source.day);
      if (!candidate.isBefore(reference)) return candidate;
    }
    return null;
  }

  /// R66: events repeat like reminders (same JSON as reminders.repeat_rule);
  /// mirrors the database's onespace_event_next_on.
  static bool ruleOccursOn(DateTime original, Map rule, DateTime selected) {
    final start = day(original), d = day(selected);
    if (d.isBefore(start)) return false;
    final until = DateTime.tryParse(rule['until']?.toString() ?? '');
    if (until != null && d.isAfter(day(until))) return false;
    final n = ((rule['interval'] as num?)?.toInt() ?? 1).clamp(1, 999);
    final elapsed = calendarDaysUntil(start, d);
    switch (rule['freq']?.toString()) {
      case 'daily':
        return elapsed % n == 0;
      case 'weekly':
        final days = [for (final x in (rule['weekdays'] as List? ?? const [])) if (x is num) x.toInt()];
        if (!(days.isEmpty ? [start.weekday] : days).contains(d.weekday)) return false;
        final weeks = calendarDaysUntil(start.subtract(Duration(days: start.weekday - 1)),
            d.subtract(Duration(days: d.weekday - 1))) ~/ 7;
        return weeks % n == 0;
      case 'monthly':
        return d.day == start.day && ((d.year - start.year) * 12 + d.month - start.month) % n == 0;
      case 'yearly':
        return d.day == start.day && d.month == start.month && (d.year - start.year) % n == 0;
      default:
        return d == start;
    }
  }

  static bool occursOn({
    required DateTime original,
    required String recurrence,
    required DateTime selected,
    Object? rule,
  }) {
    if (rule is Map) return ruleOccursOn(original, rule, selected);
    if (recurrence == 'yearly') {
      return original.month == selected.month &&
          original.day == selected.day &&
          isValid(selected.year, original.month, original.day);
    }
    return original.year == selected.year &&
        original.month == selected.month &&
        original.day == selected.day;
  }

  static int calendarDaysUntil(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day)
          .difference(DateTime.utc(a.year, a.month, a.day))
          .inDays;

  static String sqlDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
