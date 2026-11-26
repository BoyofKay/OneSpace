import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:onespace/l10n/phrases.dart';
import 'counter_chains.dart';
import 'counter_timelines.dart';
import 'smart_duration.dart';

/// 26 Nov 2026 (D100): named timelines. A counter can be on several timelines.
/// [counters] are the saved counter rows the person can see.

String _emoji(Map<String, dynamic> r) {
  final e = (r['emoji'] ?? '').toString();
  return e.isEmpty ? '📌' : e;
}
DateTime _date(Map<String, dynamic> r) => DateTime.parse(r['on_date'].toString());
String _id(Map<String, dynamic> r) => r['id'].toString();

/// Asks for a timeline name (new or rename). Returns null when cancelled.
Future<String?> askTimelineName(BuildContext context, {String initial = '', bool rename = false}) async {
  final c = TextEditingController(text: initial);
  String? error;
  return showDialog<String>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
    scrollable: true,
    title: Text(tt(rename ? 'Rename timeline' : 'New timeline')),
    content: TextField(controller: c, autofocus: true, maxLength: 80,
      decoration: InputDecoration(labelText: tt('Name'), hintText: tt('For example: Our story, Travels'),
        errorText: error == null ? null : tt(error!))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tt('Cancel'))),
      FilledButton(onPressed: () {
        final problem = NamedTimeline.validateTitle(c.text);
        if (problem != null) { set(() => error = problem); return; }
        Navigator.pop(ctx, c.text.trim());
      }, child: Text(tt(rename ? 'Save' : 'Create'))),
    ])));
}

/// From a counter: add it to an existing timeline of the same kind, or to a new one.
/// Returns true when something changed.
Future<bool> addCounterToTimeline(BuildContext context, Map<String, dynamic> counter, List<NamedTimeline> timelines) async {
  final store = CounterTimelinesStore(Supabase.instance.client);
  final candidates = [for (final t in timelines) if (t.fits(counter) && !t.counterIds.contains(_id(counter))) t];
  final choice = await showModalBottomSheet<Object>(context: context, showDragHandle: true, isScrollControlled: true,
    builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true, children: [
      ListTile(title: Text(tt('Add to a timeline'), style: const TextStyle(fontWeight: FontWeight.w700))),
      for (final t in candidates) ListTile(leading: const Icon(Icons.timeline), title: Text(t.title),
        subtitle: Text(tt('{} counters').replaceFirst('{}', '${t.counterIds.length}')), onTap: () => Navigator.pop(ctx, t)),
      ListTile(leading: const Icon(Icons.add), title: Text(tt('New timeline…')), onTap: () => Navigator.pop(ctx, 'new')),
    ])));
  if (choice == null || !context.mounted) return false;
  try {
    var target = choice is NamedTimeline ? choice : null;
    if (choice == 'new') {
      final name = await askTimelineName(context);
      if (name == null) return false;
      target = await store.create(name, spaceId: counter['space_id']?.toString(),
        privateSpaceId: counter['private_space_id']?.toString());
    }
    await store.add(target!.id, _id(counter));
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tt('Could not save. Check your connection and try again.'))));
    }
    return false;
  }
}

/// All timelines, with "New timeline".
class TimelinesListScreen extends StatefulWidget {
  const TimelinesListScreen({super.key, required this.counters, this.sharedSpaceId, this.privateSpaceId});
  final List<Map<String, dynamic>> counters;
  /// Where a new timeline can live: the couple's space and/or the person's own space.
  final String? sharedSpaceId, privateSpaceId;
  @override
  State<TimelinesListScreen> createState() => _TimelinesListScreenState();
}

class _TimelinesListScreenState extends State<TimelinesListScreen> {
  final store = CounterTimelinesStore(Supabase.instance.client);
  List<NamedTimeline>? timelines;
  String? error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final t = await store.load();
      if (mounted) setState(() { timelines = t; error = null; });
    } catch (_) {
      if (mounted) setState(() => error = 'Timelines could not be loaded. Check your connection and try again.');
    }
  }

  Future<void> _new() async {
    final name = await askTimelineName(context);
    if (name == null || !mounted) return;
    var shared = widget.sharedSpaceId != null && widget.privateSpaceId == null;
    if (widget.sharedSpaceId != null && widget.privateSpaceId != null) {
      final pick = await showModalBottomSheet<bool>(context: context, showDragHandle: true, builder: (ctx) => SafeArea(
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.people_outline), title: Text(tt('Shared')),
            subtitle: Text(tt('Both of you see it; it holds shared counters.')), onTap: () => Navigator.pop(ctx, true)),
          ListTile(leading: const Icon(Icons.lock_outline), title: Text(tt('Only me')),
            subtitle: Text(tt('Only you see it; it holds your private counters.')), onTap: () => Navigator.pop(ctx, false)),
        ]))));
      if (pick == null) return;
      shared = pick;
    }
    try {
      final t = await store.create(name, spaceId: shared ? widget.sharedSpaceId : null,
        privateSpaceId: shared ? null : widget.privateSpaceId);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => TimelineScreen(timeline: t, counters: widget.counters)));
      await _load();
    } catch (_) {
      if (mounted) setState(() => error = 'Could not save. Check your connection and try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final c in widget.counters) _id(c): c};
    final list = timelines;
    return Scaffold(
      appBar: AppBar(title: Text(tt('Timelines'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: _new,
        icon: const Icon(Icons.add), label: Text(tt('New timeline'))),
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
        if (error != null) Text(tt(error!), style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (list == null && error == null) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (list != null && list.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(tt('No timelines yet. Create one and add counters to see the time between them.'))),
        for (final t in list ?? const <NamedTimeline>[]) () {
          final rows = [for (final id in t.counterIds) if (byId[id] != null) byId[id]!]..sort((a, b) => _date(a).compareTo(_date(b)));
          return Card(elevation: 0, child: ListTile(
            leading: Icon(t.shared ? Icons.people_outline : Icons.lock_outline),
            title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(rows.length < 2
                ? tt('{} counters').replaceFirst('{}', '${rows.length}')
                : '${tt('{} counters').replaceFirst('{}', '${rows.length}')} · ${SmartSpan.between(_date(rows.first), _date(rows.last)).label}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => TimelineScreen(timeline: t, counters: widget.counters)));
              await _load();
            }));
        }(),
      ])),
    );
  }
}

/// One named timeline: its counters oldest first, the time between neighbours,
/// and "Today" only when it falls between the first and the last point.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key, required this.timeline, required this.counters});
  final NamedTimeline timeline;
  final List<Map<String, dynamic>> counters;
  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  final store = CounterTimelinesStore(Supabase.instance.client);
  late String title = widget.timeline.title;
  late List<String> members = [...widget.timeline.counterIds];
  bool busy = false;
  String? error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() { busy = true; error = null; });
    try { await action(); }
    catch (_) { if (mounted) setState(() => error = 'Could not save. Check your connection and try again.'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> _rename() async {
    final name = await askTimelineName(context, initial: title, rename: true);
    if (name == null) return;
    await _run(() async { await store.rename(widget.timeline.id, name); setState(() => title = name); });
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(scrollable: true,
      title: Text(tt('Delete this timeline?')),
      content: Text(tt('The counters stay; only this timeline and its name are deleted.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tt('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tt('Delete'))),
      ]));
    if (ok != true) return;
    await _run(() async { await store.delete(widget.timeline.id); if (mounted) Navigator.of(context).pop(); });
  }

  Future<void> _add() async {
    final options = [for (final c in widget.counters) if (widget.timeline.fits(c) && !members.contains(_id(c))) c];
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tt('All your counters are already on this timeline.'))));
      return;
    }
    final hit = await showModalBottomSheet<Map<String, dynamic>>(context: context, showDragHandle: true, isScrollControlled: true,
      builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true, children: [
        ListTile(title: Text(tt('Add a counter to this timeline'), style: const TextStyle(fontWeight: FontWeight.w700))),
        for (final c in options) ListTile(leading: Text(_emoji(c), style: const TextStyle(fontSize: 22)),
          title: Text((c['title'] ?? '').toString()),
          subtitle: Text(MaterialLocalizations.of(ctx).formatMediumDate(_date(c))), onTap: () => Navigator.pop(ctx, c)),
      ])));
    if (hit == null) return;
    await _run(() async { await store.add(widget.timeline.id, _id(hit)); setState(() => members.add(_id(hit))); });
  }

  Future<void> _remove(Map<String, dynamic> c) async {
    await _run(() async { await store.remove(widget.timeline.id, _id(c)); setState(() => members.remove(_id(c))); });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    final byId = {for (final c in widget.counters) _id(c): c};
    final line = [for (final id in members) if (byId[id] != null) byId[id]!]..sort((a, b) => _date(a).compareTo(_date(b)));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final showToday = CounterChains.showToday([for (final c in line) _date(c)], today);
    final primary = theme.colorScheme.primary;

    Widget point(Map<String, dynamic> c) => Card(elevation: 0, child: ListTile(
      leading: Text(_emoji(c), style: const TextStyle(fontSize: 26)),
      title: Text((c['title'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${loc.formatMediumDate(_date(c))} · ${SmartSpan.between(now, _date(c)).sentence}'),
      trailing: IconButton(tooltip: tt('Remove from this timeline'), icon: const Icon(Icons.link_off),
        onPressed: busy ? null : () => _remove(c))));
    Widget gap(DateTime a, DateTime b) {
      final s = SmartSpan.between(a, b);
      return Padding(padding: const EdgeInsetsDirectional.only(start: 28, top: 2, bottom: 2), child: Row(children: [
        Container(width: 3, height: 34, color: primary.withValues(alpha: .5)),
        const SizedBox(width: 12),
        Expanded(child: Text(s.isToday ? tt('The same day') : s.label,
          style: theme.textTheme.titleSmall?.copyWith(color: primary, fontWeight: FontWeight.w700))),
      ]));
    }
    Widget todayRow() => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      Expanded(child: Divider(color: theme.colorScheme.tertiary, thickness: 2)),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('${tt('Today')} · ${loc.formatMediumDate(today)}',
        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.tertiary))),
      Expanded(child: Divider(color: theme.colorScheme.tertiary, thickness: 2)),
    ]));

    final children = <Widget>[];
    for (var i = 0; i < line.length; i++) {
      if (i > 0) {
        final prev = _date(line[i - 1]), cur = _date(line[i]);
        if (showToday && today.isAfter(prev) && today.isBefore(cur)) {
          children..add(gap(prev, today))..add(todayRow())..add(gap(today, cur));
        } else {
          children.add(gap(prev, cur));
        }
      }
      children.add(point(line[i]));
    }

    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [
        IconButton(tooltip: tt('Rename timeline'), icon: const Icon(Icons.edit_outlined), onPressed: busy ? null : _rename),
        IconButton(tooltip: tt('Delete this timeline?'), icon: const Icon(Icons.delete_outline), onPressed: busy ? null : _delete),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: busy ? null : _add,
        icon: const Icon(Icons.add_link), label: Text(tt('Connect a counter'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
        if (line.length > 1) Card(elevation: 0, color: theme.colorScheme.primaryContainer, child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tt('{} counters').replaceFirst('{}', '${line.length}'), style: theme.textTheme.labelLarge),
            Text(SmartSpan.between(_date(line.first), _date(line.last)).label,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text(tt('From {} to {}').replaceFirst('{}', (line.first['title'] ?? '').toString())
              .replaceFirst('{}', (line.last['title'] ?? '').toString())),
          ]))),
        if (line.length < 2) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(tt('Connect counters to see the time between each of them on one timeline.'))),
        const SizedBox(height: 8),
        ...children,
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text(tt(error!), style: TextStyle(color: theme.colorScheme.error))),
      ]),
    );
  }
}
