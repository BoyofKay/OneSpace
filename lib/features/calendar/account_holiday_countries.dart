import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onespace/l10n/phrases.dart';
import 'holiday_calendar_service.dart';

/// QA: each person chooses their own holiday countries (any country, by
/// search). While paired, the calendar shows both people's countries.
class AccountHolidayCountries {
  const AccountHolidayCountries._();

  /// Mine and, while paired, my partner's (the server only returns those).
  static Future<Set<String>> active() async {
    final db = Supabase.instance.client;
    await ensureDefault();
    final rows = await db.from('account_holiday_countries').select('country_code');
    return {for (final r in rows) r['country_code'].toString()};
  }

  static Future<Set<String>> mine() async {
    final db = Supabase.instance.client;
    final me = db.auth.currentUser?.id;
    if (me == null) return {};
    final rows = await db.from('account_holiday_countries').select('country_code').eq('user_id', me);
    return {for (final r in rows) r['country_code'].toString()};
  }

  /// The first time, the country of my time zone is turned on for me.
  static Future<void> ensureDefault() async {
    final db = Supabase.instance.client;
    final me = db.auth.currentUser?.id;
    if (me == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'qa_holiday_default_done_$me';
      if (prefs.getBool(key) == true) return;
      if ((await mine()).isEmpty) {
        final p = await db.from('profiles').select('time_zone').eq('id', me).maybeSingle();
        final code = HolidayCatalog.countryForTimeZone(p?['time_zone']?.toString());
        if (code != null) {
          await db.from('account_holiday_countries').insert({'user_id': me, 'country_code': code});
        }
      }
      await prefs.setBool(key, true);
    } catch (_) {/* holidays are optional */}
  }
}

/// Settings › Regional holidays (QA).
class AccountHolidayCountriesPanel extends StatefulWidget {
  const AccountHolidayCountriesPanel({super.key});
  @override
  State<AccountHolidayCountriesPanel> createState() => _AccountHolidayCountriesPanelState();
}

class _AccountHolidayCountriesPanelState extends State<AccountHolidayCountriesPanel> {
  final db = Supabase.instance.client;
  final search = TextEditingController();
  Set<String> mine = {}, partner = {};
  bool loading = true, busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      await AccountHolidayCountries.ensureDefault();
      final me = db.auth.currentUser?.id;
      final rows = await db.from('account_holiday_countries').select('user_id,country_code');
      if (!mounted) return;
      setState(() {
        mine = {for (final r in rows) if (r['user_id'] == me) r['country_code'].toString()};
        partner = {for (final r in rows) if (r['user_id'] != me) r['country_code'].toString()};
        loading = false;
        error = null;
      });
    } catch (_) {
      if (mounted) setState(() { loading = false; error = 'Could not load your holiday countries.'; });
    }
  }

  Future<void> toggle(String code, bool on) async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      final me = db.auth.currentUser!.id;
      if (on) {
        await db.from('account_holiday_countries').insert({'user_id': me, 'country_code': code});
        // Check now that holidays can be fetched for it.
        final result = await HolidayCalendarService().forYearDetailed(DateTime.now().year, {code});
        if (result.unavailableCountries.isNotEmpty && mounted) {
          setState(() => error = HolidayMessages.unavailable([code]));
        }
      } else {
        await db.from('account_holiday_countries').delete().eq('user_id', me).eq('country_code', code);
      }
      await load();
    } on PostgrestException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not update your holiday countries.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = search.text.trim().toLowerCase();
    final all = HolidayCatalog.allCountries.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final shown = q.isEmpty
      ? all.where((e) => mine.contains(e.key)).toList()
      : all.where((e) => e.value.toLowerCase().contains(q) || e.key.toLowerCase() == q).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tt('Choose the countries whose public holidays you want to see. '
        'Your partner chooses their own, and while you are paired the calendar shows both.')),
      const SizedBox(height: 12),
      TextField(
        key: const Key('qaHolidayCountrySearch'),
        controller: search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(prefixIcon: const Icon(Icons.search),
          labelText: tt('Search for a country'), border: const OutlineInputBorder()),
      ),
      const SizedBox(height: 8),
      if (loading) const LinearProgressIndicator()
      else ...[
        if (q.isEmpty) Padding(padding: const EdgeInsets.only(top: 6),
          child: Text(tt(mine.isEmpty ? 'You have not chosen any country yet.' : 'Your countries'),
            style: theme.textTheme.titleSmall)),
        for (final e in shown) CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tt(e.value)),
          subtitle: Text(tt(HolidayCatalog.builtIn.contains(e.key)
            ? 'Built in: national days, Ramadan and the Eids (expected dates)'
            : 'National public holidays · from Nager.Date, when available')),
          value: mine.contains(e.key),
          onChanged: busy ? null : (v) => toggle(e.key, v ?? false)),
        if (q.isNotEmpty && shown.isEmpty) Text(tt('No country matches.')),
        if (partner.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(tt('Your partner\'s countries'), style: theme.textTheme.titleSmall),
          Text(partner.map((c) => tt(HolidayCatalog.label(c))).join(' · ')),
        ],
      ],
      if (error != null) Padding(padding: const EdgeInsets.only(top: 10),
        child: Text(tt(error!), style: TextStyle(color: theme.colorScheme.error))),
      const SizedBox(height: 12),
      Text(tt('Islamic dates follow the Umm al-Qura calendar and can move by a day after the moon sighting.'),
        style: theme.textTheme.bodySmall),
    ]);
  }
}

class HolidayMessages {
  const HolidayMessages._();
  static String unavailable(Iterable<String> codes) =>
    'Holidays for ${codes.map(HolidayCatalog.label).join(', ')} could not be loaded right now. '
    'You can add the days that matter to you in Settings › Birthdays, anniversary & special dates.';
}
