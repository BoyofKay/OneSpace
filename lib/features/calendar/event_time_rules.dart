import 'package:material_ui/material_ui.dart' show TimeOfDay;

/// Start/end rules for timed events (same day).
class EventTimeRules {
  static int _m(TimeOfDay t) => t.hour * 60 + t.minute;
  static TimeOfDay _t(int minutes) => TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  /// Picking a start moves the end to one hour later (kept on the same day:
  /// a late start ends at 23:59 at the latest).
  static TimeOfDay endFor(TimeOfDay start) {
    final m = _m(start) + 60;
    return _t(m > 23 * 60 + 59 ? 23 * 60 + 59 : m);
  }

  /// The end must be strictly after the start.
  static bool validEnd(TimeOfDay start, TimeOfDay end) => _m(end) > _m(start);

  /// The latest start that still leaves room for an end.
  static bool validStart(TimeOfDay start) => _m(start) < 23 * 60 + 59;
}
