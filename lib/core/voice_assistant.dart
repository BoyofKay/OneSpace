import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/calendar/calendar_event_editor.dart';
import '../features/calendar/calendar_rules.dart';
import '../features/calendar/calendar_screen.dart';
import '../features/checkins/checkins_screen.dart';
import '../features/connect/couple_letters_screen.dart';
import '../features/connect/partner_gestures_screen.dart';
import '../features/connect/shared_experiences_screen.dart';
import '../features/coordinate/coordinate_screen.dart';
import '../features/memories/memories_screen.dart';
import '../features/notes/notes_screen.dart';
import '../features/notes/quill_note_editor_screen.dart';
import '../features/occasions/occasions_screen.dart';
import '../features/plans/plans_screen.dart';
import '../features/reminders/reminders_screen.dart';
import '../features/search/global_search_screen.dart';
import '../features/settings/onespace_settings_screen.dart';
import '../features/share_in/items_to_sort_screen.dart';
import '../features/world/trips_screen.dart';
import '../features/world/world_contacts_screen.dart';
import 'current_space_cache.dart';
import 'voice.dart';
import 'voice_commands.dart';

/// Listens once and carries out the command.
class VoiceAssistant {
  const VoiceAssistant._();

  static const examples = [
    '“Remind me to call the clinic tomorrow at 5 pm”',
    '“Add milk to the groceries list”',
    '“Take a note: the Wi-Fi password is on the router”',
    '“Add an event dinner with Sara on Saturday at 7:30”',
    '“What’s on today?” · “Read my reminders”',
    '“Open the calendar” · “Search for passport”',
    '“Send a little love”',
  ];

  static Future<void> start(BuildContext context, {VoidCallback? goToday}) async {
    final heard = await Voice.listen(context);
    if (heard == null || heard.trim().isEmpty || !context.mounted) return;
    final command = VoiceCommandRules.parse(heard, DateTime.now());
    await run(context, command, goToday: goToday);
  }

  static Future<void> _open(BuildContext context, Widget page) =>
      Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => page));

  static Future<void> run(BuildContext context, VoiceCommand c, {VoidCallback? goToday}) async {
    final db = Supabase.instance.client;
    final space = await CurrentSpaceCache.instance.get();
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    void heard(String what) => messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 2), content: Text('“${c.heard}” · $what')));

    switch (c.action) {
      case VoiceAction.help:
        await showModalBottomSheet<void>(context: context, showDragHandle: true,
          builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Things you can say', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 10),
                for (final e in examples) Padding(padding: const EdgeInsets.only(bottom: 8),
                  child: Text(e, style: Theme.of(ctx).textTheme.bodyLarge)),
              ]))));
      case VoiceAction.reminder:
        if (space == null) return;
        heard('new reminder');
        await _open(context, ReminderEditorScreen(spaceId: space, initialTitle: c.title,
          initialDue: c.when));
      case VoiceAction.note:
        if (space == null) return;
        heard('new note');
        await _open(context, QuillNoteEditorScreen(spaceId: space,
          initialTitle: c.title.length > 60 ? '${c.title.substring(0, 57)}…' : c.title,
          initialBody: c.title));
      case VoiceAction.event:
        if (space == null) return;
        heard('new event');
        await _open(context, CalendarEventEditor(spaceId: space, initialTitle: c.title,
          initialDate: c.when ?? DateTime.now(),
          initialTime: c.timeGiven && c.when != null ? TimeOfDay.fromDateTime(c.when!) : null));
      case VoiceAction.newList:
        heard('new list');
        await _open(context, PlansScreen(startNewTask: true, newListTitle: c.title));
      case VoiceAction.addToList:
        if (space == null) return;
        await _addToList(context, db, space, c);
      case VoiceAction.open:
        if (c.target == 'today') { goToday?.call(); return; }
        final page = switch (c.target) {
          'calendar' => const CalendarScreen() as Widget,
          'reminders' => const RemindersScreen(),
          'notes' => const NotesScreen(),
          'todo' => const PlansScreen(),
          'trips' => const TripsScreen(),
          'memories' => const MemoriesScreen(),
          'letters' => const CoupleLettersScreen(),
          'activities' => const CoordinateScreen(),
          'occasions' => const OccasionsScreen(),
          'contacts' => const WorldContactsScreen(),
          'experiences' => const SharedExperiencesScreen(),
          'checkin' => const CheckinsScreen(),
          'settings' => const OneSpaceSettingsScreen(),
          'search' => const GlobalSearchScreen(),
          'sort' => const ItemsToSortScreen(),
          'love' => const PartnerGesturesScreen(),
          _ => null,
        };
        if (page != null) await _open(context, page);
      case VoiceAction.search:
        await _open(context, GlobalSearchScreen(initialQuery: c.title));
      case VoiceAction.love:
        await _open(context, const PartnerGesturesScreen());
      case VoiceAction.readToday:
        if (space == null) return;
        final text = await _todaySummary(db, space);
        if (context.mounted) await Voice.speak(context, text);
      case VoiceAction.readReminders:
        if (space == null) return;
        final text = await _remindersSummary(db, space);
        if (context.mounted) await Voice.speak(context, text);
      case VoiceAction.readNotes:
        if (space == null) return;
        final note = await db.from('notes').select('title,body').eq('space_id', space)
          .isFilter('archived_at', null).order('updated_at', ascending: false).limit(1).maybeSingle();
        if (!context.mounted) return;
        await Voice.speak(context, note == null ? 'There are no notes yet.'
          : 'Your latest note, ${note['title']}. ${note['body'] ?? ''}');
      case VoiceAction.unknown:
        await _chooseKind(context, c, space);
    }
  }

  static Future<void> _addToList(BuildContext context, SupabaseClient db, String space, VoiceCommand c) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final lists = await db.from('tasks').select('id,title,status').eq('space_id', space)
        .isFilter('migrated_to_list', null).neq('status', 'cancelled');
      final want = c.target.toLowerCase();
      Map<String, dynamic>? list;
      for (final l in lists) {
        final t = l['title'].toString().toLowerCase();
        if (t == want || t.contains(want) || want.contains(t)) { list = l; break; }
      }
      if (list == null) {
        if (!context.mounted) return;
        messenger.showSnackBar(SnackBar(content: Text('No list called “${c.target}”. Creating it…')));
        await _open(context, PlansScreen(startNewTask: true, newListTitle: _cap(c.target)));
        return;
      }
      final items = c.title.split(RegExp(r',| and ')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
      final rows = await db.from('task_checklist_items').insert([
        for (final i in items) {'task_id': list['id'], 'title': _cap(i)},
      ]).select('id');
      messenger.showSnackBar(SnackBar(
        content: Text('Added ${items.join(', ')} to ${list['title']}.'),
        action: SnackBarAction(label: 'Undo', onPressed: () async {
          final ids = [for (final r in rows) r['id']];
          try {
            await db.from('task_checklist_items').update({
              'archived_at': DateTime.now().toUtc().toIso8601String()}).inFilter('id', ids);
          } catch (_) {}
        })));
    } on PostgrestException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not add it: ${e.message}')));
    }
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static Future<void> _chooseKind(BuildContext context, VoiceCommand c, String? space) async {
    if (space == null) return;
    final pick = await showModalBottomSheet<String>(context: context, showDragHandle: true,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text('“${c.heard}”', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('What should this be?')),
        for (final o in const [('reminder', Icons.alarm_add_outlined, 'Reminder'),
          ('note', Icons.note_add_outlined, 'Note'), ('event', Icons.event_outlined, 'Event'),
          ('list', Icons.checklist_outlined, 'To-do list'), ('help', Icons.help_outline, 'What can I say?')])
          ListTile(leading: Icon(o.$2), title: Text(o.$3), onTap: () => Navigator.pop(ctx, o.$1)),
      ])));
    if (pick == null || !context.mounted) return;
    final again = switch (pick) {
      'reminder' => VoiceCommand(VoiceAction.reminder, title: c.title, heard: c.heard),
      'note' => VoiceCommand(VoiceAction.note, title: c.title, heard: c.heard),
      'event' => VoiceCommand(VoiceAction.event, title: c.title, when: DateTime.now(), heard: c.heard),
      'list' => VoiceCommand(VoiceAction.newList, title: c.title, heard: c.heard),
      _ => VoiceCommand(VoiceAction.help, heard: c.heard),
    };
    await run(context, again);
  }

  static String _time(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute == 0 ? '' : ':${t.minute.toString().padLeft(2, '0')}';
    return '$h$m ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  static Future<String> _todaySummary(SupabaseClient db, String space) async {
    final now = DateTime.now();
    final day = CalendarRules.sqlDate(now);
    final start = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    final end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1)).toUtc().toIso8601String();
    final parts = <String>[];
    try {
      final events = await db.from('space_events').select('title,starts_at').eq('space_id', space)
        .eq('event_date', day).isFilter('archived_at', null);
      for (final e in events) {
        final at = DateTime.tryParse(e['starts_at']?.toString() ?? '')?.toLocal();
        parts.add(at == null ? '${e['title']}' : '${e['title']} at ${_time(at)}');
      }
      final reminders = await db.from('reminders').select('title,due_at').eq('space_id', space)
        .isFilter('archived_at', null).gte('due_at', start).lt('due_at', end).order('due_at');
      for (final r in reminders) {
        final at = DateTime.tryParse(r['due_at']?.toString() ?? '')?.toLocal();
        parts.add('reminder: ${r['title']}${at == null ? '' : ' at ${_time(at)}'}');
      }
      final tasks = await db.from('tasks').select('title').eq('space_id', space)
        .eq('status', 'open').eq('target_date', day);
      for (final t in tasks) { parts.add('to-do list ${t['title']} is due'); }
    } catch (_) {
      return 'I could not load today right now.';
    }
    return 'Today: ${VoiceCommandRules.joinForSpeech(parts, empty: 'nothing planned. Enjoy your day.')}';
  }

  static Future<String> _remindersSummary(SupabaseClient db, String space) async {
    try {
      final rows = await db.from('reminders').select('title,due_at').eq('space_id', space)
        .isFilter('archived_at', null).gte('due_at', DateTime.now().toUtc().toIso8601String())
        .order('due_at').limit(6);
      if (rows.isEmpty) return 'You have no upcoming reminders.';
      final parts = [
        for (final r in rows) () {
          final at = DateTime.tryParse(r['due_at']?.toString() ?? '')?.toLocal();
          if (at == null) return '${r['title']}';
          final when = DateUtils.isSameDay(at, DateTime.now()) ? 'today'
            : DateUtils.isSameDay(at, DateTime.now().add(const Duration(days: 1))) ? 'tomorrow'
            : '${const ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'][at.weekday - 1]} ${at.day}';
          return '${r['title']}, $when at ${_time(at)}';
        }(),
      ];
      return 'Your next reminders: ${VoiceCommandRules.joinForSpeech(parts)}';
    } catch (_) {
      return 'I could not load your reminders right now.';
    }
  }
}
