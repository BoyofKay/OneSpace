import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_env.dart';

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
import '../features/occasions/occasion_rules.dart';
import '../features/occasions/occasions_screen.dart';
import '../features/plans/checklist_schedule.dart';
import '../features/plans/plans_screen.dart';
import '../features/plans/task_recurrence_rules.dart';
import '../features/profile/me_screen.dart';
import '../features/reminders/reminders_screen.dart';
import '../features/search/global_search_screen.dart';
import '../features/settings/onespace_settings_screen.dart';
import '../features/share_in/items_to_sort_screen.dart';
import '../features/world/trips_screen.dart';
import '../features/world/world_contacts_screen.dart';
import 'current_space_cache.dart';
import 'form_kit.dart';
import 'voice_commands.dart';
import 'voice_session_sheet.dart';
import 'package:onespace/l10n/phrases.dart';

/// What the assistant does with a command: say something, open a page,
/// offer choices, or end the conversation.
class VoiceReply {
  const VoiceReply(this.say, {this.open, this.end = false, this.goToday = false, this.choices = false});
  final String say;
  final Widget? open;
  final bool end;
  final bool goToday;
  /// Offer "Reminder · Note · Event · List" for the words that were heard.
  final bool choices;
}

/// R61: the voice assistant. Runs a conversation in [VoiceSessionSheet].
class VoiceAssistant {
  const VoiceAssistant._();

  static Future<void> start(BuildContext context, {VoidCallback? goToday}) =>
      VoiceSessionSheet.show(context, goToday: goToday);

  static const examplesEn = [
    '“Remind me to call the clinic tomorrow at 5 pm”',
    '“Add milk and eggs to the groceries list”',
    '“Check off milk on the groceries list”',
    '“Read the groceries list” · “What’s on today?”',
    '“I took my vitamins” · “Snooze the rent reminder for an hour”',
    '“I’m feeling great today” · “Send Kay a hug”',
    '“How many days until our anniversary?” · “When’s our next trip?”',
    '“Read Kay’s last letter” · “Read the Paris trip”',
    '“Take a note: …” · “Add an event dinner on Friday at 8”',
    '“Open the calendar” · “Search for passport”',
  ];
  static const examplesAr = [
    '«ذكرني أن أتصل بالعيادة بكرة الساعة 5 المساء»',
    '«أضف حليب وبيض إلى قائمة المشتريات»',
    '«اشطب الحليب من قائمة المشتريات»',
    '«اقرأ قائمة المشتريات» · «ماذا لدينا اليوم؟»',
    '«خلصت الدواء» · «أجّل الدواء ساعة»',
    '«أنا مبسوط اليوم» · «أرسل لها حضن»',
    '«كم يوم باقي على ذكرى زواجنا؟» · «متى رحلتنا القادمة؟»',
    '«اقرأ آخر رسالة» · «اقرأ رحلتنا القادمة»',
    '«اكتب ملاحظة …» · «أضف موعد عشاء يوم الجمعة الساعة 8»',
    '«افتح التقويم» · «ابحث عن جواز السفر»',
  ];

  static String _time(DateTime t, bool ar) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute == 0 ? '' : ':${t.minute.toString().padLeft(2, '0')}';
    return ar ? '$h$m ${t.hour >= 12 ? 'مساءً' : 'صباحًا'}' : '$h$m ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  static const _daysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _daysAr = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
  static const _monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'];
  static const _monthsAr = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو',
    'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

  static String _day(DateTime d, bool ar) {
    final today = DateTime.now();
    final diff = DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (diff == 0) return ar ? 'اليوم' : 'today';
    if (diff == 1) return ar ? 'غدًا' : 'tomorrow';
    if (diff > 1 && diff < 7) return ar ? 'يوم ${_daysAr[d.weekday - 1]}' : _daysEn[d.weekday - 1];
    return ar ? '${d.day} ${_monthsAr[d.month - 1]}' : '${_monthsEn[d.month - 1]} ${d.day}';
  }

  static String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  static String _join(List<String> p, bool ar, {String? empty}) => VoiceCommandRules.joinForSpeech(p,
    and: ar ? 'و' : 'and', sep: ar ? '، ' : ', ', empty: empty ?? (ar ? 'لا شيء.' : 'Nothing.'));

  /// Carries out [c]; returns what to say/show next.
  static Future<VoiceReply> handle(VoiceCommand c) async {
    final ar = c.lang == 'ar';
    String l(String en, String arText) => ar ? arText : en;
    final db = Supabase.instance.client;
    final space = await CurrentSpaceCache.instance.get();
    if (space == null && c.action != VoiceAction.stop && c.action != VoiceAction.help &&
        !(!OneSpaceEnv.isProduction &&
          (c.action == VoiceAction.note || c.action == VoiceAction.readNotes ||
           c.action == VoiceAction.reminder || c.action == VoiceAction.readReminders ||
           c.action == VoiceAction.reminderDone || c.action == VoiceAction.snooze ||
           c.action == VoiceAction.readActivity))) {
      return VoiceReply(l('Connect your shared space first.', 'اربط مساحتكما المشتركة أولًا.'), end: true);
    }
    final s = space ?? '';
    try {
      switch (c.action) {
        case VoiceAction.stop:
          return VoiceReply(l('Okay.', 'حاضر.'), end: true);
        case VoiceAction.help:
          return VoiceReply(l('Here are some things you can say.', 'هذه بعض الأشياء التي يمكنك قولها.'));
        case VoiceAction.unknown:
          return VoiceReply(l('What should this be?', 'ماذا تريد أن يكون هذا؟'), choices: true);

        // ---- open pages (nothing is saved until Save) ----
        case VoiceAction.reminder:
          return VoiceReply(l('Here is your reminder. Check it and tap Save.', 'هذا تذكيرك. راجعه واضغط حفظ.'),
            open: ReminderEditorScreen(spaceId: s, initialTitle: c.title, initialDue: c.when));
        case VoiceAction.note:
          return VoiceReply(l('Your note is ready to save.', 'ملاحظتك جاهزة للحفظ.'),
            open: QuillNoteEditorScreen(spaceId: s,
              initialTitle: c.title.length > 60 ? '${c.title.substring(0, 57)}…' : c.title, initialBody: c.title));
        case VoiceAction.event:
          return VoiceReply(l('Here is the event. Check it and tap Save.', 'هذا الموعد. راجعه واضغط حفظ.'),
            open: CalendarEventEditor(spaceId: s, initialTitle: c.title, initialDate: c.when ?? DateTime.now(),
              initialTime: c.timeGiven && c.when != null ? TimeOfDay.fromDateTime(c.when!) : null));
        case VoiceAction.newList:
          return VoiceReply(l('Starting a new list.', 'نبدأ قائمة جديدة.'),
            open: PlansScreen(startNewTask: true, newListTitle: c.title));
        case VoiceAction.search:
          return VoiceReply(l('Searching for ${c.title}.', 'أبحث عن ${c.title}.'),
            open: GlobalSearchScreen(initialQuery: c.title));
        case VoiceAction.love:
          return VoiceReply(l('Opening A little love.', 'أفتح لمسة حب.'), open: const PartnerGesturesScreen());
        case VoiceAction.open:
          if (c.target == 'today') return VoiceReply(l('Here is today.', 'هذا يومكم.'), goToday: true, end: true);
          final page = _page(c.target);
          return page == null ? VoiceReply(l("I don't know that page.", 'لا أعرف هذه الصفحة.')) : VoiceReply('', open: page);

        // ---- quick actions ----
        case VoiceAction.addToList:
          return await _addToList(db, s, c, ar);
        case VoiceAction.checkOff:
          return await _checkOff(db, s, c, ar);
        case VoiceAction.reminderDone:
        case VoiceAction.snooze:
          return await _reminderAction(db, s, c, ar);
        case VoiceAction.feeling:
          return await _feeling(db, s, c, ar);
        case VoiceAction.gesture:
          return await _gesture(db, s, c, ar);

        // ---- reading and questions ----
        case VoiceAction.readToday:
          return VoiceReply(await _dayText(db, s, DateTime.now(), ar));
        case VoiceAction.readDay:
          if (c.target == 'week') return VoiceReply(await _weekText(db, s, ar));
          return VoiceReply(await _dayText(db, s, c.when ?? DateTime.now().add(const Duration(days: 1)), ar));
        case VoiceAction.readReminders:
          return VoiceReply(await _remindersText(db, s, ar));
        case VoiceAction.readNotes:
          final noteQuery = OneSpaceEnv.isProduction
            ? db.from('notes').select('title,body').eq('space_id', s)
            : db.from('notes').select('title,body');
          final note = await noteQuery
            .isFilter('archived_at', null).order('updated_at', ascending: false).limit(1).maybeSingle();
          return VoiceReply(note == null ? l('There are no notes yet.', 'لا توجد ملاحظات بعد.')
            : l('Your latest note: ${note['title']}. ${note['body'] ?? ''}', 'آخر ملاحظة: ${note['title']}. ${note['body'] ?? ''}'));
        case VoiceAction.readLetter:
          return VoiceReply(await _letterText(db, s, ar));
        case VoiceAction.readList:
          return await _readList(db, s, c, ar);
        case VoiceAction.readActivity:
          return VoiceReply(await _activityText(db, s, c.target, ar));
        case VoiceAction.readTrip:
          return VoiceReply(await _tripText(db, s, c.target, ar));
        case VoiceAction.nextTrip:
          return VoiceReply(await _tripText(db, s, '', ar, short: true));
        case VoiceAction.nextReunion:
          return VoiceReply(await _reunionText(db, s, ar));
        case VoiceAction.countdown:
          return VoiceReply(await _countdownText(db, s, c.target, ar));
      }
    } on PostgrestException catch (e) {
      return VoiceReply(l('That did not work: ${e.message}', 'لم ينجح ذلك: ${e.message}'));
    } catch (_) {
      return VoiceReply(l('Something went wrong. Please try again.', 'حدث خطأ. حاول مرة أخرى.'));
    }
  }

  static Widget? _page(String key) => switch (key) {
    'calendar' => const CalendarScreen(),
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
    'me' => Scaffold(appBar: AppBar(title: Text(tt('Me'))), body: const MeScreen()),
    _ => null,
  };

  static Future<List<Map<String, dynamic>>> _lists(SupabaseClient db, String space) async =>
    List<Map<String, dynamic>>.from(await db.from('tasks')
      .select('id,title,status,recurrence,recurrence_rule').eq('space_id', space)
      .isFilter('migrated_to_list', null).neq('status', 'cancelled'));

  static String _cycleFor(Map<String, dynamic> list) {
    final raw = list['recurrence_rule'];
    final rule = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final rec = (list['recurrence'] ?? 'none').toString();
    final now = DateTime.now();
    return rule.isEmpty ? TaskRecurrenceRules.cycle(rec, now) : ChecklistSchedule.cycle(rec, rule, now);
  }

  static Future<VoiceReply> _addToList(SupabaseClient db, String s, VoiceCommand c, bool ar) async {
    final list = VoiceCommandRules.best(await _lists(db, s), (x) => x['title'].toString(), c.target);
    if (list == null) {
      return VoiceReply(ar ? 'لا توجد قائمة باسم ${c.target}. لننشئها.' : 'There is no ${c.target} list. Let’s create it.',
        open: PlansScreen(startNewTask: true, newListTitle: _cap(c.target)));
    }
    final items = c.title.split(RegExp(r',| and |، | و')).map((x) => x.trim()).where((x) => x.isNotEmpty)
      .map(_cap).toList();
    await db.from('task_checklist_items').insert([
      for (final i in items) {'task_id': list['id'], 'title': i.length > 200 ? i.substring(0, 200) : i},
    ]);
    return VoiceReply(ar ? 'أضفت ${_join(items, ar)} إلى ${list['title']}' : 'Added ${_join(items, ar)} to ${list['title']}');
  }

  static Future<VoiceReply?> _tryCheckOff(SupabaseClient db, String s, VoiceCommand c, bool ar) async {
    final lists = await _lists(db, s);
    final pool = <Map<String, dynamic>>[];
    if (c.target.isEmpty) {
      pool.addAll(lists);
    } else {
      final one = VoiceCommandRules.best(lists, (x) => x['title'].toString(), c.target);
      if (one != null) pool.add(one);
    }
    if (pool.isEmpty) return null;
    final items = List<Map<String, dynamic>>.from(await db.from('task_checklist_items')
      .select('id,title,task_id').inFilter('task_id', [for (final l in pool) l['id']]).isFilter('archived_at', null));
    final item = VoiceCommandRules.best(items, (x) => x['title'].toString(), c.title);
    if (item == null) return null;
    final list = pool.firstWhere((l) => l['id'] == item['task_id']);
    final cycle = _cycleFor(list);
    final me = db.auth.currentUser!.id;
    final existing = await db.from('task_checklist_checks').select('id').eq('item_id', item['id'])
      .eq('cycle_date', cycle).eq('user_id', me).limit(1);
    if (existing.isEmpty) {
      await db.from('task_checklist_checks').insert({'item_id': item['id'], 'cycle_date': cycle, 'completed': true});
    } else {
      await db.from('task_checklist_checks').update({'completed': true}).eq('id', existing.first['id']);
    }
    return VoiceReply(ar ? 'تم شطب ${item['title']} من ${list['title']}.' : 'Checked off ${item['title']} on ${list['title']}.');
  }

  static Future<VoiceReply> _checkOff(SupabaseClient db, String s, VoiceCommand c, bool ar) async =>
    await _tryCheckOff(db, s, c, ar) ?? VoiceReply(ar ? 'لم أجد ${c.title} في قوائمكما.'
      : 'I couldn’t find ${c.title} on your lists.');

  static Future<VoiceReply> _readList(SupabaseClient db, String s, VoiceCommand c, bool ar) async {
    final list = VoiceCommandRules.best(await _lists(db, s), (x) => x['title'].toString(), c.target);
    if (list == null) return VoiceReply(ar ? 'لم أجد قائمة ${c.target}.' : 'I couldn’t find the ${c.target} list.');
    final items = List<Map<String, dynamic>>.from(await db.from('task_checklist_items')
      .select('id,title').eq('task_id', list['id']).isFilter('archived_at', null).order('created_at'));
    if (items.isEmpty) return VoiceReply(ar ? 'قائمة ${list['title']} فارغة.' : '${list['title']} is empty.');
    final checks = await db.from('task_checklist_checks').select('item_id')
      .inFilter('item_id', [for (final i in items) i['id']]).eq('cycle_date', _cycleFor(list)).eq('completed', true);
    final done = {for (final x in checks) x['item_id']};
    final open = [for (final i in items) if (!done.contains(i['id'])) i['title'].toString()];
    if (open.isEmpty) return VoiceReply(ar ? 'كل ما في ${list['title']} تم.' : 'Everything on ${list['title']} is done.');
    return VoiceReply(ar ? '${list['title']}، ${open.length} متبقية: ${_join(open, ar)}'
      : '${list['title']}, ${open.length} left: ${_join(open, ar)}');
  }

  static Future<VoiceReply> _reminderAction(SupabaseClient db, String s, VoiceCommand c, bool ar) async {
    final query=OneSpaceEnv.isProduction
      ? db.from('reminders').select('id,title').eq('space_id',s)
      : db.from('reminders').select('id,title');
    final rows=List<Map<String,dynamic>>.from(await query
      .isFilter('archived_at',null).order('due_at',ascending:false).limit(200));
    final r = VoiceCommandRules.best(rows, (x) => x['title'].toString(), c.title);
    if (r == null) {
      if (c.action == VoiceAction.reminderDone) {
        // "I packed the chargers": maybe it is a list item.
        final viaList = s.isEmpty ? null :
          await _tryCheckOff(db, s, c.copyWith(action: VoiceAction.checkOff), ar);
        if (viaList != null) return viaList;
      }
      return VoiceReply(ar ? 'لم أجد تذكيرًا باسم ${c.title}.' : 'I couldn’t find a reminder called ${c.title}.');
    }
    if (c.action == VoiceAction.reminderDone) {
      await db.rpc('respond_to_reminder', params: {'p_reminder_id': r['id'], 'p_action': 'done',
        'p_note': null, 'p_snooze_until': null});
      return VoiceReply(ar ? 'أحسنت! تم ${r['title']}.' : 'Nice. ${r['title']} is done.');
    }
    final now = DateTime.now();
    final until = (c.number ?? 30) < 0 ? DateTime(now.year, now.month, now.day + 1, 9)
      : now.add(Duration(minutes: c.number ?? 30));
    await db.rpc('respond_to_reminder', params: {'p_reminder_id': r['id'], 'p_action': 'snooze',
      'p_note': null, 'p_snooze_until': until.toUtc().toIso8601String()});
    return VoiceReply(ar ? 'سأذكّرك بـ${r['title']} ${_day(until, ar)} الساعة ${_time(until, ar)}.'
      : 'I’ll remind you about ${r['title']} ${_day(until, ar)} at ${_time(until, ar)}.');
  }

  static Future<VoiceReply> _feeling(SupabaseClient db, String s, VoiceCommand c, bool ar) async {
    final me = db.auth.currentUser!.id;
    final day = CalendarRules.sqlDate(DateTime.now());
    final existing = await db.from('daily_checkins').select('id').eq('created_by', me).eq('checkin_date', day).limit(1);
    final mood = c.number ?? 3;
    if (existing.isEmpty) {
      await db.from('daily_checkins').insert({'space_id': s, 'created_by': me, 'checkin_date': day,
        'mood': mood, 'message': c.title, 'gratitude': '', 'visibility': 'shared'});
    } else {
      await db.from('daily_checkins').update({'mood': mood,
        if (c.title.isNotEmpty) 'message': c.title}).eq('id', existing.first['id']);
    }
    return VoiceReply(ar
      ? (mood >= 4 ? 'جميل! سجلت شعورك لليوم وشاركته.' : 'سجلت شعورك لليوم. أتمنى أن يتحسن يومك.')
      : (mood >= 4 ? 'Love that. I saved how you feel today and shared it.'
        : 'I saved how you feel today. I hope the day gets kinder.'));
  }

  static Future<VoiceReply> _gesture(SupabaseClient db, String s, VoiceCommand c, bool ar) async {
    final people = await SpacePeople.load();
    final partner = people?.partnerId;
    if (partner == null) return VoiceReply(ar ? 'لا يوجد شريك متصل بعد.' : 'Your partner isn’t connected yet.');
    final message = gestureMessageFor(c.target) ?? 'Thinking of you.';
    await db.from('partner_gestures').insert({'space_id': s, 'recipient_id': partner,
      'kind': c.target, 'message': message});
    final name = people?.partnerName ?? (ar ? 'شريكك' : 'your partner');
    return VoiceReply(ar ? 'أرسلت ${c.title} إلى $name.' : 'Sent ${c.title} to $name.');
  }

  static Future<String> _dayText(SupabaseClient db, String s, DateTime day, bool ar) async {
    final d = CalendarRules.sqlDate(day);
    final start = DateTime(day.year, day.month, day.day);
    final parts = <String>[];
    final events = await db.from('space_events').select('title,starts_at').eq('space_id', s)
      .eq('event_date', d).isFilter('archived_at', null);
    for (final e in events) {
      final at = DateTime.tryParse(e['starts_at']?.toString() ?? '')?.toLocal();
      parts.add(at == null ? '${e['title']}' : ar ? '${e['title']} الساعة ${_time(at, ar)}' : '${e['title']} at ${_time(at, ar)}');
    }
    final reminders = await db.from('reminders').select('title,due_at').eq('space_id', s)
      .isFilter('archived_at', null).gte('due_at', start.toUtc().toIso8601String())
      .lt('due_at', start.add(const Duration(days: 1)).toUtc().toIso8601String()).order('due_at');
    for (final r in reminders) {
      final at = DateTime.tryParse(r['due_at']?.toString() ?? '')?.toLocal();
      parts.add(ar ? 'تذكير ${r['title']}${at == null ? '' : ' الساعة ${_time(at, ar)}'}'
        : 'reminder: ${r['title']}${at == null ? '' : ' at ${_time(at, ar)}'}');
    }
    final tasks = await db.from('tasks').select('title').eq('space_id', s).eq('status', 'open').eq('target_date', d);
    for (final t in tasks) { parts.add(ar ? 'قائمة ${t['title']} مستحقة' : '${t['title']} is due'); }
    final label = _day(day, ar);
    if (parts.isEmpty) return ar ? '$label لا شيء في الجدول.' : '${_cap(label)}: nothing planned.';
    return ar ? '$label: ${_join(parts, ar)}' : '${_cap(label)}: ${_join(parts, ar)}';
  }

  static Future<String> _weekText(SupabaseClient db, String s, bool ar) async {
    final now = DateTime.now();
    final from = CalendarRules.sqlDate(now), to = CalendarRules.sqlDate(now.add(const Duration(days: 7)));
    final events = await db.from('space_events').select('title,event_date').eq('space_id', s)
      .gte('event_date', from).lte('event_date', to).isFilter('archived_at', null).order('event_date');
    if (events.isEmpty) return ar ? 'لا شيء في الجدول هذا الأسبوع.' : 'Nothing on the calendar this week.';
    final parts = [
      for (final e in events) ar ? '${_day(DateTime.parse(e['event_date'].toString()), ar)} ${e['title']}'
        : '${e['title']} ${_day(DateTime.parse(e['event_date'].toString()), ar)}',
    ];
    return ar ? 'هذا الأسبوع: ${_join(parts, ar)}' : 'This week: ${_join(parts, ar)}';
  }

  static Future<String> _remindersText(SupabaseClient db, String s, bool ar) async {
    final query=OneSpaceEnv.isProduction
      ? db.from('reminders').select('title,due_at').eq('space_id',s)
      : db.from('reminders').select('title,due_at');
    final rows=await query
      .isFilter('archived_at', null).gte('due_at', DateTime.now().toUtc().toIso8601String())
      .order('due_at').limit(6);
    if (rows.isEmpty) return ar ? 'لا توجد تذكيرات قادمة.' : 'You have no upcoming reminders.';
    final parts = <String>[];
    for (final r in rows) {
      final at = DateTime.tryParse(r['due_at']?.toString() ?? '')?.toLocal();
      parts.add(at == null ? '${r['title']}' : ar ? '${r['title']} ${_day(at, ar)} الساعة ${_time(at, ar)}'
        : '${r['title']}, ${_day(at, ar)} at ${_time(at, ar)}');
    }
    return ar ? 'تذكيراتك القادمة: ${_join(parts, ar)}' : 'Your next reminders: ${_join(parts, ar)}';
  }

  static Future<String> _letterText(SupabaseClient db, String s, bool ar) async {
    final me = db.auth.currentUser!.id;
    final letter = await db.from('couple_letters').select('title,body,sent_at,author_id').eq('space_id', s)
      .neq('author_id', me).not('sent_at', 'is', null).order('sent_at', ascending: false).limit(1).maybeSingle();
    if (letter == null) return ar ? 'لا توجد رسائل من شريكك بعد.' : 'There are no letters from your partner yet.';
    final at = DateTime.tryParse(letter['sent_at']?.toString() ?? '')?.toLocal();
    return ar ? 'رسالة ${at == null ? '' : _day(at, ar)}، بعنوان ${letter['title']}. ${letter['body'] ?? ''}'
      : 'Letter from ${at == null ? 'recently' : _day(at, ar)}: ${letter['title']}. ${letter['body'] ?? ''}';
  }

  static Future<String> _activityText(SupabaseClient db, String s, String name, bool ar) async {
    final query=OneSpaceEnv.isProduction
      ?db.from('activities').select('id,title,body').eq('space_id',s)
      :db.from('activities').select('id,title,body');
    final rows=List<Map<String,dynamic>>.from(await query
      .isFilter('archived_at',null));
    final a = VoiceCommandRules.best(rows, (x) => x['title'].toString(), name);
    if (a == null) return ar ? 'لم أجد نشاط $name.' : 'I couldn’t find the $name activity.';
    final parts = await db.from('activity_components').select('label,kind,payload').eq('activity_id', a['id'])
      .inFilter('kind', ['step', 'option']).isFilter('archived_at', null).limit(20);
    final open = [for (final x in parts) if (x['kind'] == 'step' && (x['payload'] as Map?)?['status'] != 'done') x['label'].toString()];
    final options = [for (final x in parts) if (x['kind'] == 'option') x['label'].toString()];
    final b = StringBuffer('${a['title']}. ');
    if ((a['body'] ?? '').toString().trim().isNotEmpty) b.write('${a['body']} ');
    if (options.isNotEmpty) b.write(ar ? 'الخيارات: ${_join(options, ar)} ' : 'Options: ${_join(options, ar)} ');
    if (open.isNotEmpty) b.write(ar ? 'الخطوات المتبقية: ${_join(open, ar)}' : 'Steps left: ${_join(open, ar)}');
    return b.toString();
  }

  static Future<String> _tripText(SupabaseClient db, String s, String name, bool ar, {bool short = false}) async {
    final today = CalendarRules.sqlDate(DateTime.now());
    final rows = List<Map<String, dynamic>>.from(await db.from('shared_trips')
      .select('id,title,destination,start_on,notes,status').eq('space_id', s).isFilter('archived_at', null)
      .neq('status', 'cancelled').order('start_on'));
    final trip = name.isEmpty
      ? rows.where((t) => (t['start_on']?.toString() ?? '').compareTo(today) >= 0).firstOrNull
      : VoiceCommandRules.best(rows, (x) => '${x['title']} ${x['destination'] ?? ''}', name);
    if (trip == null) return ar ? 'لا توجد رحلة قادمة مسجلة.' : 'There is no upcoming trip yet.';
    final start = DateTime.tryParse(trip['start_on']?.toString() ?? '');
    final now = DateTime.now();
    final days = start == null ? null
      : DateTime(start.year, start.month, start.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    final b = StringBuffer(ar ? 'رحلة ${trip['title']}' : '${trip['title']}');
    if ((trip['destination'] ?? '').toString().isNotEmpty) b.write(ar ? ' إلى ${trip['destination']}' : ' to ${trip['destination']}');
    if (start != null) {
      b.write(ar ? '، ${_day(start, ar)}' : ', ${_day(start, ar)}');
      if (days != null && days > 1) b.write(ar ? '، بعد $days يومًا' : ', in $days days');
    }
    b.write('. ');
    if (short) return b.toString();
    if ((trip['notes'] ?? '').toString().trim().isNotEmpty) b.write('${trip['notes']} ');
    final items = await db.from('trip_items').select('title,local_date').eq('trip_id', trip['id'])
      .isFilter('archived_at', null).order('local_date').limit(8);
    if (items.isNotEmpty) {
      b.write(ar ? 'البرنامج: ' : 'Plan: ');
      b.write(_join([
        for (final i in items) '${i['title']}${i['local_date'] == null ? '' : ' ${_day(DateTime.parse(i['local_date'].toString()), ar)}'}',
      ], ar));
    }
    return b.toString();
  }

  static Future<String> _reunionText(SupabaseClient db, String s, bool ar) async {
    final row = await db.from('spaces').select('next_meet_on,relationship_mode').eq('id', s).maybeSingle();
    if (row?['relationship_mode'] == 'together') return ar ? 'أنتما معًا الآن.' : 'You’re together now.';
    final next = DateTime.tryParse(row?['next_meet_on']?.toString() ?? '');
    if (next == null) return ar ? 'لم تحددا موعد اللقاء القادم بعد.' : 'You haven’t set your next reunion yet.';
    final now = DateTime.now();
    final days = DateTime(next.year, next.month, next.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days <= 0) return ar ? 'لقاؤكما اليوم!' : 'You see each other today!';
    return ar ? 'تلتقيان ${_day(next, ar)}، بعد $days يومًا.' : 'You see each other ${_day(next, ar)}, in $days days.';
  }

  static Future<String> _countdownText(SupabaseClient db, String s, String what, bool ar) async {
    final today = DateTime.now();
    final day0 = DateTime(today.year, today.month, today.day);
    final candidates = <({String title, DateTime date})>[];
    final occasions = await db.from('occasion_plans').select('title,honoree_name,occasion_on,annual')
      .eq('space_id', s).isFilter('archived_at', null);
    for (final o in occasions) {
      final d = OccasionRules.nextDate(original: DateTime.parse(o['occasion_on'].toString()),
        annual: o['annual'] == true, today: today);
      if (d != null) candidates.add((title: '${o['title']} ${o['honoree_name'] ?? ''}'.trim(), date: d));
    }
    final events = await db.from('space_events').select('title,event_date,recurrence').eq('space_id', s)
      .isFilter('archived_at', null);
    for (final e in events) {
      final d = OccasionRules.nextDate(original: DateTime.parse(e['event_date'].toString()),
        annual: e['recurrence'] == 'yearly', today: today);
      if (d != null) candidates.add((title: e['title'].toString(), date: d));
    }
    final trips = await db.from('shared_trips').select('title,destination,start_on').eq('space_id', s)
      .isFilter('archived_at', null);
    for (final t in trips) {
      final d = DateTime.tryParse(t['start_on']?.toString() ?? '');
      if (d != null && !d.isBefore(day0)) {
        candidates.add((title: '${t['title']} ${t['destination'] ?? ''}'.trim(), date: d));
      }
    }
    final hit = VoiceCommandRules.best(candidates, (x) => x.title, what);
    if (hit == null) return ar ? 'لم أجد $what في التقويم أو المناسبات.' : 'I couldn’t find $what on the calendar or in occasions.';
    final days = DateTime(hit.date.year, hit.date.month, hit.date.day).difference(day0).inDays;
    if (days == 0) return ar ? '${hit.title} اليوم!' : '${hit.title} is today!';
    return ar ? 'باقي $days يومًا على ${hit.title}، ${_day(hit.date, ar)}.'
      : '$days days until ${hit.title}, ${_day(hit.date, ar)}.';
  }
}
