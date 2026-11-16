import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:onespace/l10n/phrases.dart';

/// R75 (Ahmed): notifications should say more than "Ahmed added a memory".
/// For the items in the list, fetch the live details (when, where, dates,
/// status) and turn them into one short context line with an icon.
class NotificationContext {
  const NotificationContext(this.icon, this.text);
  final IconData icon;
  final String text;
}

class NotificationCategories {
  const NotificationCategories._();
  static const all = 'all', unread = 'unread', love = 'love', plans = 'plans', talk = 'talk', memories = 'memories';
  static const labels = {all: 'All', unread: 'Unread', love: 'Love', plans: 'Plans', talk: 'Messages', memories: 'Memories'};

  static String of(Map<String, dynamic> n) {
    final kind = n['kind']?.toString() ?? '';
    final object = n['object_kind']?.toString() ?? '';
    if (kind == 'gesture' || kind == 'letter' || kind.startsWith('checkin_')) return love;
    if (kind == 'message' || kind == 'trip_message' || kind == 'experience_comment' ||
        kind == 'mention' || kind == 'reply') {
      return talk;
    }
    if (object == 'memory' || object == 'scrapbook' || kind == 'scrapbook_invite') return memories;
    return plans;
  }

  static bool matches(Map<String, dynamic> n, String filter) => switch (filter) {
    all => true,
    unread => n['read_at'] == null,
    _ => of(n) == filter,
  };
}

/// "Today", "Yesterday", "Earlier this week", "Earlier".
String notificationDay(Object? raw, {DateTime? now}) {
  final at = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (at == null) return 'Earlier';
  final n = now ?? DateTime.now();
  final days = DateTime(n.year, n.month, n.day).difference(DateTime(at.year, at.month, at.day)).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return 'Earlier this week';
  return 'Earlier';
}

Future<Map<String, NotificationContext>> loadNotificationContext(
    BuildContext context, List<Map<String, dynamic>> items) async {
  final db = Supabase.instance.client;
  final loc = MaterialLocalizations.of(context);
  final ids = <String, Set<String>>{};
  String? idFor(Map<String, dynamic> n) {
    final object = n['object_kind']?.toString() ?? '';
    return switch (object) {
      'calendar' => (n['calendar_event_id'] ?? n['object_id'])?.toString(),
      'trip' => (n['trip_id'] ?? n['object_id'])?.toString(),
      'occasion' => (n['occasion_id'] ?? n['object_id'])?.toString(),
      'experience' => (n['experience_id'] ?? n['object_id'])?.toString(),
      'memory' || 'scrapbook' => (n['memory_id'] ?? n['object_id'])?.toString(),
      _ => n['object_id']?.toString(),
    };
  }
  for (final n in items) {
    final id = idFor(n);
    final object = n['object_kind']?.toString() ?? '';
    if (id != null) ids.putIfAbsent(object, () => {}).add(id);
  }
  String day(DateTime d) => loc.formatMediumDate(d);
  String time(DateTime d) => loc.formatTimeOfDay(TimeOfDay.fromDateTime(d));
  String until(DateTime d) {
    final today = DateTime.now();
    final n = DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (n == 0) return tt('Today');
    if (n == 1) return tt('Tomorrow');
    if (n > 1) return tt('In {} days').replaceFirst('{}', '$n');
    return '';
  }
  final byObject = <String, NotificationContext>{};
  Future<void> fetch(String object, String table, String columns,
      NotificationContext? Function(Map<String, dynamic>) build) async {
    final want = ids[object];
    if (want == null || want.isEmpty) return;
    try {
      final rows = await db.from(table).select('id,$columns').inFilter('id', want.toList());
      final found = <String>{};
      for (final r in rows) {
        found.add(r['id'].toString());
        final c = build(r);
        if (c != null) byObject['$object:${r['id']}'] = c;
      }
      for (final id in want.difference(found)) {
        byObject['$object:$id'] = NotificationContext(Icons.block, tt('No longer available'));
      }
    } catch (_) {}
  }
  final at = (Object? v) => DateTime.tryParse(v?.toString() ?? '')?.toLocal();
  await Future.wait([
    fetch('calendar', 'space_events', 'event_date,starts_at,location,archived_at', (r) {
      if (r['archived_at'] != null) return NotificationContext(Icons.delete_outline, tt('Removed'));
      final s = at(r['starts_at']);
      final d = s ?? at(r['event_date']);
      if (d == null) return null;
      final where = (r['location'] ?? '').toString().trim();
      return NotificationContext(Icons.event_outlined,
        [day(d), if (s != null) time(s), if (until(d).isNotEmpty) until(d), if (where.isNotEmpty) where].join(' · '));
    }),
    fetch('trip', 'shared_trips', 'destination,start_on,end_on,status,archived_at', (r) {
      if (r['archived_at'] != null) return NotificationContext(Icons.delete_outline, tt('Removed'));
      final s = at(r['start_on']), e = at(r['end_on']);
      final where = (r['destination'] ?? '').toString().trim();
      return NotificationContext(Icons.flight_takeoff_outlined, [
        if (where.isNotEmpty) where,
        if (s != null) e != null && e != s ? '${day(s)} – ${day(e)}' : day(s),
        if (s != null && until(s).isNotEmpty) until(s),
      ].join(' · '));
    }),
    fetch('occasion', 'occasion_plans', 'occasion_on,annual,archived_at', (r) {
      if (r['archived_at'] != null) return NotificationContext(Icons.delete_outline, tt('Removed'));
      final d = at(r['occasion_on']);
      if (d == null) return null;
      return NotificationContext(Icons.card_giftcard_outlined,
        [day(d), if (until(d).isNotEmpty) until(d)].join(' · '));
    }),
    fetch('reminder', 'reminders', 'due_at,urgent,archived_at', (r) {
      if (r['archived_at'] != null) return NotificationContext(Icons.delete_outline, tt('Removed'));
      final d = at(r['due_at']);
      if (d == null) return null;
      return NotificationContext(Icons.alarm_outlined,
        [day(d), time(d), if (r['urgent'] == true) tt('Urgent')].join(' · '));
    }),
    fetch('task', 'tasks', 'target_date,status,priority', (r) {
      final d = at(r['target_date']);
      final done = r['status'] == 'done' || r['status'] == 'completed';
      return NotificationContext(done ? Icons.check_circle_outline : Icons.checklist_outlined, [
        if (done) tt('Done'),
        if (!done && d != null) '${tt('Due date')}: ${day(d)}',
        if (r['priority'] == 'high' || r['priority'] == 'urgent') tt('High priority'),
      ].join(' · '));
    }),
    fetch('experience', 'shared_experiences', 'category,platform,planned_on,status', (r) {
      final d = at(r['planned_on']);
      return NotificationContext(Icons.movie_outlined, [
        if ((r['category'] ?? '').toString().isNotEmpty) tt(_title(r['category'].toString())),
        if ((r['platform'] ?? '').toString().isNotEmpty) r['platform'].toString(),
        if (d != null) '${tt('Planned')}: ${day(d)}',
      ].join(' · '));
    }),
    for (final m in const ['memory', 'scrapbook'])
      fetch(m, 'memories', 'memory_type,memory_date,place,archived_at', (r) {
        if (r['archived_at'] != null) return NotificationContext(Icons.delete_outline, tt('Removed'));
        final d = at(r['memory_date']);
        final place = (r['place'] ?? '').toString().trim();
        return NotificationContext(Icons.photo_album_outlined, [
          tt(_title((r['memory_type'] ?? 'story').toString())),
          if (d != null) day(d),
          if (place.isNotEmpty) place,
        ].join(' · '));
      }),
  ]);
  return {
    for (final n in items)
      if (n['id'] != null && byObject['${n['object_kind']}:${idFor(n)}'] != null)
        n['id'].toString(): byObject['${n['object_kind']}:${idFor(n)}']!,
  };
}

String _title(String key) => key.isEmpty ? key
  : key.replaceAll('_', ' ').replaceFirstMapped(RegExp(r'^.'), (m) => m.group(0)!.toUpperCase());
