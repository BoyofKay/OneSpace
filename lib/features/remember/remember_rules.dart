import '../../features/calendar/calendar_rules.dart';

/// Date-only, timezone-safe presentation rules for Remember.
class RememberOccurrence {
  const RememberOccurrence(this.title, this.date, this.kind);
  final String title;
  final DateTime date;
  final String kind;
}

class RememberDue {
  const RememberDue(this.id, this.title, this.date, this.kind);
  final String id;
  final String title;
  final DateTime date;
  final String kind;
}

class RememberRules {
  const RememberRules._();

  static List<RememberOccurrence> upcomingEvents(
    List<dynamic> raw,
    DateTime now, {
    int horizonDays = 60,
  }) {
    final today = CalendarRules.day(now);
    final result = <RememberOccurrence>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final source = DateTime.tryParse(item['event_date']?.toString() ?? '');
      if (source == null) continue;
      final next = CalendarRules.nextOccurrence(
        original: source,
        recurrence: item['recurrence']?.toString() ?? 'none',
        today: today,
      );
      if (next == null ||
          CalendarRules.calendarDaysUntil(today, next) > horizonDays) {
        continue;
      }
      result.add(RememberOccurrence(
        item['title']?.toString() ?? '',
        next,
        item['kind']?.toString() ?? 'event',
      ));
    }
    result.sort((a, b) {
      final compared = a.date.compareTo(b.date);
      return compared != 0 ? compared : a.title.compareTo(b.title);
    });
    return result;
  }

  static List<RememberDue> upcomingDues(List<dynamic> raw) {
    final result = <RememberDue>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final date = DateTime.tryParse(item['due_on']?.toString() ?? '');
      if (date == null) continue;
      result.add(RememberDue(
        item['id']?.toString() ?? '',
        item['title']?.toString() ?? '',
        date,
        item['type']?.toString() ?? 'todo',
      ));
    }
    result.sort((a, b) {
      final compared = a.date.compareTo(b.date);
      return compared != 0 ? compared : a.title.compareTo(b.title);
    });
    return result;
  }

  static int daysFromToday(DateTime date, DateTime now) =>
      CalendarRules.calendarDaysUntil(CalendarRules.day(now), date);
}
