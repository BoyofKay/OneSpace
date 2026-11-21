import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onespace/l10n/phrases.dart';

import '../../core/current_space_cache.dart';
import '../counters/counter_sources.dart';
import '../counters/counter_source_actions.dart';
import '../../core/form_kit.dart';
import '../../core/app_env.dart';

/// R69: one saved date in Settings › Birthdays, anniversary & special dates.
class SpecialDate {
  const SpecialDate({required this.id, required this.kind, this.personId, this.title = '',
    required this.month, required this.day, this.year});
  final String id, kind, title;
  final String? personId;
  final int month, day;
  final int? year;

  factory SpecialDate.fromRow(Map<String, dynamic> r) => SpecialDate(
    id: r['id'].toString(), kind: r['kind'].toString(), personId: r['person_id']?.toString(),
    title: (r['title'] ?? '').toString(), month: (r['month'] as num).toInt(),
    day: (r['day'] as num).toInt(), year: (r['year'] as num?)?.toInt());
}

class SpecialDateRules {
  const SpecialDateRules._();

  /// The next time it comes round (29 Feb falls on 28 Feb in other years).
  static DateTime nextOn(SpecialDate d, DateTime today) {
    final base = DateTime(today.year, today.month, today.day);
    for (var y = base.year; y <= base.year + 1; y++) {
      final last = DateTime(y, d.month + 1, 0).day;
      final date = DateTime(y, d.month, d.day > last ? last : d.day);
      if (!date.isBefore(base)) return date;
    }
    return DateTime(base.year + 1, d.month, d.day);
  }

  /// "Ahmed's birthday", "Our anniversary", or the title of your own date.
  static String label(SpecialDate d, String Function(String? personId) nameOf) => switch (d.kind) {
    'birthday' => nameOf(d.personId).isEmpty ? 'My birthday' : "${nameOf(d.personId)}'s birthday",
    'anniversary' => 'Our anniversary',
    _ => d.title,
  };

  /// "turns 41", "6 years" — when the year is known.
  static String? milestone(SpecialDate d, DateTime on) {
    final y = d.year;
    if (y == null || on.year <= y) return null;
    final n = on.year - y;
    return switch (d.kind) {
      'birthday' => 'turns $n',
      'anniversary' => '$n ${n == 1 ? 'year' : 'years'}',
      _ => '$n ${n == 1 ? 'year' : 'years'}',
    };
  }

  /// The occasion kind it starts.
  static String occasionKind(SpecialDate d) =>
    d.kind == 'birthday' ? 'birthday' : d.kind == 'anniversary' ? 'anniversary' : 'celebration';
}

/// Loads the space's saved special dates.
///
/// QA: birthdays belong to each person (account_birthdays). Mine always
/// shows to me; my partner's shows only when they chose to share it, and its
/// year only when they chose that too.
Future<List<SpecialDate>> loadSpecialDates(String spaceId) async {
  final db = Supabase.instance.client;
  final rows = await db.from('space_special_dates').select()
    .eq('space_id', spaceId).isFilter('archived_at', null).order('month').order('day');
  final list = [for (final r in rows) SpecialDate.fromRow(r)];
  if (OneSpaceEnv.isProduction) return list;
  list.removeWhere((d) => d.kind == 'birthday');
  list.addAll(await loadPersonBirthdays());
  return list;
}

/// QA: my own birthday and, when shared, my partner's.
Future<List<SpecialDate>> loadPersonBirthdays() async {
  final db = Supabase.instance.client;
  final me = db.auth.currentUser?.id;
  if (me == null) return const [];
  final out = <SpecialDate>[];
  try {
    final mine = await db.from('account_birthdays').select('month,day,year').eq('user_id', me).maybeSingle();
    if (mine != null) {
      out.add(SpecialDate.fromRow({...mine, 'id': 'birthday-$me', 'kind': 'birthday', 'person_id': me}));
    }
    final theirs = await db.rpc('partner_birthday');
    for (final r in (theirs as List? ?? const [])) {
      final row = Map<String, dynamic>.from(r as Map);
      out.add(SpecialDate.fromRow({...row, 'id': 'birthday-${row['person_id']}', 'kind': 'birthday'}));
    }
  } catch (_) {/* birthdays are optional */}
  return out;
}

/// R69 (Ahmed): a configuration, not another way into Occasions. Built-in
/// places wait to be filled — your birthday, your partner's birthday, your
/// anniversary — and you can add your own special dates. They show in the
/// calendar every year and can start an occasion plan.
class SpecialDatesScreen extends StatefulWidget {
  const SpecialDatesScreen({super.key});
  @override
  State<SpecialDatesScreen> createState() => _SpecialDatesScreenState();
}

class _SpecialDatesScreenState extends State<SpecialDatesScreen> {
  final db = Supabase.instance.client;
  String? space, error, myName;
  SpacePeople? people;
  List<SpecialDate> dates = [];
  bool loading = true, busy = false;
  // QA: my birthday's sharing choices (both default to off).
  bool shareBirthday = false, shareYear = false, hasBirthday = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      // Always re-check the partner here: a former partner's birthday slot
      // must disappear as soon as the pairing ends.
      SpacePeople.reset();
      final id = await CurrentSpaceCache.instance.get(refresh: true);
      final p = await SpacePeople.load();
      String? mine;
      final me = db.auth.currentUser?.id;
      if (me != null) {
        final row = await db.from('profiles').select('display_name').eq('id', me).maybeSingle();
        mine = (row?['display_name'] ?? '').toString().trim().split(RegExp(r'\s+')).first;
      }
      final list = id == null
        ? (OneSpaceEnv.isProduction ? <SpecialDate>[] : await loadPersonBirthdays())
        : await loadSpecialDates(id);
      if (!OneSpaceEnv.isProduction && me != null) {
        final row = await db.from('account_birthdays').select('share_with_partner,share_year')
          .eq('user_id', me).maybeSingle();
        hasBirthday = row != null;
        shareBirthday = row?['share_with_partner'] == true;
        shareYear = row?['share_year'] == true;
      }
      if (!mounted) return;
      setState(() {
        space = id; people = p; myName = (mine ?? '').isEmpty ? null : mine;
        dates = list; loading = false; error = null;
      });
    } catch (_) {
      if (mounted) setState(() { loading = false; error = 'Could not load your special dates.'; });
    }
  }

  SpecialDate? find(String kind, [String? person]) => dates.where((d) =>
    d.kind == kind && (person == null || d.personId == person)).firstOrNull;

  /// Asks for the date; the year is optional ("I know the year").
  Future<(int, int, int?)?> askDate({SpecialDate? current, required String title}) async {
    var knowYear = current == null || current.year != null;
    final initial = DateTime(current?.year ?? 1990, current?.month ?? DateTime.now().month, current?.day ?? DateTime.now().day);
    final picked = await showDatePicker(context: context, helpText: tt(title),
      initialDate: initial, firstDate: DateTime(1900), lastDate: DateTime(2100));
    if (picked == null || !mounted) return null;
    if (current == null) {
      final keep = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: Text(tt('Keep the year?')),
        content: Text(tt('With the year, OneSpace can say "turns 40" or "5 years". Without it, only the day and month are kept.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tt('Day and month only'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tt('Keep the year'))),
        ]));
      knowYear = keep ?? true;
    }
    return (picked.month, picked.day, knowYear ? picked.year : null);
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      await work();
      await load();
    } on PostgrestException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// QA: my birthday is mine, saved on my account.
  Future<void> setMyBirthday() async {
    final me = db.auth.currentUser?.id;
    if (me == null) return;
    final current = find('birthday', me);
    final picked = await askDate(current: current, title: 'Your birthday');
    if (picked == null) return;
    await run(() async {
      await db.from('account_birthdays').upsert({'user_id': me, 'month': picked.$1,
        'day': picked.$2, 'year': picked.$3});
    });
  }

  Future<void> setBirthdaySharing({bool? share, bool? year}) async {
    final me = db.auth.currentUser?.id;
    if (me == null) return;
    await run(() async {
      final saved = await db.from('account_birthdays').update({
        if (share != null) 'share_with_partner': share,
        if (share == false) 'share_year': false,
        if (year != null) 'share_year': year,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', me).select('share_with_partner,share_year').maybeSingle();
      // Show what the server really holds, so the switch never lies.
      if (saved == null) throw StateError('Your birthday sharing could not be saved. Try again.');
      if (mounted) setState(() {
        shareBirthday = saved['share_with_partner'] == true;
        shareYear = saved['share_year'] == true;
      });
    });
  }

  Future<void> setSlot(String kind, String title, {String? person}) async {
    final s = space;
    if (s == null) return;
    final current = find(kind, person);
    final picked = await askDate(current: current, title: title);
    if (picked == null) return;
    await run(() async {
      final values = {'month': picked.$1, 'day': picked.$2, 'year': picked.$3};
      if (current != null) {
        await db.from('space_special_dates').update(values).eq('id', current.id);
      } else {
        await db.from('space_special_dates').insert({...values, 'space_id': s, 'kind': kind,
          if (person != null) 'person_id': person});
      }
    });
  }

  Future<void> remove(SpecialDate d) async {
    if (!OneSpaceEnv.isProduction && d.kind == 'birthday') {
      await run(() async {
        await db.from('account_birthdays').delete().eq('user_id', db.auth.currentUser!.id);
      });
      return;
    }
    await run(() async {
      await db.from('space_special_dates').update({'archived_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', d.id);
    });
  }

  Future<void> editCustom([SpecialDate? d]) async {
    final s = space;
    if (s == null) return;
    final name = TextEditingController(text: d?.title ?? '');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(tt(d == null ? 'Add your own special date' : 'Rename')),
      content: TextField(controller: name, autofocus: true, maxLength: 120,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: tt('What is it?'),
          hintText: tt('First date, adoption day, moving-in day…'), border: const OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tt('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tt('Next'))),
      ]));
    final title = name.text.trim();
    name.dispose();
    if (ok != true || title.isEmpty || !mounted) return;
    final picked = await askDate(current: d, title: title);
    if (picked == null) return;
    await run(() async {
      final values = {'title': title, 'month': picked.$1, 'day': picked.$2, 'year': picked.$3};
      if (d != null) {
        await db.from('space_special_dates').update(values).eq('id', d.id);
      } else {
        await db.from('space_special_dates').insert({...values, 'space_id': s, 'kind': 'custom'});
      }
    });
  }

  String nameOf(String? id) {
    final p = people;
    if (id != null && id == p?.me) return myName ?? '';
    return p?.partnerName ?? 'Partner';
  }

  Widget slot({required IconData icon, required String title, required SpecialDate? value,
      required VoidCallback onTap, VoidCallback? onRemove, String? empty, bool readOnly = false}) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    String text = tt(empty ?? 'Tap to add');
    if (value != null) {
      final next = SpecialDateRules.nextOn(value, DateTime.now());
      final shown = value.year != null ? DateTime(value.year!, value.month, value.day) : next;
      final m = SpecialDateRules.milestone(value, next);
      text = (value.year != null ? loc.formatMediumDate(shown) : '${value.day} ${tt(OnespaceMonths.name(value.month))}') +
        (m == null ? '' : ' · ${tt('next:')} ${tt(m)}');
    }
    return Card(elevation: 0, child: ListTile(
      leading: CircleAvatar(backgroundColor: value == null ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.primaryContainer, child: Icon(icon)),
      title: Text(tt(title)),
      subtitle: Text(text, style: value == null ? TextStyle(color: theme.hintColor) : null),
      trailing: readOnly ? null : value == null ? const Icon(Icons.add_circle_outline)
        : onRemove == null ? const Icon(Icons.edit_outlined)
        : PopupMenuButton<String>(tooltip: tt('More'),
            onSelected: (v) {
              if (v == 'edit') { onTap(); }
              else if (v == 'counter' && space != null) {
                CounterSourceActions.open(context, space!, CounterSource.special(value, people));
              } else { onRemove(); }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(tt('Change'))),
              PopupMenuItem(value: 'counter', child: Row(children: [
                const Icon(Icons.hourglass_bottom_outlined), const SizedBox(width: 8),
                Text(tt('Add to counters'))])),
              PopupMenuItem(value: 'remove', child: Text(tt('Remove'))),
            ]),
      onTap: busy || readOnly ? null : onTap));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = people;
    final custom = dates.where((d) => d.kind == 'custom').toList();
    final mine = p == null ? null : find('birthday', p.me);
    final theirs = p?.partnerId == null ? null : find('birthday', p!.partnerId);
    final anniversary = find('anniversary');
    return Scaffold(
      appBar: AppBar(title: Text(tt('Birthdays, anniversary & special dates'))),
      body: SafeArea(child: loading ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(16), children: [
          Text(tt('Fill these once. They show in the calendar every year, and you can start planning an occasion from any of them.'),
            style: theme.textTheme.bodyMedium),
          const SizedBox(height: 14),
          if (!OneSpaceEnv.isProduction && p != null) ..._qaBirthdays(theme, p, mine, theirs),
          if (space == null) Text(tt(OneSpaceEnv.isProduction ? 'Connect your shared space first.'
            : 'Your anniversary and shared special dates can be added once your partner joins.'))
          else ...[
            if (OneSpaceEnv.isProduction) ...[
            Text(tt('Birthdays'), style: theme.textTheme.titleMedium),
            if (p != null) slot(icon: Icons.cake_outlined, title: 'Your birthday', value: mine,
              onTap: () => setSlot('birthday', 'Your birthday', person: p.me),
              onRemove: mine == null ? null : () => remove(mine)),
            if (p?.partnerId != null) slot(icon: Icons.cake_outlined,
              title: "${p!.partnerName}'s birthday", value: theirs,
              onTap: () => setSlot('birthday', "${p.partnerName}'s birthday", person: p.partnerId),
              onRemove: theirs == null ? null : () => remove(theirs)),
            ],
            const SizedBox(height: 12),
            Text(tt('Us'), style: theme.textTheme.titleMedium),
            slot(icon: Icons.favorite_border, title: 'Our anniversary', value: anniversary,
              onTap: () => setSlot('anniversary', 'Our anniversary'),
              onRemove: anniversary == null ? null : () => remove(anniversary)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text(tt('Our own special dates'), style: theme.textTheme.titleMedium)),
              TextButton.icon(onPressed: busy ? null : () => editCustom(), icon: const Icon(Icons.add),
                label: Text(tt('Add'))),
            ]),
            if (custom.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(tt('First date, the day you met, adoption day, moving-in day… add the days that matter to you.'),
                style: theme.textTheme.bodySmall)),
            for (final d in custom) slot(icon: Icons.star_outline, title: d.title, value: d,
              onTap: () => editCustom(d), onRemove: () => remove(d)),
          ],
          if (error != null) Padding(padding: const EdgeInsets.only(top: 10),
            child: Text(tt(error!), style: TextStyle(color: theme.colorScheme.error))),
        ])));
  }
}

extension on _SpecialDatesScreenState {
  /// QA: each person keeps their own birthday and decides what the partner sees.
  List<Widget> _qaBirthdays(ThemeData theme, SpacePeople p, SpecialDate? mine, SpecialDate? theirs) => [
    Text(tt('Birthdays'), style: theme.textTheme.titleMedium),
    slot(icon: Icons.cake_outlined, title: 'Your birthday', value: mine,
      onTap: setMyBirthday, onRemove: mine == null ? null : () => remove(mine)),
    if (hasBirthday) ...[
      // Sharing only means something while a partner is here.
      SwitchListTile(contentPadding: EdgeInsets.zero,
        key: const Key('qaShareBirthday'),
        title: Text(tt('Show my birthday to my partner')),
        value: p.paired && shareBirthday,
        onChanged: busy || !p.paired ? null : (v) => setBirthdaySharing(share: v)),
      SwitchListTile(contentPadding: EdgeInsets.zero,
        key: const Key('qaShareBirthYear'),
        title: Text(tt('Also show my birth year')),
        subtitle: Text(tt('Without the year, your partner sees the day only, not your age.')),
        value: p.paired && shareYear,
        onChanged: busy || !p.paired || !shareBirthday ? null : (v) => setBirthdaySharing(year: v)),
      Text(tt(p.paired
          ? 'Both are off by default, and switch off again whenever a partner joins or your space changes.'
          : 'You can choose these once a partner joins your space.'),
        style: theme.textTheme.bodySmall),
    ],
    if (p.partnerId != null) slot(icon: Icons.cake_outlined,
      title: "${p.partnerName}'s birthday", value: theirs,
      empty: '${p.partnerName} has not shared their birthday',
      readOnly: true, onTap: () {}),
    const SizedBox(height: 12),
  ];
}

/// Month names for "14 March" when the year is not kept.
class OnespaceMonths {
  const OnespaceMonths._();
  static const _en = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'];
  static String name(int month) => _en[(month - 1).clamp(0, 11)];
}
