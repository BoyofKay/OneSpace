import '../calendar/calendar_rules.dart';

/// Dates are displayed in the viewer's local calendar, not parsed as UTC
/// instants. The backend already respects each viewer's RLS and snoozes.
class TodayAttentionItem {
  const TodayAttentionItem({
    required this.id,
    required this.activityId,
    required this.title,
    required this.kind,
    required this.priority,
    this.dueOn,
    this.source='activity',
    this.reason,
    this.score=5,
  });

  final String id;
  final String activityId;
  final String title;
  final String kind;
  final String priority;
  final DateTime? dueOn;
  final String source;
  final String? reason;
  final int score;

  /// Acknowledging something is different from changing the source object.
  /// The attention row is personal; activities and tasks stay collaborative.
  static List<TodayAttentionItem> fromActionQueue(List<dynamic> raw){
    final unique=<String,TodayAttentionItem>{};
    for(final row in raw){
      if(row is! Map)continue;
      final source=row['source']?.toString()??'';
      if(!const ['activity','task','checkin'].contains(source))continue;
      final id=row['id']?.toString()??'';
      if(id.isEmpty)continue;
      final key=source+':'+id;
      final item=TodayAttentionItem(
        id:id,
        activityId:row['activity_id']?.toString()??'',
        title:row['title']?.toString()??'Needs attention',
        kind:row['kind']?.toString()??'activity',
        priority:row['priority']?.toString()??'normal',
        dueOn:DateTime.tryParse(row['due_on']?.toString()??''),
        source:source,
        reason:row['reason']?.toString(),
        score:(row['score'] as num?)?.toInt()??5,
      );
      final existing=unique[key];
      if(existing==null||item.score<existing.score)unique[key]=item;
    }
    final result=unique.values.toList()
      ..sort((a,b){
        final rank=a.score.compareTo(b.score);
        if(rank!=0)return rank;
        final date=(a.dueOn??DateTime(2100))
          .compareTo(b.dueOn??DateTime(2100));
        return date!=0?date:a.title.compareTo(b.title);
      });
    return result;
  }

  bool get isReminder => kind == 'reminder';

  int? daysUntil(DateTime now) =>
      dueOn == null ? null :
      CalendarRules.calendarDaysUntil(CalendarRules.day(now), dueOn!);

  String relativeLabel(DateTime now) {
    final days = daysUntil(now);
    if (days == null) {
      return priority == 'urgent' ? 'Urgent · no due date' :
        'High priority · no due date';
    }
    if (days < 0) return 'Overdue by ${-days} day${days == -1 ? '' : 's'}';
    if (days == 0) return 'Due today';
    if (days == 1) return 'Due tomorrow';
    return 'Due in $days days';
  }

  static List<TodayAttentionItem> parse(List<dynamic> raw, DateTime now) {
    final result = <TodayAttentionItem>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final id = item['id']?.toString();
      final activityId = item['activity_id']?.toString();
      if (id == null || id.isEmpty || activityId == null ||
          activityId.isEmpty) {
        continue;
      }
      final due = DateTime.tryParse(item['due_on']?.toString() ?? '');
      result.add(TodayAttentionItem(
        id: id,
        activityId: activityId,
        title: item['title']?.toString() ?? '',
        kind: item['kind']?.toString() ?? 'activity',
        priority: item['priority']?.toString() ?? 'normal',
        dueOn: due,
      ));
    }
    int urgency(TodayAttentionItem item) {
      final days = item.daysUntil(now);
      if (days != null && days < 0) return 0;
      if (days == 0) return 1;
      if (item.isReminder) return 2;
      if (item.priority == 'urgent' || item.priority == 'high') return 3;
      return 4;
    }
    result.sort((a,b) {
      final first = urgency(a).compareTo(urgency(b));
      if (first != 0) return first;
      final date = (a.dueOn ?? DateTime(2100))
          .compareTo(b.dueOn ?? DateTime(2100));
      return date != 0 ? date : a.title.compareTo(b.title);
    });
    return result;
  }

  static List<TodayCalendarEntry> upcomingEvents(
    List<dynamic> raw, DateTime now, {int horizonDays = 7}
  ) {
    final result = <TodayCalendarEntry>[];
    for (final rawEvent in raw) {
      if (rawEvent is! Map) continue;
      final original = DateTime.tryParse(
        rawEvent['event_date']?.toString() ?? '');
      if (original == null) continue;
      final next = CalendarRules.nextOccurrence(
        original:original,
        recurrence:rawEvent['recurrence']?.toString() ?? 'none',
        today:now,
      );
      if (next == null ||
          CalendarRules.calendarDaysUntil(CalendarRules.day(now),next) >
              horizonDays) {
        continue;
      }
      result.add(TodayCalendarEntry(
        title:rawEvent['title']?.toString() ?? '',
        date:next,
        kind:rawEvent['kind']?.toString() ?? 'event',
      ));
    }
    result.sort((a,b) {
      final date = a.date.compareTo(b.date);
      return date == 0 ? a.title.compareTo(b.title) : date;
    });
    return result;
  }
}

class TodayCalendarEntry {
  const TodayCalendarEntry({
    required this.title,
    required this.date,
    required this.kind,
    this.source='calendar',
    this.activityId,
    this.experienceId,
    this.tripId,
    this.occasionId,
  });
  final String title;
  final DateTime date;
  final String kind;
  final String source;
  final String? activityId;
  final String? experienceId;
  final String? tripId;
  final String? occasionId;
}
