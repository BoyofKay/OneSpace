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
  }) {
    final reference = day(today);
    final source = day(original);
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

  static bool occursOn({
    required DateTime original,
    required String recurrence,
    required DateTime selected,
  }) {
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
