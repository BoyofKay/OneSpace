import '../../core/partner_time_zones.dart';

/// One partner's stated schedule, in their own time zone (spec 3.2).
/// Only what the person set in Profile is used; nothing is guessed.
class StatedSchedule {
  const StatedSchedule({
    required this.timeZone,
    this.workStart,
    this.workEnd,
    this.sleepStart,
    this.sleepEnd,
    this.workDays = const {},
  });

  final String? timeZone;
  /// Minutes after local midnight; null when not set.
  final int? workStart, workEnd, sleepStart, sleepEnd;
  /// ISO weekdays (1 = Monday … 7 = Sunday).
  final Set<int> workDays;

  bool get hasSleep => sleepStart != null && sleepEnd != null;
  bool get hasWork => workStart != null && workEnd != null && workDays.isNotEmpty;
  bool get hasAny => hasSleep || hasWork;

  static int? minutes(Object? raw) {
    final text = raw?.toString() ?? '';
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(text);
    if (match == null) return null;
    final h = int.parse(match.group(1)!), m = int.parse(match.group(2)!);
    if (h > 23 || m > 59) return null;
    return h * 60 + m;
  }

  factory StatedSchedule.fromJson(Map<String, dynamic> raw) => StatedSchedule(
        timeZone: raw['time_zone']?.toString(),
        workStart: minutes(raw['work_start']),
        workEnd: minutes(raw['work_end']),
        sleepStart: minutes(raw['sleep_start']),
        sleepEnd: minutes(raw['sleep_end']),
        workDays: {
          for (final d in (raw['work_days'] as List<dynamic>? ?? const []))
            if (int.tryParse(d.toString()) case final int day
                when day >= 1 && day <= 7)
              day,
        },
      );

  static bool _inRange(int minute, int start, int end) => start <= end
      ? minute >= start && minute < end
      : minute >= start || minute < end; // window crosses midnight

  /// True when this person is awake and off work at [instant].
  bool isFree(DateTime instant) {
    final local = PartnerTimeZones.inZone(timeZone, instant);
    if (local == null) return false;
    final minute = local.hour * 60 + local.minute;
    if (hasSleep && _inRange(minute, sleepStart!, sleepEnd!)) return false;
    if (hasWork && workDays.contains(local.weekday)) {
      // A night shift that ends after midnight belongs to the day it started.
      if (workStart! <= workEnd!) {
        if (_inRange(minute, workStart!, workEnd!)) return false;
      } else {
        final yesterday = local.weekday == 1 ? 7 : local.weekday - 1;
        if (minute >= workStart!) return false;
        if (minute < workEnd! && workDays.contains(yesterday)) return false;
      }
    }
    return true;
  }
}

class TalkWindow {
  const TalkWindow(this.start, this.end);
  final DateTime start, end;
  bool isNow(DateTime now) => !start.isAfter(now) && end.isAfter(now);
}

/// Next stretch of at least [minimum] when both partners are free, searched
/// in 15-minute steps over [horizon]. Null when either schedule is empty or
/// no shared window exists (spec 3.2, backlog B-12).
TalkWindow? nextTalkWindow(StatedSchedule a, StatedSchedule b, DateTime now,
    {Duration horizon = const Duration(hours: 72),
    Duration minimum = const Duration(minutes: 30)}) {
  if (!a.hasAny || !b.hasAny) return null;
  if (!PartnerTimeZones.valid(a.timeZone) || !PartnerTimeZones.valid(b.timeZone)) {
    return null;
  }
  const step = Duration(minutes: 15);
  // Align to the current quarter hour so labels read 6:15, 6:30…
  var cursor = DateTime.fromMillisecondsSinceEpoch(
      now.millisecondsSinceEpoch - now.millisecondsSinceEpoch % step.inMilliseconds,
      isUtc: true);
  final stop = now.add(horizon);
  DateTime? start;
  while (cursor.isBefore(stop)) {
    final free = a.isFree(cursor) && b.isFree(cursor);
    if (free) {
      start ??= cursor.isBefore(now) ? now : cursor;
    } else if (start != null) {
      if (cursor.difference(start) >= minimum) return TalkWindow(start, cursor);
      start = null;
    }
    cursor = cursor.add(step);
  }
  if (start != null && stop.difference(start) >= minimum) {
    return TalkWindow(start, stop);
  }
  return null;
}

/// "Good time to talk: now until 9:00 PM" or "… today 6:30 PM – 9:00 PM",
/// shown in the viewer's own time.
String talkWindowLabel(TalkWindow window, DateTime now, String? myZone) {
  final start = PartnerTimeZones.inZone(myZone, window.start) ?? window.start.toLocal();
  final end = PartnerTimeZones.inZone(myZone, window.end) ?? window.end.toLocal();
  final today = PartnerTimeZones.inZone(myZone, now) ?? now.toLocal();
  final until = PartnerTimeZones.timeLabel(end);
  if (window.isNow(now)) return 'Good time to talk: now until $until';
  final sameDay = start.year == today.year && start.month == today.month &&
      start.day == today.day;
  final tomorrow = today.add(const Duration(days: 1));
  final isTomorrow = start.year == tomorrow.year &&
      start.month == tomorrow.month && start.day == tomorrow.day;
  final day = sameDay ? 'today' : isTomorrow ? 'tomorrow' : PartnerTimeZones.dateLabel(start);
  return 'Next good time to talk: $day ${PartnerTimeZones.timeLabel(start)} – $until';
}
