import 'package:material_ui/material_ui.dart';

import '../calendar/calendar_event_editor.dart';
import '../coordinate/new_activity_screen.dart';
import '../memories/memories_screen.dart';
import '../notes/quill_note_editor_screen.dart';
import '../occasions/occasions_screen.dart';
import '../plans/plans_screen.dart';
import '../reminders/reminders_screen.dart';
import '../world/trips_screen.dart';
import 'package:onespace/l10n/phrases.dart';

/// The eight Quick add choices, in the order the spec lists them (2.1).
enum QuickAddKind {
  reminder('Reminder', Icons.alarm_add_outlined),
  todo('To-do', Icons.add_task_outlined),
  event('Event', Icons.event_outlined),
  note('Note', Icons.note_add_outlined),
  research('Something to research', Icons.travel_explore_outlined),
  gift('Gift idea', Icons.card_giftcard_outlined),
  trip('Trip', Icons.flight_takeoff_outlined),
  memory('Memory', Icons.add_photo_alternate_outlined);

  const QuickAddKind(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// R51: "+ Quick add" from Today. Every choice opens that item's own full
/// page in draft; closing it without saving creates nothing.
Future<void> showQuickAdd(BuildContext context, {required String spaceId}) async {
  final kind = await showModalBottomSheet<QuickAddKind>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(child: Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 16),
      child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 10),
          child: Text(tt('Quick add'), style: Theme.of(ctx).textTheme.titleLarge)),
        GridView.count(
          crossAxisCount: 4, shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: .85,
          children: [
            for (final k in QuickAddKind.values) InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pop(ctx, k),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                CircleAvatar(radius: 22,
                  backgroundColor: Theme.of(ctx).colorScheme.primaryContainer,
                  child: Icon(k.icon, color: Theme.of(ctx).colorScheme.onPrimaryContainer)),
                const SizedBox(height: 6),
                Text(tt(k.label), textAlign: TextAlign.center, maxLines: 2,
                  style: Theme.of(ctx).textTheme.labelSmall),
              ])),
          ]),
      ]))));
  if (kind == null || !context.mounted) return;
  await openQuickAdd(context, kind, spaceId: spaceId);
}

/// Opens the draft page for [kind]. [title] and [details] pre-fill where the
/// page supports it (used by "Items to sort").
Future<void> openQuickAdd(BuildContext context, QuickAddKind kind,
    {required String spaceId, String title = '', String details = ''}) {
  final Widget page = switch (kind) {
    QuickAddKind.reminder => ReminderEditorScreen(spaceId: spaceId),
    QuickAddKind.todo => const PlansScreen(startNewTask: true),
    QuickAddKind.event => CalendarEventEditor(spaceId: spaceId,
        initialDate: DateTime.now()),
    QuickAddKind.note => QuillNoteEditorScreen(spaceId: spaceId),
    QuickAddKind.research => NewActivityScreen(spaceId: spaceId,
        initialTitle: title, initialDetails: details),
    QuickAddKind.gift => const OccasionsScreen(),
    QuickAddKind.trip => TripEditor(spaceId: spaceId),
    QuickAddKind.memory => MemoryEditorScreen(spaceId: spaceId),
  };
  return Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => page));
}
