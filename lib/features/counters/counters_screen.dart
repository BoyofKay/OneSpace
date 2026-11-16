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
import '../settings/special_dates.dart';
import 'smart_duration.dart';

/// R77 (Ahmed's friend's idea): our counters — moments in the past ("since")
/// and the future ("to go"), counted in the units that matter, with photos,
/// place, who was there and links between two points. Anniversary, birthdays,
/// the next trip and "last met / next meet" appear on their own.
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
class CounterPoint {
  CounterPoint({required this.id, required this.title, required this.date, this.emoji = '',
    this.row, this.source, this.yearly = false, this.pinned = false});
  final String id, title, emoji;
  final DateTime date;
  final Map<String, dynamic>? row;
  /// "Anniversary", "Birthday", "Trip"… for points that come from elsewhere.
  final String? source;
  final bool yearly, pinned;
  bool get saved => row != null;

  /// Yearly points count to their next time round.
  DateTime target(DateTime today) => yearly ? CounterMilestone.nextYearly(date, today) : date;
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
        for (final r in rows)
          CounterPoint(id: r['id'].toString(), title: (r['title'] ?? '').toString(),
            date: DateTime.parse(r['on_date'].toString()), emoji: (r['emoji'] ?? '').toString(),
            row: Map<String, dynamic>.from(r), yearly: r['yearly'] == true, pinned: r['pinned'] == true),
      ];
      out.addAll(await _fromElsewhere(s, p));
      if (!mounted) return;
      setState(() { space = s; people = p; points = out; loading = false; error = null; });
      if (openInitial && widget.initialId != null) {
        final hit = out.where((x) => x.id == widget.initialId).firstOrNull;
        if (hit != null) _open(hit);
      }
    } catch (_) {
      if (mounted) setState(() { loading = false; error = 'Could not load counters.'; });
    }
  }

  /// Anniversary, birthdays, last met / next meet and the next trip.
  Future<List<CounterPoint>> _fromElsewhere(String s, SpacePeople? p) async {
    final out = <CounterPoint>[];
    try {
      for (final d in await loadSpecialDates(s)) {
        if (d.kind == 'anniversary' && d.year != null) {
          out.add(CounterPoint(id: 'special:${d.id}', title: tt('Together'), emoji: '💞',
            date: DateTime(d.year!, d.month, d.day), source: 'Anniversary'));
          out.add(CounterPoint(id: 'special-next:${d.id}', title: tt('Our anniversary'), emoji: '💍',
            date: DateTime(d.year!, d.month, d.day), source: 'Anniversary', yearly: true));
        } else {
          final name = SpecialDateRules.label(d, (id) => id == p?.me ? '' : (p?.partnerName ?? ''));
          out.add(CounterPoint(id: 'special:${d.id}', title: tt(name), emoji: d.kind == 'birthday' ? '🎂' : '⭐',
            date: DateTime(d.year ?? DateTime.now().year, d.month, d.day), source: 'Special date', yearly: true));
        }
      }
      final sp = await db.from('spaces').select('relationship_mode,last_met_on,next_meet_on').eq('id', s).maybeSingle();
      if (sp != null && sp['relationship_mode'] == 'apart') {
        final last = DateTime.tryParse((sp['last_met_on'] ?? '').toString());
        final next = DateTime.tryParse((sp['next_meet_on'] ?? '').toString());
        if (last != null) out.add(CounterPoint(id: 'last-met', title: tt('Since we last met'), emoji: '🫂', date: last, source: 'How we live'));
        if (next != null) out.add(CounterPoint(id: 'next-meet', title: tt('Until we meet again'), emoji: '🤍', date: next, source: 'How we live'));
      }
      final today = CalendarRules.sqlDate(DateTime.now());
      final trip = await db.from('shared_trips').select('id,title,start_on').eq('space_id', s)
        .isFilter('archived_at', null).gte('start_on', today).order('start_on').limit(1).maybeSingle();
      if (trip != null) {
        out.add(CounterPoint(id: 'trip:${trip['id']}', title: (trip['title'] ?? '').toString(), emoji: '✈️',
          date: DateTime.parse(trip['start_on'].toString()), source: 'Next trip'));
      }
    } catch (_) {}
    return out;
  }

  Future<void> _edit([Map<String, dynamic>? row, DateTime? date]) async {
    final s = space;
    if (s == null) return;
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CounterEditor(spaceId: s, existing: row, initialDate: date,
        others: [for (final p in points) if (p.saved && p.id != row?['id']) p])));
    if (changed == true) await _load();
  }

  Future<void> _open(CounterPoint p) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CounterDetail(point: p, all: points, spaceId: space ?? '', onEdit: (r) => _edit(r))));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final t = DateTime(today.year, today.month, today.day);
    final shown = CountersRules.sortForList(points.where((p) => switch (filter) {
      'future' => !p.target(t).isBefore(t),
      'past' => p.target(t).isBefore(t),
      _ => true,
    }).toList(), today);
    final pinned = shown.where((p) => p.pinned).toList();
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
              for (final p in shown.where((p) => !p.pinned)) CounterCard(point: p, onTap: () => _open(p)),
            ],
          ])),
    );
  }
}

Widget _emoji(CounterPoint p, {double size = 22}) => Text(
  p.emoji.isEmpty ? '📌' : p.emoji, style: TextStyle(fontSize: size));

class CounterCard extends StatelessWidget {
  const CounterCard({super.key, required this.point, required this.onTap});
  final CounterPoint point;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    final span = SmartSpan.between(DateTime.now(), point.target(DateTime.now()));
    final (major, minor) = span.parts();
    final color = span.future || span.isToday ? theme.colorScheme.primary : theme.colorScheme.tertiary;
    return Card(elevation: 0, child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
        CircleAvatar(radius: 22, backgroundColor: color.withValues(alpha: .12), child: _emoji(point)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(point.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text([
            loc.formatMediumDate(point.yearly ? point.target(DateTime.now()) : point.date),
            if (point.yearly) tt('every year'),
            if (point.source != null) tt(point.source!),
          ].join(' · '), style: theme.textTheme.bodySmall),
        ])),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(major, style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
          if (minor.isNotEmpty) Text(minor, style: theme.textTheme.bodySmall?.copyWith(color: color)),
          if (span.caption.isNotEmpty) Text(span.caption, style: theme.textTheme.labelSmall),
        ]),
      ]))));
  }
}

class CounterHeroCard extends StatelessWidget {
  const CounterHeroCard({super.key, required this.point, required this.onTap});
  final CounterPoint point;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final span = SmartSpan.between(DateTime.now(), point.target(DateTime.now()));
    final (major, minor) = span.parts();
    return Card(elevation: 0, color: theme.colorScheme.primaryContainer,
      child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Row(children: [
            _emoji(point, size: 26), const SizedBox(width: 8),
            Expanded(child: Text(point.title, style: theme.textTheme.titleMedium)),
            Icon(Icons.push_pin, size: 18, color: theme.colorScheme.onPrimaryContainer),
          ]),
          const SizedBox(height: 12),
          Text(major, style: theme.textTheme.displaySmall?.copyWith(
            color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
          if (minor.isNotEmpty) Text(minor, style: theme.textTheme.titleMedium),
          if (span.caption.isNotEmpty) Text(span.caption, style: theme.textTheme.labelLarge),
          if (span.totalDays > 13) Text(SmartUnits.format(span.totalDays, 'day'), style: theme.textTheme.bodySmall),
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
      setState(() => point = CounterPoint(id: r['id'].toString(), title: r['title'].toString(),
        date: DateTime.parse(r['on_date'].toString()), emoji: (r['emoji'] ?? '').toString(),
        row: Map<String, dynamic>.from(r), yearly: r['yearly'] == true, pinned: r['pinned'] == true));
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
    final others = widget.all.where((x) => x.id != point.id).toList();
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
    final since = point.yearly ? SmartSpan.between(now, point.date) : null;
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
        Text([loc.formatFullDate(point.date), if (at.length >= 5) at.substring(0, 5)].join(' · '),
          textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
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
        if (since != null && !since.future && since.totalDays > 0) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(tt('Since the first one: {}').replaceFirst('{}', since.label), textAlign: TextAlign.center)),
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

class CounterEditor extends StatefulWidget {
  const CounterEditor({super.key, required this.spaceId, this.existing, this.initialDate, this.others = const []});
  final String spaceId;
  final Map<String, dynamic>? existing;
  final DateTime? initialDate;
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
    final e = widget.existing ?? const <String, dynamic>{};
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
