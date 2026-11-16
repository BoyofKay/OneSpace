import 'package:onespace/l10n/phrases.dart';

/// R77: calendar-correct distance between two days, shown in the units that
/// matter at that size ("major" + "minor"):
///   0 → Today · 1 → Tomorrow / Yesterday · < 14 days → days
///   < 2 months → weeks + days · < 1 year → months + days
///   ≥ 1 year → years + months (or years + days when months are 0)
class SmartSpan {
  const SmartSpan({required this.years, required this.months, required this.days,
    required this.totalDays, required this.future});
  final int years, months, days, totalDays;
  /// The point is after the reference day ("to go").
  final bool future;

  int get weeks => totalDays ~/ 7;
  int get weekDays => totalDays % 7;
  bool get isToday => totalDays == 0;

  /// [from] is the reference (usually today); [to] is the point.
  static SmartSpan between(DateTime from, DateTime to) {
    var a = DateTime(from.year, from.month, from.day);
    var b = DateTime(to.year, to.month, to.day);
    final future = b.isAfter(a);
    if (future) { final t = a; a = b; b = t; }
    // Now a >= b: count from b up to a.
    final total = DateTime.utc(a.year, a.month, a.day).difference(DateTime.utc(b.year, b.month, b.day)).inDays;
    var years = a.year - b.year;
    var months = a.month - b.month;
    var days = a.day - b.day;
    if (days < 0) {
      months -= 1;
      days += DateTime(b.year, b.month + 1, 0).day; // rest of b's month
    }
    if (months < 0) { years -= 1; months += 12; }
    return SmartSpan(years: years, months: months, days: days, totalDays: total, future: future);
  }

  /// (major, minor) in the right units; minor may be empty.
  (String, String) parts() {
    if (totalDays == 0) return (tt('Today'), '');
    if (totalDays == 1) return (tt(future ? 'Tomorrow' : 'Yesterday'), '');
    if (totalDays < 14) return (SmartUnits.format(totalDays, 'day'), '');
    if (years == 0 && (months < 2)) {
      return (SmartUnits.format(weeks, 'week'), weekDays == 0 ? '' : SmartUnits.format(weekDays, 'day'));
    }
    if (years == 0) {
      return (SmartUnits.format(months, 'month'), days == 0 ? '' : SmartUnits.format(days, 'day'));
    }
    if (months > 0) return (SmartUnits.format(years, 'year'), SmartUnits.format(months, 'month'));
    return (SmartUnits.format(years, 'year'), days == 0 ? '' : SmartUnits.format(days, 'day'));
  }

  /// "2 years 3 months" (no direction).
  String get label {
    final (major, minor) = parts();
    if (minor.isEmpty) return major;
    return OneSpacePhrases.arabic ? '$major و$minor' : '$major $minor';
  }

  /// "2 years 3 months ago" / "in 3 weeks" / "Today".
  String get sentence {
    if (totalDays <= 1) return label;
    return OneSpacePhrases.arabic
      ? (future ? 'بعد $label' : 'منذ $label')
      : (future ? 'in $label' : '$label ago');
  }

  /// "to go" / "since" caption under a big number.
  String get caption => isToday ? '' : tt(future ? 'to go' : 'since');
}

class SmartUnits {
  const SmartUnits._();
  static const _en = {'day': ('day', 'days'), 'week': ('week', 'weeks'), 'month': ('month', 'months'),
    'year': ('year', 'years'), 'hour': ('hour', 'hours')};
  // Arabic: 1 · 2 (dual) · 3–10 (plural) · 11+ (singular accusative).
  static const _ar = {
    'day': ('يوم', 'يومان', 'أيام', 'يومًا'),
    'week': ('أسبوع', 'أسبوعان', 'أسابيع', 'أسبوعًا'),
    'month': ('شهر', 'شهران', 'أشهر', 'شهرًا'),
    'year': ('سنة', 'سنتان', 'سنوات', 'سنة'),
    'hour': ('ساعة', 'ساعتان', 'ساعات', 'ساعة'),
  };

  static String number(int n) {
    final s = n.abs().toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  static String format(int n, String unit, {bool? arabic}) {
    if (arabic ?? OneSpacePhrases.arabic) {
      final f = _ar[unit]!;
      if (n == 1) return f.$1;
      if (n == 2) return f.$2;
      final mod = n % 100;
      return '${number(n)} ${mod >= 3 && mod <= 10 ? f.$3 : f.$4}';
    }
    final f = _en[unit]!;
    return '${number(n)} ${n == 1 ? f.$1 : f.$2}';
  }
}

/// A round number worth celebrating: 100 / 500 / 1,000 … days, or the next
/// whole year. Only for points in the past.
class CounterMilestone {
  const CounterMilestone(this.label, this.on, this.inDays);
  final String label;
  final DateTime on;
  final int inDays;

  static const _dayMarks = [100, 200, 300, 365, 500, 730, 1000, 1500, 2000, 2500, 3000, 4000, 5000,
    6000, 7000, 7500, 8000, 9000, 10000, 12500, 15000, 20000, 25000, 30000];

  static CounterMilestone? next(DateTime point, DateTime today) {
    final p = DateTime(point.year, point.month, point.day);
    final t = DateTime(today.year, today.month, today.day);
    if (!p.isBefore(t)) return null;
    final elapsed = DateTime.utc(t.year, t.month, t.day).difference(DateTime.utc(p.year, p.month, p.day)).inDays;
    CounterMilestone? best;
    for (final m in _dayMarks) {
      if (m > elapsed) {
        final on = DateTime(p.year, p.month, p.day + m);
        best = CounterMilestone(SmartUnits.format(m, 'day'), on, m - elapsed);
        break;
      }
    }
    // The next whole year, if it comes first.
    var years = t.year - p.year;
    var anniversary = _safe(p.year + years, p.month, p.day);
    if (!anniversary.isAfter(t)) { years += 1; anniversary = _safe(p.year + years, p.month, p.day); }
    final yearDays = DateTime.utc(anniversary.year, anniversary.month, anniversary.day)
      .difference(DateTime.utc(t.year, t.month, t.day)).inDays;
    if (years >= 1 && (best == null || yearDays <= best.inDays)) {
      return CounterMilestone(SmartUnits.format(years, 'year'), anniversary, yearDays);
    }
    return best;
  }

  static DateTime _safe(int y, int m, int d) {
    final last = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, d > last ? last : d);
  }

  /// The next time a yearly point comes round (today counts).
  static DateTime nextYearly(DateTime point, DateTime today) {
    final t = DateTime(today.year, today.month, today.day);
    var d = _safe(t.year, point.month, point.day);
    if (d.isBefore(t)) d = _safe(t.year + 1, point.month, point.day);
    return d;
  }
}
