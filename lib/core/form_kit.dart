import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'current_space_cache.dart';

/// R57 (Ahmed, 15 Nov): one form language for every editor.
///
/// * Small sets (≤ 6 options) → [ChoiceRow] (chips).
/// * Long sets → [ChoicePickerField] (one tile that opens a searchable list).
/// * No dropdowns.
/// * The three details almost every item shares — who can see it, who it
///   belongs to and an optional date — sit in one [MetaStrip] right above
///   Cancel/Save, always in the same place and order.

/// Who is in the space: me and my partner (with the name I use for them).
class SpacePeople {
  const SpacePeople({required this.me, this.partnerId, this.partnerName = 'Partner'});
  final String me;
  final String? partnerId;
  final String partnerName;

  static SpacePeople? _cached;
  static Future<SpacePeople?> load() async {
    if (_cached != null) return _cached;
    final db = Supabase.instance.client;
    final me = db.auth.currentUser?.id;
    if (me == null) return null;
    try {
      final space = await CurrentSpaceCache.instance.get();
      if (space == null) return SpacePeople(me: me);
      final rows = await db.from('space_members').select('user_id').eq('space_id', space);
      final partner = rows.map((r) => r['user_id']?.toString()).where((id) => id != null && id != me).firstOrNull;
      var name = 'Partner';
      if (partner != null) {
        final mine = await db.from('profiles').select('partner_label').eq('id', me).maybeSingle();
        final label = mine?['partner_label']?.toString().trim() ?? '';
        if (label.isNotEmpty) {
          name = label;
        } else {
          final p = await db.from('profiles').select('display_name').eq('id', partner).maybeSingle();
          final first = (p?['display_name']?.toString().trim() ?? '').split(RegExp(r'\s+')).first;
          if (first.isNotEmpty) name = first;
        }
      }
      return _cached = SpacePeople(me: me, partnerId: partner, partnerName: name);
    } catch (_) {
      return SpacePeople(me: me);
    }
  }

  /// Forget the cache (sign-out, partner change).
  static void reset() => _cached = null;
}

/// The values the [MetaStrip] edits.
class MetaValues {
  const MetaValues({this.shared = true, this.belongsTo, this.date});
  final bool shared;
  /// null = both of us; otherwise a user id.
  final String? belongsTo;
  final DateTime? date;

  MetaValues copyWith({bool? shared, Object? belongsTo = _keep, Object? date = _keep}) => MetaValues(
    shared: shared ?? this.shared,
    belongsTo: identical(belongsTo, _keep) ? this.belongsTo : belongsTo as String?,
    date: identical(date, _keep) ? this.date : date as DateTime?);
  static const _keep = Object();

  /// The linked rules: a private item belongs to me; an item that belongs to
  /// my partner must be shared (otherwise they could never see it).

  String get signature => '$shared|$belongsTo|${date?.toIso8601String()}';
}

/// Pure rules behind the strip (tested).
class MetaRules {
  const MetaRules._();
  static MetaValues setShared(MetaValues v, bool shared, String me) =>
      shared ? v.copyWith(shared: true) : v.copyWith(shared: false, belongsTo: me);
  /// "Both of us" or my partner can only be chosen for a shared item.
  static MetaValues setBelongsTo(MetaValues v, String? who, String me) =>
      who != me ? v.copyWith(belongsTo: who, shared: true) : v.copyWith(belongsTo: who);
  static String belongsLabel(String? who, SpacePeople? people) =>
      who == null ? 'Both of us' : who == people?.me ? 'Me' : (people?.partnerName ?? 'Partner');
}

/// The three fixed chips above Cancel/Save.
class MetaStrip extends StatelessWidget {
  const MetaStrip({super.key, required this.value, required this.onChanged, this.people,
    this.showVisibility = true, this.showBelongs = true, this.showDate = true,
    this.dateLabel = 'Date', this.withTime = false});
  final MetaValues value;
  final ValueChanged<MetaValues> onChanged;
  final SpacePeople? people;
  final bool showVisibility, showBelongs, showDate, withTime;
  final String dateLabel;

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final day = await showDatePicker(context: context,
      initialDate: value.date ?? now, firstDate: DateTime(now.year - 2), lastDate: DateTime(now.year + 10));
    if (day == null || !context.mounted) return;
    var picked = day;
    if (withTime) {
      final t = await showTimePicker(context: context,
        initialTime: TimeOfDay.fromDateTime(value.date ?? now.add(const Duration(hours: 1))));
      if (t != null) picked = DateTime(day.year, day.month, day.day, t.hour, t.minute);
    }
    onChanged(value.copyWith(date: picked));
  }

  @override
  Widget build(BuildContext context) {
    final me = people?.me ?? '';
    final loc = MaterialLocalizations.of(context);
    final chips = <Widget>[
      if (showVisibility) _MenuChip<bool>(
        icon: value.shared ? Icons.people_outline : Icons.lock_outline,
        label: value.shared ? 'Shared' : 'Only me',
        tooltip: 'Who can see it',
        options: const {true: 'Shared', false: 'Only me'},
        icons: const {true: Icons.people_outline, false: Icons.lock_outline},
        selected: value.shared,
        onSelected: (v) => onChanged(MetaRules.setShared(value, v, me))),
      if (showBelongs) _MenuChip<String>(
        icon: value.belongsTo == null ? Icons.group_outlined : Icons.person_outline,
        label: MetaRules.belongsLabel(value.belongsTo, people),
        tooltip: 'Belongs to',
        options: {
          '': 'Both of us',
          if (me.isNotEmpty) me: 'Me',
          if (people?.partnerId != null) people!.partnerId!: people!.partnerName,
        },
        icons: {'': Icons.group_outlined, if (me.isNotEmpty) me: Icons.person_outline,
          if (people?.partnerId != null) people!.partnerId!: Icons.favorite_border},
        selected: value.belongsTo ?? '',
        onSelected: (v) => onChanged(MetaRules.setBelongsTo(value, v.isEmpty ? null : v, me))),
      if (showDate) InputChip(
        avatar: const Icon(Icons.event_outlined, size: 18),
        label: Text(value.date == null ? 'Add ${dateLabel.toLowerCase()}'
          : withTime ? '${loc.formatShortDate(value.date!)} ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(value.date!))}'
          : loc.formatShortDate(value.date!)),
        tooltip: dateLabel,
        onPressed: () => _pickDate(context),
        onDeleted: value.date == null ? null : () => onChanged(value.copyWith(date: null))),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            chips[i],
          ],
        ])));
  }
}

class _MenuChip<T> extends StatelessWidget {
  const _MenuChip({required this.icon, required this.label, required this.tooltip,
    required this.options, required this.selected, required this.onSelected, this.icons = const {}});
  final IconData icon;
  final String label, tooltip;
  final Map<T, String> options;
  final Map<T, IconData> icons;
  final T selected;
  final ValueChanged<T> onSelected;
  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    tooltip: tooltip,
    initialValue: selected,
    onSelected: onSelected,
    itemBuilder: (_) => [
      for (final e in options.entries) CheckedPopupMenuItem<T>(
        value: e.key, checked: e.key == selected,
        child: Row(children: [
          if (icons[e.key] != null) ...[Icon(icons[e.key], size: 20), const SizedBox(width: 10)],
          Text(e.value),
        ])),
    ],
    child: Chip(
      avatar: Icon(icon, size: 18),
      label: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label), const SizedBox(width: 2), const Icon(Icons.arrow_drop_down, size: 18)]),
    ));
}

/// A labelled row of choice chips (≤ 6 options).
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({super.key, required this.label, required this.options, required this.selected,
    required this.onSelected, this.icons = const {}, this.required = false, this.allowNone = false});
  final String label;
  final Map<T, String> options;
  final Map<T, IconData> icons;
  final T? selected;
  final ValueChanged<T?> onSelected;
  final bool required, allowNone;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(required ? '$label *' : label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final e in options.entries) ChoiceChip(
          avatar: icons[e.key] == null ? null : Icon(icons[e.key], size: 18),
          showCheckmark: false,
          label: Text(e.value),
          selected: selected == e.key,
          onSelected: (on) => onSelected(on ? e.key : (allowNone ? null : e.key))),
      ]),
    ]));
}

/// A long list (category, currency, time zone…): one tile showing the
/// choice; tapping opens a searchable list in a bottom sheet.
class ChoicePickerField<T> extends StatelessWidget {
  const ChoicePickerField({super.key, required this.label, required this.options,
    required this.selected, required this.onSelected, this.icon, this.icons = const {},
    this.required = false, this.noneLabel});
  final String label;
  final Map<T, String> options;
  final Map<T, IconData> icons;
  final T? selected;
  final ValueChanged<T?> onSelected;
  final IconData? icon;
  final bool required;
  /// When set, the list starts with this "none" choice (selected = null).
  final String? noneLabel;

  Future<void> _open(BuildContext context) async {
    final result = await showModalBottomSheet<_Pick<T>>(context: context,
      isScrollControlled: true, showDragHandle: true,
      builder: (_) => _PickerSheet<T>(title: label, options: options, icons: icons,
        selected: selected, noneLabel: noneLabel));
    if (result != null) onSelected(result.value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = selected == null ? (noneLabel ?? 'Choose') : (options[selected] ?? 'Choose');
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(context),
      child: InputDecorator(
        decoration: InputDecoration(labelText: required ? '$label *' : label,
          prefixIcon: Icon(icons[selected] ?? icon ?? Icons.list_alt_outlined),
          suffixIcon: const Icon(Icons.unfold_more),
          border: const OutlineInputBorder()),
        child: Text(text, style: theme.textTheme.bodyLarge))));
  }
}

class _Pick<T> { const _Pick(this.value); final T? value; }

class _PickerSheet<T> extends StatefulWidget {
  const _PickerSheet({required this.title, required this.options, required this.icons,
    required this.selected, this.noneLabel});
  final String title;
  final Map<T, String> options;
  final Map<T, IconData> icons;
  final T? selected;
  final String? noneLabel;
  @override State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final entries = widget.options.entries
        .where((e) => q.isEmpty || e.value.toLowerCase().contains(q.toLowerCase())).toList();
    return SafeArea(child: SizedBox(
      height: MediaQuery.of(context).size.height * .7,
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            if (widget.options.length > 8) Padding(padding: const EdgeInsets.only(top: 8),
              child: TextField(autofocus: false, onChanged: (v) => setState(() => q = v),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search),
                  hintText: 'Search', isDense: true, border: OutlineInputBorder()))),
          ])),
        Expanded(child: ListView(children: [
          if (widget.noneLabel != null && q.isEmpty) ListTile(
            leading: const Icon(Icons.remove_circle_outline),
            title: Text(widget.noneLabel!),
            trailing: widget.selected == null ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, _Pick<T>(null))),
          for (final e in entries) ListTile(
            leading: Icon(widget.icons[e.key] ?? Icons.circle_outlined),
            title: Text(e.value),
            trailing: e.key == widget.selected ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, _Pick<T>(e.key))),
        ])),
      ])));
  }
}

/// A required or optional date (or date + time) inside the form body —
/// used when the date is the point of the item (event, occasion, trip).
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged,
    this.required = false, this.withTime = false, this.first, this.last});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool required, withTime;
  final DateTime? first, last;
  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final text = value == null ? 'Choose' : withTime
        ? '${loc.formatMediumDate(value!)} · ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(value!))}'
        : loc.formatFullDate(value!);
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final d = await showDatePicker(context: context, initialDate: value ?? now,
          firstDate: first ?? DateTime(now.year - 5), lastDate: last ?? DateTime(now.year + 10));
        if (d == null || !context.mounted) return;
        var picked = d;
        if (withTime) {
          final t = await showTimePicker(context: context,
            initialTime: TimeOfDay.fromDateTime(value ?? now));
          if (t != null) picked = DateTime(d.year, d.month, d.day, t.hour, t.minute);
        }
        onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: required ? '$label *' : label,
          prefixIcon: Icon(withTime ? Icons.schedule : Icons.event_outlined),
          suffixIcon: !required && value != null
            ? IconButton(tooltip: 'Clear', icon: const Icon(Icons.close), onPressed: () => onChanged(null))
            : null,
          border: const OutlineInputBorder()),
        child: Text(text))));
  }
}

/// Section title inside a form.
class FormSection extends StatelessWidget {
  const FormSection(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 10),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(
      color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)));
}
