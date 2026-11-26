import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:onespace/l10n/phrases.dart';
import 'counter_chains.dart';
import 'counters_screen.dart';
import 'smart_duration.dart';

/// 26 Nov 2026: the connected counters timeline on its own page. Any number of
/// counters, oldest first, with the time between each pair of neighbouring points.
/// "Today" appears only when it falls between the first and the last point.
class ConnectedCountersScreen extends StatefulWidget {
  const ConnectedCountersScreen({super.key, required this.startId, required this.all});
  final String startId;
  /// Saved, non-yearly counters the person can see (the "day itself" points).
  final List<CounterPoint> all;
  @override
  State<ConnectedCountersScreen> createState() => _ConnectedCountersScreenState();
}

class _ConnectedCountersScreenState extends State<ConnectedCountersScreen> {
  final db = Supabase.instance.client;
  late List<CounterPoint> points = [for (final p in widget.all) if (p.saved && !p.yearly) p];
  bool busy = false;
  String? error;

  List<CounterLink> get _links => [
        for (final p in points)
          CounterLink(id: p.row!['id'].toString(), date: p.date, linkedTo: p.row!['linked_counter_id']?.toString()),
      ];
  String _id(CounterPoint p) => p.row!['id'].toString();

  Future<void> _apply(Map<String, String?> changes) async {
    if (changes.isEmpty) return;
    setState(() { busy = true; error = null; });
    try {
      for (final e in changes.entries) {
        await db.from('space_counters').update({'linked_counter_id': e.value}).eq('id', e.key);
      }
      setState(() {
        points = [
          for (final p in points)
            changes.containsKey(_id(p))
                ? CounterPoint(id: p.id, title: p.title, date: p.date, emoji: p.emoji,
                    row: {...p.row!, 'linked_counter_id': changes[_id(p)]}, source: p.source, yearly: p.yearly,
                    pinned: p.pinned, start: p.start, yearKnown: p.yearKnown, birthday: p.birthday, original: p.original)
                : p,
        ];
      });
    } catch (_) {
      setState(() => error = 'Could not save. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _add() async {
    final members = CounterChains.group(widget.startId, _links).map((c) => c.id).toSet();
    // The database keeps a timeline inside one space: private with private, shared with shared.
    final start = points.where((p) => _id(p) == widget.startId).firstOrNull;
    bool sameScope(CounterPoint p) => start == null ||
        (p.row!['space_id']?.toString() == start.row!['space_id']?.toString() &&
         p.row!['private_space_id']?.toString() == start.row!['private_space_id']?.toString());
    final others = [for (final p in points) if (!members.contains(_id(p)) && sameScope(p)) p];
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tt('All your counters are already on this timeline.'))));
      return;
    }
    final hit = await showModalBottomSheet<CounterPoint>(context: context, showDragHandle: true, isScrollControlled: true,
      builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true, children: [
        ListTile(title: Text(tt('Add a counter to this timeline'), style: const TextStyle(fontWeight: FontWeight.w700))),
        for (final o in others) ListTile(
          leading: Text(o.emoji.isEmpty ? '📌' : o.emoji, style: const TextStyle(fontSize: 22)),
          title: Text(o.title), subtitle: Text(MaterialLocalizations.of(ctx).formatMediumDate(o.date)),
          onTap: () => Navigator.pop(ctx, o)),
      ])));
    if (hit == null) return;
    await _apply(CounterChains.connect(widget.startId, _id(hit), _links));
  }

  Future<void> _remove(CounterPoint p) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(scrollable: true,
      title: Text(tt('Remove from this timeline?')),
      content: Text(tt('The counter stays; only its connection to this timeline is removed. The other counters stay connected.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tt('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tt('Remove'))),
      ]));
    if (ok != true) return;
    await _apply(CounterChains.remove(_id(p), _links));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    final members = CounterChains.group(widget.startId, _links).map((c) => c.id).toList();
    final byId = {for (final p in points) _id(p): p};
    final line = [for (final id in members) if (byId[id] != null) byId[id]!];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final showToday = CounterChains.showToday([for (final p in line) p.date], today);
    final primary = theme.colorScheme.primary;

    Widget point(CounterPoint p) => Card(elevation: 0, child: ListTile(
      leading: Text(p.emoji.isEmpty ? '📌' : p.emoji, style: const TextStyle(fontSize: 26)),
      title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${loc.formatMediumDate(p.date)} · ${SmartSpan.between(now, p.date).sentence}'),
      trailing: line.length > 1
          ? IconButton(tooltip: tt('Remove from this timeline'), icon: const Icon(Icons.link_off), onPressed: busy ? null : () => _remove(p))
          : null));
    Widget gap(DateTime a, DateTime b) {
      final s = SmartSpan.between(a, b);
      return Padding(padding: const EdgeInsetsDirectional.only(start: 28, top: 2, bottom: 2),
        child: Row(children: [
          Container(width: 3, height: 34, color: primary.withValues(alpha: .5)),
          const SizedBox(width: 12),
          Expanded(child: Text(s.isToday ? tt('The same day') : s.label,
            style: theme.textTheme.titleSmall?.copyWith(color: primary, fontWeight: FontWeight.w700))),
        ]));
    }
    Widget todayRow() => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      Expanded(child: Divider(color: theme.colorScheme.tertiary, thickness: 2)),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('${tt('Today')} · ${loc.formatMediumDate(today)}',
          style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.tertiary))),
      Expanded(child: Divider(color: theme.colorScheme.tertiary, thickness: 2)),
    ]));

    final children = <Widget>[];
    for (var i = 0; i < line.length; i++) {
      if (i > 0) {
        final prev = line[i - 1].date, cur = line[i].date;
        if (showToday && !today.isBefore(prev) && today.isBefore(cur) && today.isAfter(prev)) {
          children..add(gap(prev, today))..add(todayRow())..add(gap(today, cur));
        } else {
          children.add(gap(prev, cur));
        }
      }
      children.add(point(line[i]));
    }

    // Going back hands the updated links to the counter page.
    return PopScope<List<CounterPoint>>(canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) Navigator.of(context).pop(points); },
      child: Scaffold(
      appBar: AppBar(title: Text(tt('Connected timeline'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: busy ? null : _add,
        icon: const Icon(Icons.add_link), label: Text(tt('Connect a counter'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
        if (line.length > 1) Card(elevation: 0, color: theme.colorScheme.primaryContainer, child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tt('{} counters').replaceFirst('{}', '${line.length}'), style: theme.textTheme.labelLarge),
            Text(SmartSpan.between(line.first.date, line.last.date).label,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text(tt('From {} to {}').replaceFirst('{}', line.first.title).replaceFirst('{}', line.last.title)),
          ]))),
        if (line.length < 2) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(tt('Connect counters to see the time between each of them on one timeline.'))),
        const SizedBox(height: 8),
        ...children,
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text(tt(error!), style: TextStyle(color: theme.colorScheme.error))),
      ]),
    ));
  }
}
