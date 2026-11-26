import 'package:supabase_flutter/supabase_flutter.dart';

/// Named counter timelines (26 Nov 2026, decision D100; database 0321).
/// A timeline has a name and holds any number of counters; one counter can be on
/// several timelines. A timeline is private (only its owner) or shared (the couple),
/// and only holds counters of the same kind.
class NamedTimeline {
  NamedTimeline({required this.id, required this.title, this.spaceId, this.privateSpaceId,
      this.counterIds = const []});
  final String id, title;
  final String? spaceId, privateSpaceId;
  final List<String> counterIds;
  bool get shared => spaceId != null;

  static NamedTimeline fromRow(Map<String, dynamic> r) => NamedTimeline(
        id: r['id'].toString(),
        title: (r['title'] ?? '').toString(),
        spaceId: r['space_id']?.toString(),
        privateSpaceId: r['private_space_id']?.toString(),
        counterIds: [
          for (final m in (r['counter_timeline_members'] as List? ?? const []))
            if (m is Map && m['counter_id'] != null) m['counter_id'].toString(),
        ],
      );

  /// True when [counterRow] may be put on this timeline (same private/shared scope).
  bool fits(Map<String, dynamic> counterRow) =>
      counterRow['space_id']?.toString() == spaceId &&
      counterRow['private_space_id']?.toString() == privateSpaceId;

  static String? validateTitle(String title) {
    final t = title.trim();
    if (t.isEmpty) return 'Give the timeline a name.';
    if (t.length > 80) return 'Keep the name under 80 characters.';
    return null;
  }
}

class CounterTimelinesStore {
  CounterTimelinesStore(this.db);
  final SupabaseClient db;

  /// Every timeline the person can see. Empty if the backend has no timelines yet.
  Future<List<NamedTimeline>> load() async {
    final rows = await db.from('counter_timelines')
        .select('id,title,space_id,private_space_id,counter_timeline_members(counter_id)')
        .order('created_at');
    return [for (final r in rows) NamedTimeline.fromRow(Map<String, dynamic>.from(r))];
  }

  Future<NamedTimeline> create(String title, {String? spaceId, String? privateSpaceId}) async {
    final r = await db.from('counter_timelines').insert({
      'title': title.trim(),
      if (spaceId != null) 'space_id': spaceId,
      if (privateSpaceId != null) 'private_space_id': privateSpaceId,
    }).select('id,title,space_id,private_space_id').single();
    return NamedTimeline.fromRow(Map<String, dynamic>.from(r));
  }

  Future<void> rename(String id, String title) =>
      db.from('counter_timelines').update({'title': title.trim()}).eq('id', id);

  Future<void> delete(String id) => db.from('counter_timelines').delete().eq('id', id);

  Future<void> add(String timelineId, String counterId) => db.from('counter_timeline_members')
      .upsert({'timeline_id': timelineId, 'counter_id': counterId}, ignoreDuplicates: true);

  Future<void> remove(String timelineId, String counterId) => db.from('counter_timeline_members')
      .delete().eq('timeline_id', timelineId).eq('counter_id', counterId);
}
