import 'package:timezone/data/latest_all.dart' as tzdb;
import 'package:timezone/timezone.dart' as tz;

/// Wall-clock times in a named (IANA) time zone, DST included.
class ZoneTime {
  const ZoneTime._();
  static bool _ready = false;
  static void _ensure() {
    if (!_ready) { tzdb.initializeTimeZones(); _ready = true; }
  }

  static tz.Location? _loc(String? zone) {
    if (zone == null || zone.isEmpty) return null;
    try { _ensure(); return tz.getLocation(zone); } catch (_) { return null; }
  }

  /// The wall-clock time an instant shows in [zone] (phone time if unknown).
  static DateTime wall(DateTime instant, String? zone) {
    final l = _loc(zone);
    if (l == null) return instant.toLocal();
    final t = tz.TZDateTime.from(instant.toUtc(), l);
    return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
  }

  /// The instant (UTC) of a wall-clock time in [zone].
  static DateTime instant(int y, int m, int d, int h, int min, String? zone) {
    final l = _loc(zone);
    if (l == null) return DateTime(y, m, d, h, min).toUtc();
    return tz.TZDateTime(l, y, m, d, h, min).toUtc();
  }

  /// Offset of [zone] from UTC right now, in minutes.
  static int offsetMinutes(String? zone, [DateTime? at]) {
    final now = (at ?? DateTime.now()).toUtc();
    final l = _loc(zone);
    if (l == null) return now.toLocal().timeZoneOffset.inMinutes;
    return tz.TZDateTime.from(now, l).timeZoneOffset.inMinutes;
  }

  static bool differs(String? a, String? b, [DateTime? at]) =>
    a != null && b != null && a != b && offsetMinutes(a, at) != offsetMinutes(b, at);

  /// "Europe/London" → "London".
  static String city(String? zone) =>
    (zone ?? '').split('/').last.replaceAll('_', ' ');
}
