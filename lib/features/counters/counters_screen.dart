import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:onespace/l10n/phrases.dart';
import '../../core/current_space_cache.dart';
import '../../core/editor_scaffold.dart';
import '../../core/form_kit.dart';
import '../../core/item_menu.dart';
import '../calendar/calendar_rules.dart';
import '../memories/memories_screen.dart';
import '../memories/memory_view_screen.dart';
import 'counter_sources.dart';
import 'smart_duration.dart';

/// R77 (Ahmed's friend's idea): our counters — moments in the past ("since")
/// and the future ("to go"), counted in the units that matter, with photos,
/// place, who was there and links between two points. Only consciously saved
/// counters appear here; other dates stay in their original feature.
class CounterCategories {
  const CounterCategories._();
  static const labels = {
    'love': 'Us', 'family': 'Family', 'home': 'Home', 'travel': 'Travel', 'work': 'Work',
    'study': 'Study', 'health': 'Health', 'life': 'Life', 'other': 'Other'};
  static const emoji = {
    'love': '❤️', 'family': '👨‍👩‍👦', 'home': '🏡', 'travel': '✈️', 'work': '💼',
    'study': '🎓', 'health': '🌿', 'life': '⭐', 'other': '📌'};
  static const suggestions = ['❤️', '💍', '🥂', '🏡', '✈️', '🎂', '👶', '🐶', '🎓', '💼', '🌍', '⭐', '🎉', '🌙', '☕', '🚗'];
}

/// One point on the screen: a saved counter or one that comes from elsewhere.
///
/// R78 (Ahmed): a date that repeats every year shows as TWO points — the day
/// itself (in the past: "5 years 6 months ago") and its next anniversary
/// (coming up: "6th anniversary · in 5 months") — so they never get mixed up.
class CounterPoint {
  CounterPoint({required this.id, required this.title, required this.date, this.emoji = '',
    this.row, this.source, this.yearly = false, this.pinned = false, this.start,
    this.yearKnown = true, this.birthday = false, this.original});
  final String id, title, emoji;
  /// The day itself (for an anniversary point: the original date).
  final DateTime date;
  final Map<String, dynamic>? row;
  /// "Anniversary", "Birthday", "Trip"… for points that come from elsewhere.
  final String? source;
  /// This point is the yearly return of [date].
  final bool yearly, pinned;
  /// When the wait began, for the progress bar of an upcoming point.
  final DateTime? start;
  /// False when only day and month are known (a birthday without the year).
  final bool yearKnown;
  final bool birthday;
  /// For the "day itself" point of a yearly counter: its anniversary twin id.
  final String? original;
  bool get saved => row != null;

  /// Yearly points count to their next time round.
  DateTime target(DateTime today) {
    if (!yearly) return date;
    final t = DateTime(today.year, today.month, today.day);
    // A yearly date that hasn't happened yet counts to the first time.
    return date.isAfter(t) ? date : CounterMilestone.nextYearly(date, today);
  }

  /// "6th anniversary" / "turns 31" for a yearly point; null otherwise.
  String? occasionLabel(DateTime today) {
    if (!yearly || !yearKnown) return null;
    final n = target(today).year - date.year;
    if (n <= 0) return null;
    if (birthday) return tt('turns {}').replaceFirst('{}', '$n');
    return OneSpacePhrases.arabic ? 'الذكرى رقم $n' : '${CountersRules.ordinal(n)} anniversary';
  }

  /// Progress of the wait from [start] (or the previous time round) to the target.
  double? progress(DateTime today) {
    final t = DateTime(today.year, today.month, today.day);
    final end = target(t);
    if (end.isBefore(t)) return null;
    final from = yearly ? DateTime(end.year - 1, end.month, end.day) : start;
    if (from == null || !from.isBefore(end)) return null;
    final total = end.difference(from).inDays;
    if (total <= 0) return null;
    return (t.difference(from).inDays / total).clamp(0.0, 1.0);
  }
}

class CountersRules {
  const CountersRules._();
  static List<CounterPoint> sortForList(List<CounterPoint> all, DateTime today) {
    final t = DateTime(today.year, today.month, today.day);
    final upcoming = all.where((p) => !p.target(t).isBefore(t)).toList()
      ..sort((a, b) => a.target(t).compareTo(b.target(t)));
    final past = all.where((p) => p.target(t).isBefore(t)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return [...upcoming, ...past];
  }

  static String ordinal(int n) {
    final mod100 = n % 100;
    final suffix = mod100 >= 11 && mod100 <= 13 ? 'th'
      : switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
    return '$n$suffix';
  }

  /// How far back a past point is, relative to the oldest one (0…1).
  static double ageShare(DateTime date, DateTime oldest, DateTime today) {
    final total = today.difference(oldest).inDays;
    if (total <= 0) return 0;
    return (today.difference(date).inDays / total).clamp(0.0, 1.0);
  }

  /// A saved counter → its point(s): yearly counters give the day itself and
  /// the next anniversary.
  static List<CounterPoint> fromRow(Map<String, dynamic> r) {
    final id = r['id'].toString();
    final date = DateTime.parse(r['on_date'].toString());
    final created = DateTime.tryParse((r['created_at'] ?? '').toString())?.toLocal();
    final base = (String pid, bool yearly) => CounterPoint(id: pid, title: (r['title'] ?? '').toString(),
      date: date, emoji: (r['emoji'] ?? '').toString(), row: r, yearly: yearly, pinned: r['pinned'] == true,
      start: created, original: yearly ? null : (r['yearly'] == true ? 'yearly:$id' : null));
    if (r['yearly'] != true) return [base(id, false)];
    final today = DateTime.now();
    final pastDay = !DateTime(date.year, date.month, date.day).isAfter(DateTime(today.year, today.month, today.day));
    return [if (pastDay) base(id, false), base('yearly:$id', true)];
  }
}

class CountersScreen extends StatefulWidget {
  const CountersScreen({super.key, this.initialId});
  final String? initialId;
  @override
  State<CountersScreen> createState() => _CountersScreenState();
}

class _CountersScreenState extends State<CountersScreen> {
  final db = Supabase.instance.client;
  String? space;
  SpacePeople? people;
  List<CounterPoint> points = [];
  bool loading = true, timeline = false;
  String filter = 'all';
  String? error;

  @override
  void initState() {
    super.initState();
    _load(openInitial: true);
  }

  Future<void> _load({bool openInitial = false}) async {
    try {
      final s = await CurrentSpaceCache.instance.get();
      if (s == null) { if (mounted) setState(() => loading = false); return; }
      final p = await SpacePeople.load();
      final rows = await db.from('space_counters').select().eq('space_id', s)
        .isFilter('archived_at', null).order('on_date');
      final out = <CounterPoint>[
        for (final r in rows) ...CountersRules.fromRow(Map<String, dynamic>.from(r)),
      ];
      if (!mounted) return;
      setState(() { space = s; people = p; points = out; loading = false; error = null; });
      if (openInitial && widget.initialId != null) {
        final hit = out.where((x) => x.id == widget.initialId || x.id == 'yearly:${widget.initialId}').firstOrNull;
        if (hit != null) _open(hit);
      }
    } catch (_) {
      if (mounted) setState(() { loading = false; error = 'Could not load counters.'; });
    }
  }

  Future<void> _edit([Map<String, dynamic>? row, DateTime? date]) async {
    final s = space;
    if (s == null) return;
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CounterEditor(spaceId: s, existing: row, initialDate: date,
        others: [for (final p in points) if (p.saved && !p.yearly && p.row?['id'] != row?['id']) p])));
    if (changed == true) await _load();
  }

  Future<void> _open(CounterPoint p) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CounterDetail(point: p, all: points, spaceId: space ?? '', onEdit: (r) => _edit(r))));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    final today = DateTime.now();
    final t = DateTime(today.year, today.month, today.day);
    final shown = CountersRules.sortForList(points.where((p) => switch (filter) {
      'future' => !p.target(t).isBefore(t),
      'past' => p.target(t).isBefore(t),
      _ => true,
    }).toList(), today);
    final pinned = shown.where((p) => p.pinned && !p.target(t).isBefore(t)).toList();
    final rest = shown.where((p) => !pinned.contains(p)).toList();
    final upcoming = rest.where((p) => !p.target(t).isBefore(t)).toList();
    final past = rest.where((p) => p.target(t).isBefore(t)).toList();
    final oldest = past.isEmpty ? t : past.map((p) => p.date).reduce((a, b) => a.isBefore(b) ? a : b);
    Widget todayLine() => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(children: [
      Icon(Icons.radio_button_checked, size: 16, color: theme.colorScheme.primary),
      const SizedBox(width: 6),
      Text('${tt('Today')} · ${loc.formatMediumDate(today)}',
        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
      const SizedBox(width: 8),
      Expanded(child: Divider(color: theme.colorScheme.primary, thickness: 2)),
    ]));
    return Scaffold(
      appBar: AppBar(title: Text(tt('Counters')), actions: [
        IconButton(tooltip: tt(timeline ? 'Show as cards' : 'Show as a timeline'),
          icon: Icon(timeline ? Icons.view_agenda_outlined : Icons.timeline),
          onPressed: () => setState(() => timeline = !timeline)),
      ]),
      floatingActionButton: space == null ? null
        : AddFab(label: tt('Add a counter'), onPressed: () => _edit()),
      body: loading ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(onRefresh: _load, child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            Wrap(spacing: 6, children: [
              for (final e in const {'all': 'All', 'future': 'Coming up', 'past': 'Looking back'}.entries)
                ChoiceChip(label: Text(tt(e.value)), selected: filter == e.key,
                  onSelected: (_) => setState(() => filter = e.key)),
            ]),
            if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(tt(error!))),
            if (shown.isEmpty) Padding(padding: const EdgeInsets.all(32), child: Column(children: [
              const Text('⏳', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 8),
              Text(tt('Count the days since your first date, until the wedding, or to anything you are looking forward to.'),
                textAlign: TextAlign.center),
            ]))
            else if (timeline) CounterTimeline(points: shown, onTap: _open)
            else ...[
              for (final p in pinned) CounterHeroCard(point: p, onTap: () => _open(p)),
              if (upcoming.isNotEmpty && filter != 'past') Padding(padding: const EdgeInsets.only(top: 8, bottom: 2),
                child: Text(tt('Coming up'), style: theme.textTheme.titleSmall)),
              for (final p in upcoming) CounterCard(point: p, onTap: () => _open(p)),
              // R78: the line between what is coming and what is behind us.
              if (filter == 'all' && (upcoming.isNotEmpty || pinned.isNotEmpty) && past.isNotEmpty) todayLine(),
              if (past.isNotEmpty && filter == 'past') Padding(padding: const EdgeInsets.only(top: 8, bottom: 2),
                child: Text(tt('Looking back'), style: theme.textTheme.titleSmall)),
              for (final p in past) CounterCard(point: p, onTap: () => _open(p),
                ageShare: CountersRules.ageShare(p.date, oldest, t)),
            ],
          ])),
    );
  }
}

Widget _emoji(CounterPoint p, {double size = 22}) => Text(
  p.emoji.isEmpty ? '📌' : p.emoji, style: TextStyle(fontSize: size));

/// The small line under a title: which date it is and where it comes from.
String _subtitle(BuildContext context, CounterPoint point) {
  final loc = MaterialLocalizations.of(context);
  final now = DateTime.now();
  final occasion = point.occasionLabel(now);
  if (point.yearly) {
    return [
      loc.formatMediumDate(point.target(now)),
      if (occasion != null) occasion,
      if (point.yearKnown) tt('first on {}').replaceFirst('{}', loc.formatMediumDate(point.date))
      else tt('every year'),
    ].join(' · ');
  }
  return [
    loc.formatMediumDate(point.date),
    if (point.original != null) tt('the day itself'),
    if (point.source != null) tt(point.source!),
  ].join(' · ');
}

class CounterCard extends StatelessWidget {
  const CounterCard({super.key, required this.point, required this.onTap, this.ageShare});
  final CounterPoint point;
  final VoidCallback onTap;
  /// Past points: how far back, relative to the oldest (drawn as a soft bar).
  final double? ageShare;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final span = SmartSpan.between(now, point.target(now));
    final (major, minor) = span.parts();
    final color = span.future || span.isToday ? theme.colorScheme.primary : theme.colorScheme.tertiary;
    final progress = point.progress(now);
    return Card(elevation: 0, clipBehavior: Clip.antiAlias, child: InkWell(onTap: onTap, child: Stack(children: [
      if (ageShare != null && ageShare! > 0) Positioned.fill(child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(widthFactor: ageShare, heightFactor: 1,
          child: ColoredBox(color: theme.colorScheme.tertiary.withValues(alpha: .13))))),
      Padding(padding: const EdgeInsets.all(14), child: Column(children: [
        Row(children: [
          CircleAvatar(radius: 22, backgroundColor: color.withValues(alpha: .12), child: _emoji(point)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(point.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(_subtitle(context, point), style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(major, style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
            if (minor.isNotEmpty) Text(minor, style: theme.textTheme.bodySmall?.copyWith(color: color)),
            if (span.caption.isNotEmpty) Text(span.caption, style: theme.textTheme.labelSmall),
          ]),
        ]),
        // R78: how much of the wait is already behind us.
        if (progress != null) Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(
            value: progress, minHeight: 7, color: color, backgroundColor: color.withValues(alpha: .15)))),
          const SizedBox(width: 8),
          Text('${(progress * 100).round()}%', style: theme.textTheme.labelSmall),
        ])),
      ])),
    ])));
  }
}

class CounterHeroCard extends StatelessWidget {
  const CounterHeroCard({super.key, required this.point, required this.onTap});
  final CounterPoint point;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final span = SmartSpan.between(now, point.target(now));
    final (major, minor) = span.parts();
    final progress = point.progress(now);
    return Card(elevation: 0, color: theme.colorScheme.primaryContainer,
      child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Row(children: [
            _emoji(point, size: 26), const SizedBox(width: 8),
            Expanded(child: Text(point.title, style: theme.textTheme.titleMedium)),
            Icon(Icons.push_pin, size: 18, color: theme.colorScheme.onPrimaryContainer),
          ]),
          Align(alignment: AlignmentDirectional.centerStart,
            child: Text(_subtitle(context, point), style: theme.textTheme.bodySmall)),
          const SizedBox(height: 12),
          Text(major, style: theme.textTheme.displaySmall?.copyWith(
            color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
          if (minor.isNotEmpty) Text(minor, style: theme.textTheme.titleMedium),
          if (span.caption.isNotEmpty) Text(span.caption, style: theme.textTheme.labelLarge),
          if (span.totalDays > 13) Text(SmartUnits.format(span.totalDays, 'day'), style: theme.textTheme.bodySmall),
          if (progress != null) Padding(padding: const EdgeInsets.only(top: 12), child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: progress, minHeight: 9))),
        ]))));
  }
}

/// A vertical line with today in the middle: what's coming above, what's
/// behind us below.
class CounterTimeline extends StatelessWidget {
  const CounterTimeline({super.key, required this.points, required this.onTap});
  final List<CounterPoint> points;
  final ValueChanged<CounterPoint> onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final t = DateTime(now.year, now.month, now.day);
    final future = points.where((p) => !p.target(t).isBefore(t)).toList()
      ..sort((a, b) => b.target(t).compareTo(a.target(t)));
    final past = points.where((p) => p.target(t).isBefore(t)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    Widget row(CounterPoint p) {
      final span = SmartSpan.between(now, p.target(now));
      return InkWell(onTap: () => onTap(p), child: IntrinsicHeight(child: Row(children: [
        SizedBox(width: 44, child: Stack(alignment: Alignment.center, children: [
          VerticalDivider(width: 2, thickness: 2, color: theme.colorScheme.outlineVariant),
          CircleAvatar(radius: 16, backgroundColor: theme.colorScheme.surface, child: _emoji(p, size: 16)),
        ])),
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.title, style: theme.textTheme.titleSmall),
            Text('${loc.formatMediumDate(p.target(now))} · ${span.sentence}', style: theme.textTheme.bodySmall),
          ]))),
      ])));
    }
    return Column(children: [
      for (final p in future) row(p),
      Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
        Expanded(child: Divider(color: theme.colorScheme.primary, thickness: 2)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('${tt('Today')} · ${loc.formatMediumDate(now)}',
            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary))),
        Expanded(child: Divider(color: theme.colorScheme.primary, thickness: 2)),
      ])),
      for (final p in past) row(p),
    ]);
  }
}

/// R78: two linked dates (and today) on one line, with the time between them.
class LinkedDatesLine extends StatelessWidget {
  const LinkedDatesLine({super.key, required this.a, required this.b, required this.aLabel, required this.bLabel});
  final DateTime a, b;
  final String aLabel, bLabel;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = a.isBefore(b) ? a : b, last = a.isBefore(b) ? b : a;
    final firstLabel = a.isBefore(b) ? aLabel : bLabel, lastLabel = a.isBefore(b) ? bLabel : aLabel;
    final from = [first, today].reduce((x, y) => x.isBefore(y) ? x : y);
    final to = [last, today].reduce((x, y) => x.isAfter(y) ? x : y);
    final total = to.difference(from).inDays.clamp(1, 1 << 30);
    double at(DateTime d) => d.difference(from).inDays / total;
    final between = SmartSpan.between(first, last);
    final primary = theme.colorScheme.primary;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth - 24;
      double x(DateTime d) => 12 + w * at(d);
      Widget dot(DateTime d, Color c, double r) => Positioned(left: x(d) - r, top: 40 - r,
        child: Container(width: r * 2, height: r * 2, decoration: BoxDecoration(color: c, shape: BoxShape.circle,
          border: Border.all(color: theme.colorScheme.surface, width: 2))));
      Widget label(DateTime d, String text, {bool below = false, TextAlign align = TextAlign.center}) {
        const width = 110.0;
        final left = (x(d) - width / 2).clamp(0.0, box.maxWidth - width);
        return Positioned(left: left, top: below ? 52 : 0, width: width, child: Text(text, textAlign: align,
          maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall));
      }
      return SizedBox(height: 92, child: Stack(clipBehavior: Clip.none, children: [
        Positioned(left: 12, right: 12, top: 38, child: Container(height: 4,
          decoration: BoxDecoration(color: theme.colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)))),
        Positioned(left: x(first), width: (x(last) - x(first)).clamp(2.0, double.infinity), top: 36,
          child: Container(height: 8, decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(4)))),
        dot(first, primary, 8),
        dot(last, primary, 8),
        if (!today.isAtSameMomentAs(first) && !today.isAtSameMomentAs(last))
          dot(today, theme.colorScheme.tertiary, 6),
        label(first, '$firstLabel\n${loc.formatShortDate(first)}'),
        label(last, '$lastLabel\n${loc.formatShortDate(last)}'),
        if (!today.isAtSameMomentAs(first) && !today.isAtSameMomentAs(last)) label(today, tt('Today'), below: true),
        Positioned(left: x(first), width: (x(last) - x(first)).clamp(60.0, double.infinity), top: 70,
          child: Text(between.label, textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(color: primary, fontWeight: FontWeight.w700))),
      ]));
    });
  }
}

class CounterDetail extends StatefulWidget {
  const CounterDetail({super.key, required this.point, required this.all, required this.spaceId, this.onEdit});
  final CounterPoint point;
  final List<CounterPoint> all;
  final String spaceId;
  final Future<void> Function(Map<String, dynamic> row)? onEdit;
  @override
  State<CounterDetail> createState() => _CounterDetailState();
}

class _CounterDetailState extends State<CounterDetail> {
  final db = Supabase.instance.client;
  late CounterPoint point = widget.point;
  CounterPoint? compareWith;
  String? placeName;

  @override
  void initState() {
    super.initState();
    final link = point.row?['linked_counter_id']?.toString();
    if (link != null) compareWith = widget.all.where((x) => x.id == link).firstOrNull;
    _loadPlace();
  }

  Future<void> _loadPlace() async {
    final id = point.row?['place_id']?.toString();
    if (id == null) return;
    try {
      final r = await db.from('places').select('name').eq('id', id).maybeSingle();
      if (mounted) setState(() => placeName = r?['name']?.toString());
    } catch (_) {}
  }

  Future<void> _reload() async {
    final id = point.row?['id'];
    if (id == null) return;
    final r = await db.from('space_counters').select().eq('id', id).maybeSingle();
    if (r == null) { if (mounted) Navigator.of(context).pop(); return; }
    if (mounted) {
      final fresh = CountersRules.fromRow(Map<String, dynamic>.from(r));
      setState(() => point = fresh.where((x) => x.yearly == point.yearly).firstOrNull ?? fresh.last);
    }
  }

  Future<void> _photos() async {
    final r = point.row;
    if (r == null) return;
    final memory = r['memory_id']?.toString();
    if (memory != null) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MemoryViewScreen(memoryId: memory, spaceId: widget.spaceId)));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MemoryEditorScreen(
      spaceId: widget.spaceId,
      prefill: {'title': point.title, 'memory_date': CalendarRules.sqlDate(point.date),
        'place': placeName ?? (r['place_text'] ?? '').toString()},
      onSaved: (id) async {
        try { await db.from('space_counters').update({'memory_id': id}).eq('id', r['id']); } catch (_) {}
      })));
    await _reload();
  }

  Future<void> _pickCompare() async {
    final others = widget.all.where((x) => x.id != point.id && !x.yearly).toList();
    final hit = await showModalBottomSheet<CounterPoint>(context: context, showDragHandle: true,
      builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true, children: [
        ListTile(title: Text(tt('Measure the time between this and…'), style: const TextStyle(fontWeight: FontWeight.w700))),
        for (final o in others) ListTile(leading: _emoji(o), title: Text(o.title),
          subtitle: Text(MaterialLocalizations.of(ctx).formatMediumDate(o.date)),
          onTap: () => Navigator.pop(ctx, o)),
      ])));
    if (hit != null) setState(() => compareWith = hit);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final target = point.target(now);
    final span = SmartSpan.between(now, target);
    final (major, minor) = span.parts();
    final milestone = CounterMilestone.next(point.date, now);
    final r = point.row;
    final people = r == null ? const <String>[] : List<String>.from(r['people'] as List? ?? const []);
    final at = (r?['at_time'] ?? '').toString();
    Widget fact(IconData icon, String text) => ListTile(dense: true, leading: Icon(icon), title: Text(text));
    return Scaffold(
      appBar: AppBar(title: Text(tt('Counter')), actions: [
        if (r != null) ItemMenu(kind: 'counter', recordId: r['id'].toString(), title: point.title,
          table: 'space_counters', onChanged: () { if (mounted) Navigator.of(context).pop(); },
          onOpen: widget.onEdit == null ? null : () async { await widget.onEdit!(r); await _reload(); },
          moreActions: [
            ItemMenuAction(r['pinned'] == true ? 'Unpin' : 'Pin to the top', Icons.push_pin_outlined, () async {
              await db.from('space_counters').update({'pinned': r['pinned'] != true}).eq('id', r['id']);
              await _reload();
            }),
          ]),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(child: _emoji(point, size: 48)),
        const SizedBox(height: 8),
        Text(point.title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
        Text([
          loc.formatFullDate(point.yearly ? target : point.date),
          if (point.occasionLabel(now) != null) point.occasionLabel(now)!,
          if (at.length >= 5) at.substring(0, 5),
        ].join(' · '), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        // R78: the day itself and its anniversary, side by side and clearly named.
        if (point.yearly && point.yearKnown || point.original != null) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(children: [
            Expanded(child: _dayCard(theme, loc, tt('The day itself'), point.date,
              SmartSpan.between(now, point.date), highlighted: !point.yearly)),
            const SizedBox(width: 8),
            Expanded(child: _dayCard(theme, loc,
              point.occasionLabel(now) ?? tt('Next anniversary'),
              CounterPoint(id: '', title: '', date: point.date, yearly: true).target(now),
              SmartSpan.between(now, CounterPoint(id: '', title: '', date: point.date, yearly: true).target(now)),
              highlighted: point.yearly)),
          ])),
        const SizedBox(height: 16),
        Card(elevation: 0, color: theme.colorScheme.primaryContainer, child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            if (point.yearly) Text(tt('Next time: {}').replaceFirst('{}', loc.formatMediumDate(target)),
              style: theme.textTheme.labelLarge),
            Text(major, style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
            if (minor.isNotEmpty) Text(minor, style: theme.textTheme.titleMedium),
            if (span.caption.isNotEmpty) Text(span.caption),
            const Divider(height: 24),
            Wrap(alignment: WrapAlignment.center, spacing: 16, runSpacing: 4, children: [
              if (span.years > 0) Text(SmartUnits.format(span.years * 12 + span.months, 'month')),
              if (span.totalDays >= 7) Text(SmartUnits.format(span.weeks, 'week')),
              Text(SmartUnits.format(span.totalDays, 'day')),
              if (span.totalDays < 60) Text(SmartUnits.format(span.totalDays * 24, 'hour')),
            ]),
          ]))),
        if (point.progress(now) != null) Padding(padding: const EdgeInsets.only(top: 10), child: Column(children: [
          ClipRRect(borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: point.progress(now), minHeight: 10)),
          const SizedBox(height: 4),
          Text(tt('{}% of the wait is behind us').replaceFirst('{}', '${(point.progress(now)! * 100).round()}'),
            style: theme.textTheme.bodySmall),
        ])),
        if (milestone != null) Card(elevation: 0, child: ListTile(
          leading: const Text('🎉', style: TextStyle(fontSize: 24)),
          title: Text(tt('Next milestone: {}').replaceFirst('{}', milestone.label)),
          subtitle: Text('${loc.formatMediumDate(milestone.on)} · '
            '${SmartSpan.between(now, milestone.on).sentence}'))),
        if ((r?['description'] ?? '').toString().trim().isNotEmpty) Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(r!['description'].toString(), style: theme.textTheme.bodyLarge)),
        if (placeName != null || (r?['place_text'] ?? '').toString().isNotEmpty)
          fact(Icons.place_outlined, placeName ?? r!['place_text'].toString()),
        if (people.isNotEmpty) fact(Icons.people_outline, people.join(', ')),
        if (r?['category'] != null) fact(Icons.label_outline, tt(CounterCategories.labels[r!['category']] ?? 'Other')),
        if (point.source != null) fact(Icons.info_outline,
          tt('From {}. Change it there.').replaceFirst('{}', tt(point.source!))),
        const SizedBox(height: 8),
        if (r != null) OutlinedButton.icon(onPressed: _photos,
          icon: Icon(r['memory_id'] == null ? Icons.add_a_photo_outlined : Icons.photo_library_outlined),
          label: Text(tt(r['memory_id'] == null ? 'Add photos and the story' : 'Open the photos and story'))),
        const SizedBox(height: 8),
        Card(elevation: 0, child: Column(children: [
          ListTile(leading: const Icon(Icons.straighten), title: Text(tt('Time between two points')),
            subtitle: Text(compareWith == null ? tt('Pick another counter to compare')
              : '${compareWith!.title} ↔ ${point.title}'),
            trailing: TextButton(onPressed: _pickCompare, child: Text(tt(compareWith == null ? 'Pick' : 'Change')))),
          if (compareWith != null) Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: LinkedDatesLine(a: compareWith!.date, b: point.date, aLabel: compareWith!.title, bLabel: point.title)),
          if (compareWith != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text(
            () {
              final between = SmartSpan.between(compareWith!.date, point.date);
              return between.isToday ? tt('The same day')
                : tt(between.future ? '{} after {}' : '{} before {}')
                    .replaceFirst('{}', between.label).replaceFirst('{}', compareWith!.title);
            }(),
            style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary))),
        ])),
      ]),
    );
  }
}

Widget _dayCard(ThemeData theme, MaterialLocalizations loc, String title, DateTime date, SmartSpan span,
    {bool highlighted = false}) => Card(
  elevation: 0,
  color: highlighted ? theme.colorScheme.secondaryContainer : theme.colorScheme.surfaceContainerHighest,
  child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: theme.textTheme.labelLarge),
    Text(loc.formatMediumDate(date), style: theme.textTheme.bodySmall),
    const SizedBox(height: 4),
    Text(span.isToday ? tt('Today') : span.sentence,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
  ])));

class CounterEditor extends StatefulWidget {
  const CounterEditor({super.key, required this.spaceId, this.existing, this.initialDate, this.source, this.others = const []});
  final String spaceId;
  final Map<String, dynamic>? existing;
  final DateTime? initialDate;
  final CounterSource? source;
  final List<CounterPoint> others;
  @override
  State<CounterEditor> createState() => _CounterEditorState();
}

class _CounterEditorState extends State<CounterEditor> with FormChangeTracker<CounterEditor> {
  final db = Supabase.instance.client;
  late final TextEditingController title, description, placeText, personName;
  late String emoji, category;
  DateTime? date;
  TimeOfDay? time;
  String? placeId, linkedId;
  late bool yearly, pinned, shared;
  late List<String> people;
  List<Map<String, dynamic>> places = [];
  SpacePeople? who;
  bool saving = false;
  String? error;

  @override
  String get signature => [title.text, description.text, placeText.text, emoji, category, date, time,
    placeId, linkedId, yearly, pinned, shared, people.join(',')].join('|');

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? widget.source?.prefill ?? const <String, dynamic>{};
    title = TextEditingController(text: (e['title'] ?? '').toString());
    description = TextEditingController(text: (e['description'] ?? '').toString());
    placeText = TextEditingController(text: (e['place_text'] ?? '').toString());
    personName = TextEditingController();
    emoji = (e['emoji'] ?? '').toString();
    category = (e['category'] ?? 'love').toString();
    date = DateTime.tryParse((e['on_date'] ?? '').toString()) ?? widget.initialDate;
    final t = (e['at_time'] ?? '').toString();
    if (t.length >= 5) time = TimeOfDay(hour: int.parse(t.substring(0, 2)), minute: int.parse(t.substring(3, 5)));
    placeId = e['place_id']?.toString();
    linkedId = e['linked_counter_id']?.toString();
    yearly = e['yearly'] == true;
    pinned = e['pinned'] == true;
    shared = (e['visibility'] ?? 'shared') == 'shared';
    people = List<String>.from(e['people'] as List? ?? const []);
    SpacePeople.load().then((p) { if (mounted) setState(() => who = p); });
    db.from('places').select('id,name').eq('space_id', widget.spaceId).isFilter('archived_at', null).order('name')
      .then((rows) { if (mounted) setState(() => places = List<Map<String, dynamic>>.from(rows)); },
        onError: (_) {});
  }

  @override
  void dispose() {
    title.dispose(); description.dispose(); placeText.dispose(); personName.dispose();
    super.dispose();
  }

  Future<void> _chooseSource() async {
    final source = await pickCounterSource(context, widget.spaceId);
    if (!mounted || source == null) return;
    final e = source.prefill;
    setState(() {
      title.text = e['title'].toString();
      date = source.date;
      time = null;
      emoji = source.emoji;
      category = source.category;
      yearly = source.yearly;
      shared = source.shared;
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: date ?? DateTime.now(),
      firstDate: DateTime(1900), lastDate: DateTime(2100));
    if (d != null) setState(() => date = d);
  }

  Future<void> _save() async {
    if (saving || date == null || title.text.trim().isEmpty) return;
    setState(() { saving = true; error = null; });
    final values = <String, dynamic>{
      'title': title.text.trim(), 'description': description.text.trim(),
      'emoji': emoji, 'category': category, 'on_date': CalendarRules.sqlDate(date!),
      'at_time': time == null ? null
        : '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}',
      'place_id': placeId, 'place_text': placeId == null ? placeText.text.trim() : '',
      'people': people, 'linked_counter_id': linkedId, 'yearly': yearly, 'pinned': pinned,
      'visibility': shared ? 'shared' : 'private',
    };
    try {
      if (widget.existing == null) {
        await db.from('space_counters').insert({...values, 'space_id': widget.spaceId});
      } else {
        await db.from('space_counters').update(values).eq('id', widget.existing!['id']);
      }
      markClean();
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not save. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final me = who?.me;
    final partnerName = who?.partnerName;
    final span = date == null ? null : SmartSpan.between(DateTime.now(), date!);
    return EditorScaffold(
      title: widget.existing == null ? 'New counter' : 'Edit counter',
      isNew: widget.existing == null, saving: saving, listenTo: [title, description, placeText],
      isChanged: () => changed, isComplete: () => title.text.trim().isNotEmpty && date != null,
      onSave: _save,
      meta: MetaStrip(value: MetaValues(shared: shared), people: who, showBelongs: false, showDate: false,
        onChanged: (v) => setState(() => shared = v.shared)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.existing == null) Padding(padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton.icon(onPressed: _chooseSource,
            icon: const Icon(Icons.library_add_outlined),
            label: Text(tt('Choose from calendar, dates, occasions, flights or trips')))),
        TextField(controller: title, maxLength: 120, textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tt(requiredLabel('What happened or is coming')),
            hintText: tt('Our first date, the wedding, moving in…'), border: const OutlineInputBorder())),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.event_outlined),
            label: Text(date == null ? tt(requiredLabel('Date')) : loc.formatMediumDate(date!)))),
          const SizedBox(width: 8),
          OutlinedButton.icon(icon: const Icon(Icons.schedule),
            label: Text(time == null ? tt('Time') : time!.format(context)),
            onPressed: () async {
              final t = await showTimePicker(context: context, initialTime: time ?? const TimeOfDay(hour: 19, minute: 0));
              if (t != null) setState(() => time = t);
            }),
          if (time != null) IconButton(icon: const Icon(Icons.close), tooltip: tt('Clear'),
            onPressed: () => setState(() => time = null)),
        ]),
        if (span != null) Padding(padding: const EdgeInsets.only(top: 6),
          child: Text(span.isToday ? tt('Today') : span.sentence,
            style: TextStyle(color: Theme.of(context).colorScheme.primary))),
        const SizedBox(height: 12),
        FormSection(tt('Look')),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final e in CounterCategories.suggestions) ChoiceChip(
            label: Text(e, style: const TextStyle(fontSize: 18)), selected: emoji == e,
            onSelected: (_) => setState(() => emoji = emoji == e ? '' : e)),
        ]),
        const SizedBox(height: 8),
        ChoiceRow<String>(label: 'Kind', selected: category,
          options: CounterCategories.labels, onSelected: (v) => setState(() {
            if (v == null) return;
            category = v;
            if (emoji.isEmpty) emoji = CounterCategories.emoji[v] ?? '';
          })),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: yearly, onChanged: (v) => setState(() => yearly = v),
          title: Text(tt('Every year')), subtitle: Text(tt('Count down to the next time it comes round'))),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: pinned, onChanged: (v) => setState(() => pinned = v),
          title: Text(tt('Pin to the top')), subtitle: Text(tt('Shown big at the top of Counters'))),
        FormSection(tt('The story')),
        TextField(controller: description, minLines: 2, maxLines: 6, maxLength: 4000,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tt('Description'), border: const OutlineInputBorder())),
        if (places.isNotEmpty) DropdownButtonFormField<String?>(
          initialValue: places.any((p) => p['id'] == placeId) ? placeId : null,
          decoration: InputDecoration(labelText: tt('One of our places'), border: const OutlineInputBorder()),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(tt('None'))),
            for (final p in places) DropdownMenuItem<String?>(value: p['id'].toString(), child: Text(p['name'].toString())),
          ],
          onChanged: (v) => setState(() => placeId = v)),
        if (placeId == null) Padding(padding: const EdgeInsets.only(top: 12), child: TextField(controller: placeText,
          maxLength: 200, decoration: InputDecoration(labelText: tt('Place'), prefixIcon: const Icon(Icons.place_outlined),
            border: const OutlineInputBorder()))),
        Text(tt('Who was there'), style: Theme.of(context).textTheme.labelLarge),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final name in {if (me != null) tt('Me'), if (partnerName != null) partnerName, ...people})
            FilterChip(label: Text(name), selected: people.contains(name),
              onSelected: (on) => setState(() => on ? people.add(name) : people.remove(name))),
        ]),
        TextField(controller: personName, decoration: InputDecoration(hintText: tt('Add someone else'),
          suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: () {
            final n = personName.text.trim();
            if (n.isNotEmpty && !people.contains(n) && people.length < 20) setState(() { people.add(n); personName.clear(); });
          })),
          onSubmitted: (n) {
            if (n.trim().isNotEmpty && !people.contains(n.trim())) setState(() { people.add(n.trim()); personName.clear(); });
          }),
        if (widget.others.isNotEmpty) ...[
          const SizedBox(height: 12),
          FormSection(tt('Link to another counter')),
          DropdownButtonFormField<String?>(
            initialValue: widget.others.any((o) => o.id == linkedId) ? linkedId : null,
            decoration: InputDecoration(labelText: tt('Show the time between this and…'), border: const OutlineInputBorder()),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(tt('None'))),
              for (final o in widget.others) DropdownMenuItem<String?>(value: o.id, child: Text('${o.emoji} ${o.title}')),
            ],
            onChanged: (v) => setState(() => linkedId = v)),
        ],
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text(tt(error!), style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 24),
      ]),
    );
  }
}
