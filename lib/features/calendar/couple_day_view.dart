import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onespace/l10n/phrases.dart';

import '../../core/device_time_zone.dart';
import '../../core/zone_time.dart';
import 'calendar_rules.dart';

/// One partner's working week, hours and sleep, in their own time zone.
class CouplePerson {
  const CouplePerson({required this.id, required this.first, this.zone,
    this.workDays = const {}, this.workStart, this.workEnd, this.sleepStart, this.sleepEnd});
  final String id, first;
  final String? zone;
  final Set<int> workDays; // 1 = Monday … 7 = Sunday
  final TimeOfDay? workStart, workEnd, sleepStart, sleepEnd;

  String get initial => first.isEmpty ? '?' : first.characters.first.toUpperCase();

  static TimeOfDay? _t(Object? v) {
    final parts = (v?.toString() ?? '').split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
    return h == null || m == null ? null : TimeOfDay(hour: h, minute: m);
  }

  /// Me first, then my partner (when there is one).
  static Future<List<CouplePerson>> load(String? spaceId) async {
    final db = Supabase.instance.client;
    final me = db.auth.currentUser?.id;
    if (me == null) return const [];
    var ids = <String>[me];
    if (spaceId != null && spaceId.isNotEmpty) {
      final rows = await db.from('space_members').select('user_id').eq('space_id', spaceId);
      ids = {me, ...rows.map((r) => r['user_id'].toString())}.toList();
    }
    final rows = await db.from('profiles').select(
      'id,display_name,time_zone,work_days,work_start_local,work_end_local,sleep_start_local,sleep_end_local')
      .inFilter('id', ids);
    final phone = await DeviceTimeZone.readPhone();
    final out = <CouplePerson>[];
    for (final id in ids) {
      final r = rows.where((x) => x['id'] == id).firstOrNull;
      if (r == null) continue;
      out.add(CouplePerson(
        id: id,
        first: (r['display_name'] ?? '').toString().trim().split(RegExp(r'\s+')).first,
        zone: id == me ? (phone ?? r['time_zone']?.toString()) : r['time_zone']?.toString(),
        workDays: {for (final d in (r['work_days'] as List? ?? const [])) (d as num).toInt()},
        workStart: _t(r['work_start_local']), workEnd: _t(r['work_end_local']),
        sleepStart: _t(r['sleep_start_local']), sleepEnd: _t(r['sleep_end_local']),
      ));
    }
    return out;
  }

  bool offOn(DateTime day, List<Map<String, dynamic>> daysOff) => daysOff.any((r) =>
    r['user_id'] == id && r['off_date']?.toString() == CalendarRules.sqlDate(day));

  /// 'off', 'work' or null for a calendar day.
  String? statusOn(DateTime day, List<Map<String, dynamic>> daysOff) {
    if (offOn(day, daysOff)) return 'off';
    if (workDays.contains(day.weekday)) return 'work';
    return null;
  }
}

/// Month cell marker: each partner's initial, coloured for work or day off.
class CoupleDayMarkers extends StatelessWidget {
  const CoupleDayMarkers({super.key, required this.people, required this.day, required this.daysOff});
  final List<CouplePerson> people;
  final DateTime day;
  final List<Map<String, dynamic>> daysOff;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final marks = [
      for (final p in people)
        if (p.statusOn(day, daysOff) case final String s) (p, s),
    ];
    if (marks.isEmpty) return const SizedBox(height: 13);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (final (p, s) in marks) Container(
        width: 13, height: 13, margin: const EdgeInsets.symmetric(horizontal: 1),
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle,
          color: s == 'off' ? CoupleColors.off : CoupleColors.work),
        child: Text(p.initial, style: TextStyle(fontSize: 8, height: 1,
          fontWeight: FontWeight.w700, color: scheme.surface)),
      ),
    ]);
  }
}

class CoupleColors {
  const CoupleColors._();
  static const work = Color(0xFF3B6FB6);
  static const off = Color(0xFF2E8B57);
  static const sleep = Color(0x335C4BA6);
  static const workBand = Color(0x2E3B6FB6);
}

/// Legend under the month grid.
class CoupleMarkersLegend extends StatelessWidget {
  const CoupleMarkersLegend({super.key, required this.people});
  final List<CouplePerson> people;
  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    Widget dot(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
      const SizedBox(width: 4), Text(tt(label), style: small)]);
    return Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 14, runSpacing: 4, children: [
      dot(CoupleColors.work, 'Working day'),
      dot(CoupleColors.off, 'Day off'),
      Text(people.map((p) => '${p.initial} = ${p.first}').join(' · '), style: small),
    ]));
  }
}

/// Day view: one timeline per partner, side by side, names pinned on top,
/// sleep and work hours shaded, shared events across both, a line for now.
class CoupleDayTimeline extends StatefulWidget {
  const CoupleDayTimeline({super.key, required this.people, required this.day,
    required this.timed, required this.daysOff, required this.onOpen, required this.myId});
  final List<CouplePerson> people;
  final DateTime day;
  final List<Map<String, dynamic>> timed;
  final List<Map<String, dynamic>> daysOff;
  final void Function(Map<String, dynamic>) onOpen;
  final String myId;

  @override
  State<CoupleDayTimeline> createState() => _CoupleDayTimelineState();
}

class _CoupleDayTimelineState extends State<CoupleDayTimeline> {
  static const hh = 46.0, gutter = 46.0;
  late final ScrollController scroll;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = CalendarRules.day(now) == CalendarRules.day(widget.day);
    final hour = today ? (now.hour - 2).clamp(0, 16) : 7;
    scroll = ScrollController(initialScrollOffset: hour * hh);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  /// [from, to) in the phone's local time for a band given in the person's zone.
  List<(DateTime, DateTime)> _bands(CouplePerson p, TimeOfDay? a, TimeOfDay? b, {bool workOnly = false}) {
    if (a == null || b == null) return const [];
    final out = <(DateTime, DateTime)>[];
    final dayStart = DateTime(widget.day.year, widget.day.month, widget.day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    // The person's own calendar days that can overlap this local day.
    final theirDay = ZoneTime.wall(dayStart.toUtc(), p.zone);
    for (var i = -1; i <= 1; i++) {
      final d = DateTime(theirDay.year, theirDay.month, theirDay.day + i);
      if (workOnly && (!p.workDays.contains(d.weekday) || p.offOn(d, widget.daysOff))) continue;
      final start = ZoneTime.instant(d.year, d.month, d.day, a.hour, a.minute, p.zone).toLocal();
      var end = ZoneTime.instant(d.year, d.month, d.day, b.hour, b.minute, p.zone).toLocal();
      if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
      final s = start.isBefore(dayStart) ? dayStart : start;
      final e = end.isAfter(dayEnd) ? dayEnd : end;
      if (e.isAfter(s)) out.add((s, e));
    }
    return out;
  }

  double _y(DateTime t) {
    final dayStart = DateTime(widget.day.year, widget.day.month, widget.day.day);
    return t.difference(dayStart).inMinutes / 60 * hh;
  }

  int _column(Map<String, dynamic> e) {
    final shared = e['visibility'] == 'shared' && e['for_user_id'] == null;
    if (shared) return -1;
    final who = (e['for_user_id'] ?? e['created_by'])?.toString();
    final i = widget.people.indexWhere((p) => p.id == who);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final people = widget.people;
    final n = people.isEmpty ? 1 : people.length;
    final now = DateTime.now();
    final myZone = people.isEmpty ? null : people.first.zone;
    final differ = people.length > 1 && ZoneTime.differs(people[0].zone, people[1].zone);
    final loc = MaterialLocalizations.of(context);
    String hm(DateTime t) => loc.formatTimeOfDay(TimeOfDay.fromDateTime(t));

    return LayoutBuilder(builder: (context, box) {
      final colW = (box.maxWidth - gutter) / n;
      final eventBoxes = <Widget>[];
      for (final e in widget.timed) {
        final st = DateTime.tryParse(e['starts_at'].toString())?.toLocal();
        if (st == null) continue;
        final end = DateTime.tryParse(e['ends_at']?.toString() ?? '')?.toLocal() ?? st.add(const Duration(hours: 1));
        final top = _y(st).clamp(0.0, 24 * hh - 24);
        final height = (_y(end) - _y(st)).clamp(24.0, 24 * hh - top);
        final col = _column(e);
        final left = gutter + (col < 0 ? 0 : col * colW) + 3;
        final width = (col < 0 ? colW * n : colW) - 6;
        final shared = col < 0;
        eventBoxes.add(Positioned(top: top, height: height, left: left, width: width,
          child: Material(
            color: shared ? scheme.primaryContainer : scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(borderRadius: BorderRadius.circular(8), onTap: () => widget.onOpen(e),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Text('${hm(st)} ${tt(e['title']?.toString() ?? '')}',
                  maxLines: height > 40 ? 2 : 1, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: shared ? scheme.onPrimaryContainer : scheme.onSecondaryContainer)))))));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Pinned header: first names and, if different, each local time now.
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
          child: Row(children: [
            SizedBox(width: gutter, child: Text(differ ? tt(ZoneTime.city(myZone)) : '',
              style: theme.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
            for (final p in people) Expanded(child: Column(children: [
              Text(p.first.isEmpty ? tt('Partner') : p.first, style: theme.textTheme.titleSmall,
                maxLines: 1, overflow: TextOverflow.ellipsis),
              if (differ) Text('${hm(ZoneTime.wall(now, p.zone))} · ${tt(ZoneTime.city(p.zone))}',
                style: theme.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
          ]),
        ),
        SizedBox(height: 520, child: SingleChildScrollView(controller: scroll, child: SizedBox(
          height: 24 * hh,
          child: Stack(children: [
            // Hour lines and labels (my local time).
            for (var h = 0; h < 24; h++) Positioned(top: h * hh, left: 0, right: 0, child: Row(children: [
              SizedBox(width: gutter, child: Text(hm(DateTime(2000, 1, 1, h)),
                style: theme.textTheme.labelSmall)),
              Expanded(child: Container(height: 1, color: scheme.outlineVariant)),
            ])),
            // Each partner's sleep and work hours.
            for (var i = 0; i < people.length; i++) ...[
              for (final (s, e) in _bands(people[i], people[i].sleepStart, people[i].sleepEnd))
                Positioned(top: _y(s), height: _y(e) - _y(s), left: gutter + i * colW + 2, width: colW - 4,
                  child: _Band(color: CoupleColors.sleep, label: 'Sleep', icon: Icons.bedtime_outlined)),
              for (final (s, e) in _bands(people[i], people[i].workStart, people[i].workEnd, workOnly: true))
                Positioned(top: _y(s), height: _y(e) - _y(s), left: gutter + i * colW + 2, width: colW - 4,
                  child: _Band(color: CoupleColors.workBand, label: 'Work', icon: Icons.work_outline)),
            ],
            if (people.length > 1) Positioned(top: 0, bottom: 0, left: gutter + colW, width: 1,
              child: Container(color: scheme.outlineVariant)),
            // Events: shared ones span both timelines.
            ...eventBoxes,
            // The current time.
            if (CalendarRules.day(now) == CalendarRules.day(widget.day))
              Positioned(top: _y(now) - 1, left: gutter - 6, right: 0, child: Row(children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red)),
                Expanded(child: Container(height: 2, color: Colors.red)),
              ])),
          ]),
        ))),
        Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 12, runSpacing: 4, children: [
          _legend(CoupleColors.sleep, 'Sleep'),
          _legend(CoupleColors.workBand, 'Working hours'),
          if (people.length > 1) _legend(scheme.primaryContainer, 'Shared'),
          _legend(scheme.secondaryContainer, people.length > 1 ? 'Just one of you' : 'Event'),
        ])),
      ]);
    });
  }

  Widget _legend(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 4), Text(tt(label), style: Theme.of(context).textTheme.bodySmall)]);
}

class _Band extends StatelessWidget {
  const _Band({required this.color, required this.label, required this.icon});
  final Color color;
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
    alignment: AlignmentDirectional.topEnd,
    padding: const EdgeInsets.all(3),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: Theme.of(context).colorScheme.outline),
      const SizedBox(width: 2),
      Text(tt(label), style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.outline)),
    ]));
}
