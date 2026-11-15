import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/calendar/calendar_event_editor.dart';
import '../features/calendar/calendar_screen.dart';
import '../features/calendar/calendar_rules.dart';
import '../features/connect/shared_experiences_screen.dart';
import '../features/coordinate/activity_detail_screen.dart';
import '../features/memories/memories_screen.dart';
import '../features/notes/notes_screen.dart';
import '../features/occasions/occasions_screen.dart';
import '../features/plans/plans_screen.dart';
import '../features/reminders/reminders_screen.dart';
import '../features/world/trips_screen.dart';

/// R53 (spec 6, backlog B-17, decision D10): item kinds that can be linked.
enum LinkKind {
  activity('Activity', Icons.hub_outlined),
  trip('Trip', Icons.flight_takeoff_outlined),
  occasion('Occasion', Icons.card_giftcard_outlined),
  experience('Experience', Icons.movie_outlined),
  event('Event', Icons.event_outlined),
  reminder('Reminder', Icons.alarm_outlined),
  task('To-do', Icons.checklist_outlined),
  note('Note', Icons.sticky_note_2_outlined),
  memory('Memory', Icons.photo_album_outlined);

  const LinkKind(this.label, this.icon);
  final String label;
  final IconData icon;

  static LinkKind? parse(Object? raw) {
    for (final k in values) {
      if (k.name == raw?.toString()) return k;
    }
    return null;
  }
}

class LinkedItem {
  const LinkedItem({required this.kind, required this.id, required this.title, this.linkId});
  final LinkKind kind;
  final String id, title;
  /// Null for built-in links (a reminder's own source) that cannot be unlinked here.
  final String? linkId;

  static List<LinkedItem> parseAll(Object? raw) {
    final found = <LinkedItem>[];
    for (final row in raw is List ? raw : const []) {
      if (row is! Map) continue;
      final kind = LinkKind.parse(row['kind']);
      final id = row['id']?.toString();
      if (kind == null || id == null) continue;
      found.add(LinkedItem(kind: kind, id: id,
        title: (row['title']?.toString().trim().isNotEmpty ?? false) ? row['title'].toString() : kind.label,
        linkId: row['link_id']?.toString()));
    }
    found.sort((a, b) => a.kind.index != b.kind.index
        ? a.kind.index.compareTo(b.kind.index) : a.title.compareTo(b.title));
    return found;
  }
}

/// Opens any linked item on its own screen.
Future<void> openLinkedItem(BuildContext context, LinkKind kind, String id) {
  final Widget page = switch (kind) {
    LinkKind.activity => ActivityScreen(id: id),
    LinkKind.trip => TripsScreen(initialTripId: id),
    LinkKind.occasion => OccasionsScreen(initialPlanId: id),
    LinkKind.experience => SharedExperiencesScreen(initialExperienceId: id),
    LinkKind.event => CalendarScreen(initialEventId: id),
    LinkKind.reminder => RemindersScreen(initialReminderId: id),
    LinkKind.task => PlansScreen(focusTaskId: id),
    LinkKind.note => NotesScreen(initialNoteId: id),
    LinkKind.memory => MemoriesScreen(initialMemoryId: id),
  };
  return Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => page));
}

/// One horizontal strip of linked items (spec 6.3). Tap opens; long-press
/// offers Unlink. Shows nothing when there are no links; items the viewer
/// cannot see are never returned by the server.
class LinkedItemsStrip extends StatefulWidget {
  const LinkedItemsStrip({super.key, required this.kind, required this.id});
  final LinkKind kind;
  final String id;
  @override State<LinkedItemsStrip> createState() => LinkedItemsStripState();
}

class LinkedItemsStripState extends State<LinkedItemsStrip> {
  // Looked up lazily so screens that embed the strip still work where the
  // backend is not initialised (widget tests, previews).
  SupabaseClient get db => Supabase.instance.client;
  List<LinkedItem> items = const [];

  @override void initState() { super.initState(); reload(); }

  @override void didUpdateWidget(covariant LinkedItemsStrip old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) reload();
  }

  Future<void> reload() async {
    try {
      final raw = await db.rpc('item_linked', params: {'p_kind': widget.kind.name, 'p_id': widget.id});
      if (mounted) setState(() => items = LinkedItem.parseAll(raw));
    } catch (_) {/* Links are optional context; the item itself still works. */}
  }

  Future<void> _unlink(LinkedItem item) async {
    if (item.linkId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This link is part of the reminder itself. Edit the reminder to change it.')));
      return;
    }
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Unlink?'),
      content: Text('"${item.title}" stays as it is; only the link is removed.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Unlink')),
      ]));
    if (ok != true) return;
    try {
      await db.from('item_links').update({'unlinked_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', item.linkId!);
      await reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not unlink.')));
      }
    }
  }

  @override Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        Padding(padding: const EdgeInsets.only(right: 6, top: 12),
          child: Text('Linked', style: Theme.of(context).textTheme.labelMedium)),
        for (final item in items) Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onLongPress: () => _unlink(item),
            child: ActionChip(
              avatar: Icon(item.kind.icon, size: 18),
              label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180),
                child: Text(item.title, overflow: TextOverflow.ellipsis)),
              onPressed: () async {
                await openLinkedItem(context, item.kind, item.id);
                await reload();
              }))),
      ]),
    );
  }
}

/// What "Create from this" offers for a source item (spec 6.2).
enum CreateFromAction {
  reminder('Create reminder', Icons.alarm_add_outlined),
  calendar('Add to calendar', Icons.event_available_outlined),
  todo('Make a to-do', Icons.add_task_outlined),
  note('Add a note', Icons.note_add_outlined),
  turnIntoTrip('Turn into trip', Icons.flight_takeoff_outlined),
  leaveForAirport('Leave-for-airport reminder', Icons.local_taxi_outlined),
  checkIn('Online check-in reminder', Icons.airplane_ticket_outlined),
  preparation('Preparation reminder', Icons.checklist_rtl_outlined),
  planDate('Plan a date', Icons.favorite_outline);

  const CreateFromAction(this.label, this.icon);
  final String label;
  final IconData icon;

  /// Common actions first, then the ones that only make sense for [kind].
  static List<CreateFromAction> forKind(LinkKind kind) => [
    reminder, calendar, todo, note,
    ...switch (kind) {
      LinkKind.activity => const [turnIntoTrip],
      LinkKind.trip => const [leaveForAirport, checkIn],
      LinkKind.occasion => const [preparation],
      LinkKind.experience => const [planDate],
      _ => const <CreateFromAction>[],
    },
  ];

  /// Pre-filled title for the new item.
  String titleFor(String source) => switch (this) {
    leaveForAirport => 'Leave for the airport · $source',
    checkIn => 'Online check-in · $source',
    preparation => 'Prepare for $source',
    planDate => 'Date: $source',
    turnIntoTrip => source,
    _ => source,
  };

  /// Pre-filled due time: trip day 6:00 AM, check-in the day before 9:00 AM,
  /// preparation a week before at 9:00 AM; otherwise none.
  DateTime? dueFor(DateTime? sourceDate) {
    if (sourceDate == null) return null;
    final day = DateTime(sourceDate.year, sourceDate.month, sourceDate.day);
    return switch (this) {
      leaveForAirport => day.add(const Duration(hours: 6)),
      checkIn => day.subtract(const Duration(days: 1)).add(const Duration(hours: 9)),
      preparation => day.subtract(const Duration(days: 7)).add(const Duration(hours: 9)),
      reminder => day.add(const Duration(hours: 9)),
      _ => null,
    };
  }
}

/// The "Create from this" button for an item's page or menu. The new item is
/// pre-filled (title, date, visibility) and linked automatically, both ways.
class CreateFromThisButton extends StatelessWidget {
  const CreateFromThisButton({super.key, required this.kind, required this.id,
    required this.spaceId, required this.title, this.date, this.stripKey, this.shared = true});
  final LinkKind kind;
  final String id, spaceId, title;
  final DateTime? date;
  final bool shared;
  final GlobalKey<LinkedItemsStripState>? stripKey;

  @override Widget build(BuildContext context) => IconButton(
    tooltip: 'Create from this',
    icon: const Icon(Icons.add_link),
    onPressed: () => createFromThis(context, kind: kind, id: id, spaceId: spaceId,
        title: title, date: date, shared: shared,
        onLinked: () => stripKey?.currentState?.reload()));
}

Future<void> createFromThis(BuildContext context, {required LinkKind kind,
    required String id, required String spaceId, required String title,
    DateTime? date, bool shared = true, VoidCallback? onLinked}) async {
  final action = await showModalBottomSheet<CreateFromAction>(
    context: context, showDragHandle: true,
    builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(title: Text('Create from "$title"', maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700))),
      for (final a in CreateFromAction.forKind(kind)) ListTile(
        leading: Icon(a.icon), title: Text(a.label), onTap: () => Navigator.pop(ctx, a)),
      const SizedBox(height: 8),
    ])));
  if (action == null || !context.mounted) return;
  final db = Supabase.instance.client;
  Future<void> link(LinkKind to, String toId) async {
    try {
      await db.from('item_links').insert({'space_id': spaceId,
        'from_kind': kind.name, 'from_id': id, 'to_kind': to.name, 'to_id': toId});
      onLinked?.call();
    } catch (_) {/* The new item exists either way; only the link failed. */}
  }
  final newTitle = action.titleFor(title);
  switch (action) {
    case CreateFromAction.reminder:
    case CreateFromAction.leaveForAirport:
    case CreateFromAction.checkIn:
    case CreateFromAction.preparation:
      await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
        builder: (_) => ReminderEditorScreen(spaceId: spaceId, initialTitle: newTitle,
          initialDue: action.dueFor(date), initialShared: shared,
          onCreated: (newId) => link(LinkKind.reminder, newId))));
    case CreateFromAction.calendar:
    case CreateFromAction.planDate:
      await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
        builder: (_) => CalendarEventEditor(spaceId: spaceId, initialTitle: newTitle,
          initialDate: date ?? DateTime.now(),
          onCreated: (newId) => link(LinkKind.event, newId))));
    case CreateFromAction.turnIntoTrip:
      await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
        builder: (_) => TripEditor(spaceId: spaceId, prefill: {'title': newTitle},
          onCreated: (newId) => link(LinkKind.trip, newId))));
    case CreateFromAction.todo:
      try {
        final created = await db.from('tasks').insert({
          'space_id': spaceId, 'created_by': db.auth.currentUser!.id,
          'title': newTitle, 'status': 'open', 'visibility': shared ? 'shared' : 'private',
          if (date != null) 'target_date': CalendarRules.sqlDate(date),
        }).select('id').single();
        await link(LinkKind.task, created['id'].toString());
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('To-do "$newTitle" added and linked.'),
            action: SnackBarAction(label: 'Open', onPressed: () =>
              openLinkedItem(context, LinkKind.task, created['id'].toString()))));
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not add the to-do.')));
        }
      }
    case CreateFromAction.note:
      try {
        final created = await db.from('notes').insert({
          'space_id': spaceId, 'created_by': db.auth.currentUser!.id,
          'title': 'Notes · $newTitle', 'body': '', 'visibility': shared ? 'shared' : 'private',
        }).select('id').single();
        await link(LinkKind.note, created['id'].toString());
        if (context.mounted) await openLinkedItem(context, LinkKind.note, created['id'].toString());
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not add the note.')));
        }
      }
  }
}
