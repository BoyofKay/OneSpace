/// R47: repeating reminders. The database computes every occurrence from the
/// stored rule (in a fixed IANA zone, daylight-saving safe); this class only
/// builds, reads and describes the rule for the editor and the list.
class ReminderRepeat {
  const ReminderRepeat({
    this.preset = 'none',
    this.interval = 1,
    this.weekdays = const {1},
    this.extraTimes = const [],
    this.until,
  });

  /// none · daily · weekdays · weekly · monthly · yearly
  final String preset;
  final int interval;

  /// ISO weekdays, 1 = Monday … 7 = Sunday (weekly only).
  final Set<int> weekdays;

  /// Additional "HH:MM" times on the same day, besides the main time.
  final List<String> extraTimes;
  final DateTime? until;

  static const presets = ['none', 'daily', 'weekdays', 'weekly', 'monthly', 'yearly'];
  static const presetLabels = {
    'none': 'Does not repeat',
    'daily': 'Every day',
    'weekdays': 'Every weekday (Mon–Fri)',
    'weekly': 'Every week on…',
    'monthly': 'Every month',
    'yearly': 'Every year',
  };
  static const dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  bool get repeats => preset != 'none';

  ReminderRepeat copyWith({String? preset, int? interval, Set<int>? weekdays,
      List<String>? extraTimes, DateTime? until, bool clearUntil = false}) =>
    ReminderRepeat(
      preset: preset ?? this.preset,
      interval: interval ?? this.interval,
      weekdays: weekdays ?? this.weekdays,
      extraTimes: extraTimes ?? this.extraTimes,
      until: clearUntil ? null : (until ?? this.until),
    );

  static String hhmm(int hour, int minute) =>
    hour.toString().padLeft(2, '0') + ':' + minute.toString().padLeft(2, '0');

  /// All times of day, main time first then extras, unique and sorted.
  static List<String> allTimes(String mainTime, List<String> extras) {
    final set = <String>{mainTime, ...extras};
    final list = set.toList()..sort();
    return list.take(6).toList();
  }

  /// The JSON stored in reminders.repeat_rule, or null for one-time.
  Map<String, dynamic>? toRule({required DateTime start, required String timeZone}) {
    if (!repeats) return null;
    final main = hhmm(start.hour, start.minute);
    final freq = preset == 'weekdays' ? 'weekly' : preset;
    final days = preset == 'weekdays'
        ? <int>{1, 2, 3, 4, 5}
        : preset == 'weekly'
            ? (weekdays.isEmpty ? {start.weekday} : weekdays)
            : <int>{};
    final u = until;
    return {
      'freq': freq,
      'interval': preset == 'weekdays' ? 1 : interval.clamp(1, 99),
      if (freq == 'weekly') 'weekdays': (days.toList()..sort()),
      'times': allTimes(main, extraTimes),
      'tz': timeZone,
      'until': u == null ? null : _date(u),
    };
  }

  /// Reads a stored rule back into editor state (main time = start time).
  static ReminderRepeat fromRule(Object? raw, {DateTime? start}) {
    if (raw is! Map) return const ReminderRepeat();
    final freq = raw['freq']?.toString() ?? 'none';
    final interval = (raw['interval'] as num?)?.toInt() ?? 1;
    final days = <int>{
      for (final d in (raw['weekdays'] as List? ?? const []))
        if (int.tryParse(d.toString()) != null) int.parse(d.toString()),
    };
    final main = start == null ? null : hhmm(start.hour, start.minute);
    final times = [
      for (final t in (raw['times'] as List? ?? const [])) t.toString(),
    ]..removeWhere((t) => t == main);
    final untilText = raw['until']?.toString();
    String preset = freq;
    if (freq == 'weekly' && interval == 1 &&
        days.length == 5 && days.containsAll({1, 2, 3, 4, 5})) {
      preset = 'weekdays';
    }
    if (!presets.contains(preset)) preset = 'none';
    return ReminderRepeat(
      preset: preset,
      interval: interval,
      weekdays: days.isEmpty ? const {1} : days,
      extraTimes: times,
      until: untilText == null ? null : DateTime.tryParse(untilText),
    );
  }

  /// Human summary such as "Every day at 8:00 AM and 8:00 PM".
  static String describe(Object? raw) {
    if (raw is! Map) return '';
    final freq = raw['freq']?.toString() ?? '';
    final n = (raw['interval'] as num?)?.toInt() ?? 1;
    final days = [
      for (final d in (raw['weekdays'] as List? ?? const []))
        int.tryParse(d.toString()) ?? 0,
    ]..sort();
    final times = [
      for (final t in (raw['times'] as List? ?? const [])) clock(t.toString()),
    ];
    String head;
    if (freq == 'daily') {
      head = n == 1 ? 'Every day' : 'Every $n days';
    } else if (freq == 'weekly') {
      final names = [for (final d in days) if (d >= 1 && d <= 7) dayShort[d - 1]];
      if (n == 1 && days.length == 5 && days.every((d) => d <= 5)) {
        head = 'Every weekday';
      } else if (days.length == 7 && n == 1) {
        head = 'Every day';
      } else {
        head = (n == 1 ? 'Every week' : 'Every $n weeks') + ' on ' + names.join(', ');
      }
    } else if (freq == 'monthly') {
      head = n == 1 ? 'Every month' : 'Every $n months';
    } else if (freq == 'yearly') {
      head = n == 1 ? 'Every year' : 'Every $n years';
    } else {
      return '';
    }
    final at = times.isEmpty ? '' : ' at ' + _joinAnd(times);
    final until = raw['until']?.toString();
    return head + at + (until == null || until.isEmpty ? '' : ' · until ' + until);
  }

  static String clock(String hhmmText) {
    final parts = hhmmText.split(':');
    if (parts.length != 2) return hhmmText;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1];
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m ${h >= 12 ? 'PM' : 'AM'}';
  }

  static String _joinAnd(List<String> items) {
    if (items.length <= 1) return items.join();
    return items.sublist(0, items.length - 1).join(', ') + ' and ' + items.last;
  }

  static String _date(DateTime d) =>
    d.year.toString().padLeft(4, '0') + '-' +
    d.month.toString().padLeft(2, '0') + '-' + d.day.toString().padLeft(2, '0');

  /// Plain-language name for system and partner actions in the history.
  static String actionLabel(String action) {
    switch (action) {
      case 'done': return 'Done';
      case 'follow_up': return 'Needs follow-up';
      case 'snooze': return 'Snoozed';
      case 'reopen': return 'Reopened';
      case 'missed': return 'Missed';
      case 'source_closed': return 'Linked item closed';
      case 'deferred': return 'Held until wake-up';
      default: return action.replaceAll('_', ' ');
    }
  }
}
