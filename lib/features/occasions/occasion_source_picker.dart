import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onespace/l10n/phrases.dart';

import '../calendar/holiday_calendar_service.dart';
import '../calendar/holiday_sources_panel.dart';
import '../calendar/calendar_rules.dart';
import 'occasion_rules.dart';
import '../settings/special_dates.dart';
import '../../core/form_kit.dart';

/// R68: what an occasion is planned for, picked from what the space already
/// keeps: the regional holidays it follows and the special dates (yearly
/// events) in the calendar.
class OccasionSource {
  const OccasionSource({required this.kind, required this.ref, required this.title,
    required this.date, required this.occasionKind, this.detail = ''});
  final String kind; // 'special' | 'holiday' | 'calendar'
  final String ref;
  final String title, occasionKind, detail;
  final DateTime date;
}

class OccasionSourceRules {
  const OccasionSourceRules._();

  /// Birthday / anniversary / holiday / celebration from the words in a title.
  static String kindFor(String title, {bool holiday = false}) {
    final t = title.toLowerCase();
    if (t.contains('birthday') || t.contains('ميلاد')) return 'birthday';
    if (t.contains('anniversary') || t.contains('ذكرى')) return 'anniversary';
    if (holiday || t.contains('eid') || t.contains('عيد') || t.contains('christmas') ||
        t.contains('ramadan') || t.contains('رمضان') || t.contains('new year')) {
      return 'holiday';
    }
    return 'celebration';
  }

  /// A stable reference for a holiday ("SA:2026-12-02:National Day").
  static String holidayRef(String country, DateTime day, String name) {
    final ref = '$country:${CalendarRules.sqlDate(day)}:$name';
    return ref.length > 200 ? ref.substring(0, 200) : ref;
  }
}

/// Opens the picker. Returns null when closed without choosing.
Future<OccasionSource?> pickOccasionSource(BuildContext context, String spaceId) =>
  showModalBottomSheet<OccasionSource>(context: context, isScrollControlled: true,
    showDragHandle: true, builder: (_) => _SourceSheet(spaceId: spaceId));

class _SourceSheet extends StatefulWidget {
  const _SourceSheet({required this.spaceId});
  final String spaceId;
  @override
  State<_SourceSheet> createState() => _SourceSheetState();
}

class _SourceSheetState extends State<_SourceSheet> {
  final db = Supabase.instance.client;
  final service = HolidayCalendarService();
  List<OccasionSource> holidays = [], special = [], saved = [];
  bool loading = true;
  String? note;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    service.close();
    super.dispose();
  }

  Future<void> load() async {
    final today = CalendarRules.day(DateTime.now());
    final horizon = today.add(const Duration(days: 400));
    // R69: the dates saved in Settings › Birthdays, anniversary & special dates.
    try {
      final people = await SpacePeople.load();
      String? mine;
      final me = db.auth.currentUser?.id;
      if (me != null) {
        final row = await db.from('profiles').select('display_name').eq('id', me).maybeSingle();
        mine = (row?['display_name'] ?? '').toString().trim().split(RegExp(r'\s+')).first;
      }
      String nameOf(String? id) => id != null && id == people?.me
        ? (mine ?? '') : (people?.partnerName ?? 'Partner');
      saved = [
        for (final d in await loadSpecialDates(widget.spaceId))
          OccasionSource(kind: 'special', ref: d.id, title: SpecialDateRules.label(d, nameOf),
            date: SpecialDateRules.nextOn(d, today), occasionKind: SpecialDateRules.occasionKind(d),
            detail: SpecialDateRules.milestone(d, SpecialDateRules.nextOn(d, today)) ?? ''),
      ]..sort((a, b) => a.date.compareTo(b.date));
    } catch (_) {}
    try {
      final events = await db.from('space_events')
        .select('id,title,event_date,starts_at,recurrence,repeat_rule')
        .eq('space_id', widget.spaceId).isFilter('archived_at', null).limit(400);
      final found = <OccasionSource>[];
      for (final e in events) {
        final rule = e['repeat_rule'];
        final yearly = e['recurrence'] == 'yearly' || (rule is Map && rule['freq'] == 'yearly');
        if (!yearly) continue;
        final start = DateTime.tryParse((e['event_date'] ?? e['starts_at'] ?? '').toString());
        if (start == null) continue;
        final next = OccasionRules.nextDate(original: start, annual: true, today: today);
        if (next == null) continue;
        final title = (e['title'] ?? '').toString();
        if (saved.any((x) => x.title.toLowerCase() == title.toLowerCase())) continue;
        found.add(OccasionSource(kind: 'calendar', ref: e['id'].toString(), title: title,
          date: next, occasionKind: OccasionSourceRules.kindFor(title)));
      }
      found.sort((a, b) => a.date.compareTo(b.date));
      special = found;
    } catch (_) {
      note = 'Special dates could not load.';
    }
    try {
      await HolidayDefaults.ensure(widget.spaceId);
      final sources = await db.from('space_holiday_sources')
        .select('country_code,enabled').eq('space_id', widget.spaceId);
      final codes = {for (final s in sources) if (s['enabled'] == true) s['country_code'].toString()};
      if (codes.isEmpty) {
        note ??= 'Choose regional holidays in Settings to see them here.';
      } else {
        final days = [
          ...await service.forYear(today.year, codes),
          ...await service.forYear(today.year + 1, codes),
        ];
        holidays = [
          for (final d in days)
            if (!d.date.isBefore(today) && d.date.isBefore(horizon))
              OccasionSource(kind: 'holiday', ref: OccasionSourceRules.holidayRef(d.country, d.date, d.name),
                title: d.name, date: d.date, occasionKind: 'holiday',
                detail: HolidayCatalog.countryNames[d.country] ?? d.country),
        ]..sort((a, b) => a.date.compareTo(b.date));
      }
    } catch (_) {
      note ??= 'Holidays could not load. You can still type the occasion.';
    }
    if (mounted) setState(() => loading = false);
  }

  Widget tile(OccasionSource s) {
    final loc = MaterialLocalizations.of(context);
    final days = OccasionRules.daysUntil(s.date, DateTime.now()) ?? 0;
    return ListTile(
      leading: CircleAvatar(child: Icon(switch (s.occasionKind) {
        'birthday' => Icons.cake_outlined,
        'anniversary' => Icons.favorite_border,
        'holiday' => Icons.celebration_outlined,
        _ => Icons.star_outline,
      })),
      title: Text(tt(s.title)),
      subtitle: Text([loc.formatMediumDate(s.date), tt(days == 0 ? 'Today' : 'In $days days'),
        if (s.detail.isNotEmpty) tt(s.detail)].join(' · ')),
      onTap: () => Navigator.pop(context, s));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(height: MediaQuery.sizeOf(context).height * .8, child: loading
      ? const Center(child: CircularProgressIndicator())
      : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(tt('What are we planning for?'), style: theme.textTheme.titleLarge)),
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(tt('Pick a special date or a holiday, or close this to type your own.'),
              style: theme.textTheme.bodySmall)),
          if (note != null) Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(tt(note!), style: theme.textTheme.bodySmall)),
          if (saved.isNotEmpty || special.isNotEmpty) ...[
            Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(tt('Special dates'), style: theme.textTheme.titleSmall)),
            for (final s in saved) tile(s),
            for (final s in special) tile(s),
          ],
          if (holidays.isNotEmpty) ...[
            Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(tt('Holidays'), style: theme.textTheme.titleSmall)),
            for (final s in holidays.take(40)) tile(s),
          ],
          if (saved.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(tt('Tip: save birthdays and your anniversary in Settings › Birthdays, anniversary & special dates, and they appear here.'),
              style: theme.textTheme.bodySmall)),
        ]));
  }
}
