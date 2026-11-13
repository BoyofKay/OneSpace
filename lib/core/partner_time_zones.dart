import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Explicit IANA time zones. Device location is never requested or guessed.
/// IANA rules handle daylight-saving changes for past/future instants.
class PartnerTimeZones {
  const PartnerTimeZones._();

  static bool _ready = false;

  static void initialize() {
    if (_ready) return;
    tzdata.initializeTimeZones();
    _ready = true;
  }

  static List<String> all() {
    initialize();
    return tz.timeZoneDatabase.locations.keys.where((name) =>
      !name.startsWith('Etc/GMT') &&
      !name.startsWith('SystemV/')).toList()..sort();
  }

  static bool valid(String? name) {
    if (name == null || name.isEmpty) return false;
    initialize();
    return tz.timeZoneDatabase.locations.containsKey(name);
  }

  static tz.TZDateTime? inZone(String? zone, DateTime instant) {
    if (!valid(zone)) return null;
    return tz.TZDateTime.from(instant.toUtc(), tz.getLocation(zone!));
  }

  static String timeLabel(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return '$hour:${value.minute.toString().padLeft(2, '0')} '
        '${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  static String dateLabel(DateTime value) {
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug',
      'Sep','Oct','Nov','Dec'];
    return '${days[value.weekday - 1]}, ${months[value.month - 1]} '
        '${value.day}';
  }

  static String zoneLabel(String zone) =>
      zone.split('/').last.replaceAll('_', ' ');

  static String offsetLabel(Duration offset) {
    final minutes = offset.inMinutes;
    final sign = minutes < 0 ? '-' : '+';
    final absMinutes = minutes.abs();
    return 'UTC$sign${(absMinutes ~/ 60).toString().padLeft(2,'0')}:'
        '${(absMinutes % 60).toString().padLeft(2,'0')}';
  }

  static int? differenceHoursMinutes(
    String? mine, String? partner, DateTime instant,
  ) {
    final mineNow = inZone(mine, instant);
    final partnerNow = inZone(partner, instant);
    if (mineNow == null || partnerNow == null) return null;
    return partnerNow.timeZoneOffset.inMinutes -
      mineNow.timeZoneOffset.inMinutes;
  }

  static String differenceLabel(int minutes) {
    if (minutes == 0) return 'Same local time';
    final hours = minutes.abs() ~/ 60;
    final mins = minutes.abs() % 60;
    final amount = [
      if (hours > 0) '$hours hour${hours == 1 ? '' : 's'}',
      if (mins > 0) '$mins min',
    ].join(' ');
    return 'Partner is $amount ${minutes > 0 ? 'ahead' : 'behind'}';
  }
}
