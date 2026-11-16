import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:onespace/l10n/phrases.dart';
import '../features/calendar/calendar_rules.dart';
import '../features/settings/special_dates.dart';
import 'current_space_cache.dart';
import 'form_kit.dart';

/// One item for the phone's calendar. All-day items use [date] (+ [days]);
/// timed items use [start] and [end] in local time.
class PhoneCalendarItem {
  const PhoneCalendarItem({required this.key, required this.title, this.notes = '',
    this.location = '', this.date, this.days = 1, this.start, this.end});
  final String key, title, notes, location;
  final DateTime? date, start, end;
  final int days;

  bool get allDay => start == null;

  Map<String, Object?> toChannel() => {
    'key': key, 'title': title, 'notes': notes, 'location': location, 'allDay': allDay,
    if (allDay) 'startDate': CalendarRules.sqlDate(date!),
    if (allDay) 'endDate': CalendarRules.sqlDate(DateTime(date!.year, date!.month, date!.day + days)),
    if (!allDay) 'startMs': start!.millisecondsSinceEpoch,
    if (!allDay) 'endMs': (end ?? start!.add(const Duration(hours: 1))).millisecondsSinceEpoch,
  };
}

/// R74 (Ahmed): one way only — OneSpace → the phone's own calendar
/// (Google / Samsung / iPhone). A separate "OneSpace" calendar is replaced on
/// each sync, so nothing in the person's other calendars is ever touched or read.
class PhoneCalendarRules {
  const PhoneCalendarRules._();

  /// What goes into the phone calendar from 30 days ago to a year ahead.
  static List<PhoneCalendarItem> build({
    required List<Map<String, dynamic>> events,
    required List<Map<String, dynamic>> trips,
    required List<Map<String, dynamic>> occasions,
    required List<SpecialDate> specials,
    required String Function(String? personId) nameOf,
    required DateTime today,
  }) {
    final from = DateTime(today.year, today.month, today.day - 30);
    final to = DateTime(today.year + 1, today.month, today.day);
    final out = <PhoneCalendarItem>[];
    bool inWindow(DateTime d) => !d.isBefore(from) && !d.isAfter(to);

    for (final e in events) {
      final title = (e['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      final start = CalendarRules.eventLocalStart(e['starts_at']);
      final end = CalendarRules.eventLocalStart(e['ends_at']);
      final original = start != null ? CalendarRules.day(start)
        : DateTime.tryParse((e['event_date'] ?? '').toString());
      if (original == null) continue;
      final rule = e['repeat_rule'];
      final recurrence = (e['recurrence'] ?? 'none').toString();
      final repeats = rule is Map || recurrence == 'yearly';
      final dates = <DateTime>[];
      if (!repeats) {
        if (inWindow(original)) dates.add(original);
      } else {
        for (var d = original.isAfter(from) ? original : from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
          if (CalendarRules.occursOn(original: original, recurrence: recurrence, selected: d, rule: rule)) dates.add(d);
          if (dates.length >= 400) break;
        }
      }
      for (final d in dates) {
        final key = 'event:${e['id']}:${CalendarRules.sqlDate(d)}';
        if (start == null) {
          out.add(PhoneCalendarItem(key: key, title: title, notes: (e['details'] ?? '').toString(),
            location: (e['location'] ?? '').toString(), date: d));
        } else {
          final s = DateTime(d.year, d.month, d.day, start.hour, start.minute);
          final length = end != null && end.isAfter(start) ? end.difference(start) : const Duration(hours: 1);
          out.add(PhoneCalendarItem(key: key, title: title, notes: (e['details'] ?? '').toString(),
            location: (e['location'] ?? '').toString(), start: s, end: s.add(length)));
        }
      }
    }

    for (final t in trips) {
      final start = DateTime.tryParse((t['start_on'] ?? '').toString());
      if (start == null) continue;
      final end = DateTime.tryParse((t['end_on'] ?? '').toString()) ?? start;
      final days = CalendarRules.calendarDaysUntil(start, end) + 1;
      if (end.isBefore(from) || start.isAfter(to) || days < 1 || days > 120) continue;
      final where = (t['destination'] ?? '').toString();
      out.add(PhoneCalendarItem(key: 'trip:${t['id']}',
        title: '✈ ${(t['title'] ?? '').toString().trim().isEmpty ? where : t['title']}',
        location: where, date: start, days: days));
    }

    for (final o in occasions) {
      final on = DateTime.tryParse((o['occasion_on'] ?? '').toString());
      if (on == null) continue;
      final annual = o['annual'] == true;
      for (var y = from.year; y <= to.year; y++) {
        final d = annual ? DateTime(y, on.month, on.day) : on;
        if (inWindow(d)) {
          out.add(PhoneCalendarItem(key: 'occasion:${o['id']}:${d.year}', title: '🎁 ${o['title']}', date: d));
        }
        if (!annual) break;
      }
    }

    for (final s in specials) {
      for (var y = from.year; y <= to.year; y++) {
        final last = DateTime(y, s.month + 1, 0).day;
        final d = DateTime(y, s.month, s.day > last ? last : s.day);
        if (!inWindow(d)) continue;
        final label = tt(SpecialDateRules.label(s, nameOf));
        final turns = SpecialDateRules.milestone(s, d);
        out.add(PhoneCalendarItem(key: 'special:${s.id}:$y',
          title: '❤ ${turns == null ? label : '$label · ${tt(turns)}'}', date: d));
      }
    }
    // Occasions started from a special date would appear twice: keep one.
    final seen = <String>{};
    return [for (final i in out) if (seen.add('${i.title}|${i.date ?? i.start}')) i];
  }
}

class PhoneCalendarSync {
  PhoneCalendarSync._();
  static const _channel = MethodChannel('onespace/phone_calendar');
  static const _key = 'phone_calendar_sync_v1';
  static DateTime? _lastSync;
  static Future<int?>? _running;

  static Future<bool> isOn() async {
    try { return await SharedPreferencesAsync().getBool(_key) ?? false; } catch (_) { return false; }
  }

  /// Asks the phone for calendar permission, then fills the OneSpace calendar.
  /// Returns the number of items written, or null when permission was refused.
  static Future<int?> turnOn() async {
    final granted = await _channel.invokeMethod<bool>('requestAccess') ?? false;
    if (!granted) return null;
    await SharedPreferencesAsync().setBool(_key, true);
    return syncNow(force: true);
  }

  static Future<void> turnOff() async {
    await SharedPreferencesAsync().setBool(_key, false);
    try { await _channel.invokeMethod<void>('removeCalendar'); } catch (_) {}
  }

  /// Called when the app opens or comes back; at most every 10 minutes.
  static Future<int?> syncNow({bool force = false}) {
    final running = _running;
    if (running != null) return running;
    final f = _sync(force).whenComplete(() => _running = null);
    _running = f;
    return f;
  }

  static Future<int?> _sync(bool force) async {
    try {
      if (!await isOn()) return null;
      final last = _lastSync;
      if (!force && last != null && DateTime.now().difference(last) < const Duration(minutes: 10)) return null;
      final db = Supabase.instance.client;
      final me = db.auth.currentUser?.id;
      final space = await CurrentSpaceCache.instance.get();
      if (me == null || space == null) return null;
      final results = await Future.wait([
        db.from('space_events').select('id,title,details,event_date,starts_at,ends_at,location,recurrence,repeat_rule')
          .eq('space_id', space).isFilter('archived_at', null),
        db.from('shared_trips').select('id,title,destination,start_on,end_on,status')
          .eq('space_id', space).isFilter('archived_at', null).neq('status', 'cancelled'),
        db.from('occasion_plans').select('id,title,occasion_on,annual,source_kind')
          .eq('space_id', space).isFilter('archived_at', null),
      ]);
      final people = await SpacePeople.load();
      final specials = await loadSpecialDates(space);
      final items = PhoneCalendarRules.build(
        events: List<Map<String, dynamic>>.from(results[0]),
        trips: List<Map<String, dynamic>>.from(results[1]),
        // Occasions that came from a special date are already written as that date.
        occasions: [for (final o in results[2]) if (o['source_kind'] != 'special') Map<String, dynamic>.from(o)],
        specials: specials,
        nameOf: (id) => id == null || id == me ? '' : (id == people?.partnerId ? people!.partnerName : ''),
        today: DateTime.now());
      final written = await _channel.invokeMethod<int>('replaceAll', {
        'name': 'OneSpace', 'items': [for (final i in items) i.toChannel()]});
      _lastSync = DateTime.now();
      return written;
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') await SharedPreferencesAsync().setBool(_key, false);
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// The switch in Settings.
class PhoneCalendarSettingsScreen extends StatefulWidget {
  const PhoneCalendarSettingsScreen({super.key});
  @override
  State<PhoneCalendarSettingsScreen> createState() => _PhoneCalendarSettingsScreenState();
}

class _PhoneCalendarSettingsScreenState extends State<PhoneCalendarSettingsScreen> {
  bool? on;
  bool busy = false;
  String? note;

  @override
  void initState() {
    super.initState();
    PhoneCalendarSync.isOn().then((v) { if (mounted) setState(() => on = v); });
  }

  Future<void> _set(bool value) async {
    setState(() { busy = true; note = null; });
    try {
      if (value) {
        final n = await PhoneCalendarSync.turnOn();
        if (!mounted) return;
        setState(() {
          on = n != null;
          note = n == null
            ? tt('OneSpace needs calendar permission. You can allow it in your phone settings.')
            : tt('Done — {} items are in the OneSpace calendar on this phone.').replaceFirst('{}', '$n');
        });
      } else {
        await PhoneCalendarSync.turnOff();
        if (mounted) setState(() { on = false; note = tt('The OneSpace calendar was removed from this phone.'); });
      }
    } catch (_) {
      if (mounted) setState(() => note = tt('Could not reach the phone calendar. Try again.'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tt('Show in my phone calendar'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(tt('Your shared events, trips, occasions and special dates appear in a separate "OneSpace" calendar '
          'in your phone\'s calendar app (Google, Samsung or iPhone). It updates when you open OneSpace.'),
          style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text(tt('One way only: OneSpace never reads your other calendars. Change things in OneSpace — edits made in '
          'the phone calendar are replaced on the next update.'), style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        Card(elevation: 0, child: SwitchListTile(
          secondary: const Icon(Icons.event_available_outlined),
          title: Text(tt('Show in my phone calendar')),
          subtitle: Text(tt('This phone only. Your partner chooses on theirs.')),
          value: on ?? false,
          onChanged: on == null || busy ? null : _set)),
        if (on == true) TextButton.icon(
          icon: const Icon(Icons.sync), label: Text(tt('Update now')),
          onPressed: busy ? null : () async {
            setState(() => busy = true);
            final n = await PhoneCalendarSync.syncNow(force: true);
            if (mounted) {
              setState(() { busy = false; note = n == null ? tt('Could not reach the phone calendar. Try again.')
                : tt('Done — {} items are in the OneSpace calendar on this phone.').replaceFirst('{}', '$n'); });
            }
          }),
        if (busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
        if (note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(note!)),
      ]),
    );
  }
}
