import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onespace/l10n/phrases.dart';

import '../../core/form_kit.dart';
import '../settings/special_dates.dart';

/// A date copied into Counters only when the user explicitly chooses it.
/// The counter is an independent saved snapshot, not another automatically
/// rendered copy of a calendar, trip, flight or occasion entry.
class CounterSource {
  const CounterSource({required this.kind, required this.id, required this.title,
    required this.date, required this.emoji, required this.category,
    this.yearly = false, this.shared = true, this.note = ''});
  final String kind, id, title, emoji, category, note;
  final DateTime date;
  final bool yearly, shared;

  static DateTime? _date(Object? raw) =>
      raw == null ? null : DateTime.tryParse(raw.toString());
  static bool _shared(Map<String, dynamic> row) => row['visibility'] != 'private';

  static CounterSource? event(Map<String, dynamic> row) {
    final d = _date(row['event_date']) ?? _date(row['starts_at'])?.toLocal();
    if (d == null) return null;
    return CounterSource(kind: 'event', id: row['id'].toString(),
      title: (row['title'] ?? 'Event').toString(), date: d, emoji: '📅',
      category: 'life', yearly: row['recurrence'] == 'yearly',
      shared: _shared(row));
  }

  static CounterSource? occasion(Map<String, dynamic> row) {
    final d = _date(row['occasion_on']);
    if (d == null) return null;
    return CounterSource(kind: 'occasion', id: row['id'].toString(),
      title: (row['title'] ?? 'Occasion').toString(), date: d,
      emoji: '🎁', category: 'love', yearly: row['annual'] == true,
      shared: _shared(row));
  }

  static CounterSource? trip(Map<String, dynamic> row) {
    final d = _date(row['start_on']);
    if (d == null) return null;
    return CounterSource(kind: 'trip', id: row['id'].toString(),
      title: (row['title'] ?? 'Trip').toString(), date: d,
      emoji: '🧳', category: 'travel', shared: _shared(row));
  }

  static CounterSource? flight(Map<String, dynamic> row, {bool shared = true}) {
    final d = _date(row['departure_on']);
    if (d == null) return null;
    return CounterSource(kind: 'flight', id: row['id'].toString(),
      title: (row['title'] ?? 'Flight').toString(), date: d,
      emoji: '✈️', category: 'travel', shared: shared);
  }

  static CounterSource special(SpecialDate d, SpacePeople? people) {
    final now = DateTime.now();
    final date = d.year == null ? SpecialDateRules.nextOn(d, now)
        : DateTime(d.year!, d.month, d.day);
    final title = SpecialDateRules.label(d, (id) =>
      id == people?.me ? '' : (people?.partnerName ?? 'Partner'));
    return CounterSource(kind: 'special', id: d.id, title: title,
      date: date, emoji: d.kind == 'birthday' ? '🎂'
        : d.kind == 'anniversary' ? '💍' : '⭐',
      category: d.kind == 'birthday' ? 'family' : 'love', yearly: true);
  }

  static CounterSource? meeting(Map<String, dynamic> space, String which) {
    final date = _date(space[which == 'last' ? 'last_met_on' : 'next_meet_on']);
    if (date == null) return null;
    return CounterSource(kind: 'meeting', id: which,
      title: which == 'last' ? 'Since we last met' : 'Until we meet again',
      date: date, emoji: which == 'last' ? '🫂' : '🤍', category: 'love');
  }

  Map<String, dynamic> get prefill => {
    'title': title, 'on_date': date.toIso8601String().substring(0, 10),
    'emoji': emoji, 'category': category, 'yearly': yearly,
    'visibility': shared ? 'shared' : 'private',
  };
}

/// User-driven source selector. RLS on each table protects private records.
/// A flight inherits its trip's visibility.
Future<CounterSource?> pickCounterSource(BuildContext context, String spaceId) async {
  final db = Supabase.instance.client;
  final sources = <CounterSource>[];
  try {
    final results = await Future.wait([
      db.from('space_events').select('id,title,event_date,starts_at,recurrence,visibility')
        .eq('space_id', spaceId).isFilter('archived_at', null),
      db.from('occasion_plans').select('id,title,occasion_on,annual,visibility')
        .eq('space_id', spaceId).isFilter('archived_at', null),
      db.from('shared_trips').select('id,title,start_on,visibility')
        .eq('space_id', spaceId).isFilter('archived_at', null),
    ]);
    for (final r in results[0]) { final v = CounterSource.event(r); if (v != null) sources.add(v); }
    for (final r in results[1]) { final v = CounterSource.occasion(r); if (v != null) sources.add(v); }
    final tripRows = results[2];
    final visibility = <String, bool>{};
    for (final r in tripRows) {
      visibility[r['id'].toString()] = r['visibility'] != 'private';
      final v = CounterSource.trip(r); if (v != null) sources.add(v);
    }
    if (visibility.isNotEmpty) {
      final flights = await db.from('trip_flight_options')
        .select('id,trip_id,title,departure_on')
        .inFilter('trip_id', visibility.keys.toList()).isFilter('archived_at', null);
      for (final r in flights) {
        final v = CounterSource.flight(r, shared: visibility[r['trip_id'].toString()] ?? false);
        if (v != null) sources.add(v);
      }
    }
    final people = await SpacePeople.load();
    for (final d in await loadSpecialDates(spaceId)) { sources.add(CounterSource.special(d, people)); }
    final sp = await db.from('spaces').select('last_met_on,next_meet_on')
      .eq('id', spaceId).maybeSingle();
    if (sp != null) {
      for (final k in ['last', 'next']) {
        final v = CounterSource.meeting(sp, k); if (v != null) sources.add(v);
      }
    }
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tt('Could not load dates. Check your connection and try again.'))));
    return null;
  }
  if (!context.mounted) return null;
  sources.sort((a, b) => a.date.compareTo(b.date));
  const names = {'special': 'Special dates', 'event': 'Calendar events',
    'occasion': 'Occasions', 'trip': 'Trips', 'flight': 'Flights', 'meeting': 'How we live'};
  final groups = ['special', 'event', 'occasion', 'trip', 'flight', 'meeting'];
  return showModalBottomSheet<CounterSource>(context: context, showDragHandle: true,
    isScrollControlled: true, builder: (ctx) => SafeArea(child: SizedBox(
      height: MediaQuery.sizeOf(ctx).height * .72,
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(tt('Choose a date for your counter'),
            style: Theme.of(ctx).textTheme.titleLarge)),
        Expanded(child: sources.isEmpty
          ? Center(child: Text(tt('No dated items to choose from yet.')))
          : ListView(children: [
            for (final group in groups) if (sources.any((s) => s.kind == group)) ...[
              Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 5),
                child: Text(tt(names[group]!), style: Theme.of(ctx).textTheme.titleMedium)),
              for (final s in sources.where((s) => s.kind == group))
                ListTile(leading: Text(s.emoji, style: const TextStyle(fontSize: 23)),
                  title: Text(s.title),
                  subtitle: Text('${MaterialLocalizations.of(ctx).formatMediumDate(s.date)}'
                    '${s.yearly ? ' · ${tt('Every year')}' : ''}'
                    '${s.shared ? '' : ' · ${tt('Only me')}'}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(ctx, s)),
            ],
          ])),
      ]))));
}
