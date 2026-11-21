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
  /// The day scrolls with the page (no inner scroll area to get stuck in);
  /// it opens near the current hour (or 7:00 on other days).
  final GlobalKey _startHour = GlobalKey();
  late final int _start;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = CalendarRules.day(now) == CalendarRules.day(widget.day);
    _start = today ? (now.hour - 2).clamp(0, 16) : 7;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _startHour.currentContext;
      if (ctx != null && mounted) Scrollable.ensureVisible(ctx, alignment: .05,
        duration: const Duration(milliseconds: 250));
    });
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

  /// The timeline follows who the event is for (its participants), not who
  /// can see it: for both of us it spans both timelines, otherwise it sits in
  /// that person's timeline. Visibility only decides who sees it at all.
  int _column(Map<String, dynamic> e) {
    final who = e['for_user_id']?.toString();
    if (who == null) return widget.people.length > 1 ? -1 : 0;
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
      // Overlapping events sit side by side instead of on top of each other.
      final placed = <({Map<String, dynamic> e, DateTime st, DateTime end, double top, double height, int col})>[];
      for (final e in widget.timed) {
        final st = DateTime.tryParse(e['starts_at'].toString())?.toLocal();
        if (st == null) continue;
        final end = DateTime.tryParse(e['ends_at']?.toString() ?? '')?.toLocal() ?? st.add(const Duration(hours: 1));
        final top = _y(st).clamp(0.0, 24 * hh - 24).toDouble();
        final height = (_y(end) - _y(st)).clamp(28.0, 24 * hh - top).toDouble();
        placed.add((e: e, st: st, end: end, top: top, height: height, col: _column(e)));
      }
      final lanes = CoupleDayLanes.assign([
        for (final p in placed) (top: p.top, bottom: p.top + p.height, col: p.col),
      ], columns: n);
      final area = colW * n;
      for (var i = 0; i < placed.length; i++) {
        final p = placed[i];
        final lane = lanes[i];
        final shared = p.col < 0;
        final e = p.e;
        eventBoxes.add(Positioned(top: p.top, height: p.height,
          left: gutter + lane.left * area + 2, width: lane.width * area - 4,
          child: Material(
            color: shared ? scheme.primaryContainer : scheme.secondaryContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: scheme.surface, width: 1.5)),
            child: InkWell(borderRadius: BorderRadius.circular(8), onTap: () => widget.onOpen(e),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${e['visibility'] == 'private' ? '🔒 ' : ''}${tt(e['title']?.toString() ?? '')}',
                    maxLines: p.height > 56 ? 2 : 1, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600,
                      color: shared ? scheme.onPrimaryContainer : scheme.onSecondaryContainer)),
                  if (p.height > 40) Text('${hm(p.st)} – ${hm(p.end)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: shared ? scheme.onPrimaryContainer : scheme.onSecondaryContainer)),
                ]))))));
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
        SizedBox(
          height: 24 * hh,
          child: Stack(children: [
            // Hour lines and labels (my local time).
            for (var h = 0; h < 24; h++) Positioned(top: h * hh, left: 0, right: 0, child: Row(children: [
              SizedBox(key: h == _start ? _startHour : null, width: gutter, child: Text(hm(DateTime(2000, 1, 1, h)),
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
            if (people.length > 1)
              for (final h in const [6, 12, 18])
                for (var i = 0; i < people.length; i++) Positioned(top: h * hh + 2, left: gutter + i * colW, width: colW,
                  child: Center(child: Text(people[i].first, style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.outline, fontWeight: FontWeight.w600)))),
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
        ),
        Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 12, runSpacing: 4, children: [
          _legend(CoupleColors.sleep, 'Sleep'),
          _legend(CoupleColors.workBand, 'Working hours'),
          if (people.length > 1) _legend(scheme.primaryContainer, 'For both of us'),
          _legend(scheme.secondaryContainer, people.length > 1 ? 'For one of you' : 'Event'),
          Text('🔒 ${tt('Only me (private)')}', style: Theme.of(context).textTheme.bodySmall),
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


/// Where each timeline event goes across the whole day area (0 = left
/// edge, 1 = right edge). With two people, "only me" events (col 0) sit on
/// the left, "only my partner" (col 1) on the right, and "both of us"
/// (col < 0) in the middle. When a both-of-us event overlaps one-person
/// events, the group is split into thirds: mine, both of us (straddling the
/// two lanes), my partner's. Events of the same kind that overlap sit side
/// by side inside their part.
class CoupleDayLanes {
  static List<({double left, double width})> assign(
      List<({double top, double bottom, int col})> boxes, {int columns = 2}) {
    final n = boxes.length;
    int kind(int i) => columns < 2 ? 0 : (boxes[i].col < 0 ? -1 : boxes[i].col.clamp(0, 1));
    bool clash(int a, int b) => boxes[a].top < boxes[b].bottom && boxes[b].top < boxes[a].bottom &&
      (kind(a) < 0 || kind(b) < 0 || kind(a) == kind(b));
    final group = List<int>.generate(n, (i) => i);
    int find(int i) => group[i] == i ? i : group[i] = find(group[i]);
    for (var a = 0; a < n; a++) {
      for (var b = a + 1; b < n; b++) {
        if (clash(a, b)) group[find(a)] = find(b);
      }
    }
    final out = List<({double left, double width})>.filled(n, (left: 0, width: 1));
    final members = <int, List<int>>{};
    for (var i = 0; i < n; i++) {
      (members[find(i)] ??= []).add(i);
    }
    for (final list in members.values) {
      // The part of the width each kind of event may use in this group.
      final kinds = {for (final i in list) kind(i)};
      final part = <int, ({double left, double width})>{};
      if (columns < 2) {
        part[0] = (left: 0, width: 1);
      } else if (!kinds.contains(-1)) {
        part[0] = (left: 0, width: .5);
        part[1] = (left: .5, width: .5);
      } else {
        final l = kinds.contains(0) ? 1 / 3 : 0.0;
        final r = kinds.contains(1) ? 2 / 3 : 1.0;
        part[0] = (left: 0, width: 1 / 3);
        part[-1] = (left: l, width: r - l);
        part[1] = (left: 2 / 3, width: 1 / 3);
      }
      for (final k in kinds) {
        final mine = list.where((i) => kind(i) == k).toList()
          ..sort((a, b) => boxes[a].top.compareTo(boxes[b].top));
        final laneEnds = <double>[];
        final laneOf = <int, int>{};
        for (final i in mine) {
          var lane = laneEnds.indexWhere((end) => end <= boxes[i].top);
          if (lane < 0) { laneEnds.add(boxes[i].bottom); lane = laneEnds.length - 1; }
          else { laneEnds[lane] = boxes[i].bottom; }
          laneOf[i] = lane;
        }
        final region = part[k]!;
        final w = region.width / laneEnds.length;
        for (final i in mine) {
          out[i] = (left: region.left + laneOf[i]! * w, width: w);
        }
      }
    }
    return out;
  }
}
