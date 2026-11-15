import '../../core/form_kit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../calendar/calendar_event_editor.dart';
import '../connect/shared_experiences_screen.dart';
import '../coordinate/activity_detail_screen.dart';
import '../notes/notes_screen.dart';
import '../occasions/occasions_screen.dart';
import '../plans/plans_screen.dart';
import '../reminders/reminders_screen.dart';
import '../world/trips_screen.dart';
import 'items_to_sort_screen.dart';
import 'share_intake_rules.dart';
import 'share_suggestions.dart';

/// R52 (spec 4.1, backlog B-16): everything shared into OneSpace lands here.
/// The first choice is always "Save to Items to sort" (one tap, sort later).
/// Below it, up to three destinations suggested from WHAT was shared, then
/// "More…" with every destination. Nothing reaches the partner until a
/// destination is saved as Shared.
///
/// When [trayItem] is given, this screen sorts that tray item: on success the
/// tray item is marked sorted and leaves the list.
class ShareIntakeScreen extends StatefulWidget {
  const ShareIntakeScreen({super.key, this.shared, this.trayItem});
  final IncomingShare? shared;
  final Map<String, dynamic>? trayItem;
  @override State<ShareIntakeScreen> createState() => _ShareIntakeScreenState();
}

class _ShareIntakeScreenState extends State<ShareIntakeScreen> {
  final db = Supabase.instance.client;
  late final TextEditingController title, url, notes, price, currency, specs;
  String? spaceId, error, selectedActivity, selectedOccasion;
  bool loading = true, saving = false, onlyMe = false, showMore = false;
  ShareDestination? destination;
  String category = 'other';
  List<Map<String, dynamic>> activities = [], occasions = [];

  bool get sorting => widget.trayItem != null;

  IncomingShare get current => IncomingShare(
      title: title.text.trim(), link: url.text.trim(), note: notes.text.trim());

  @override void initState() {
    super.initState();
    final tray = widget.trayItem;
    final content = widget.shared;
    title = TextEditingController(text: tray?['title']?.toString() ?? content?.title ?? '');
    url = TextEditingController(text: tray?['link']?.toString() ?? content?.link ?? '');
    notes = TextEditingController(text: tray?['note']?.toString() ?? content?.note ?? '');
    price = TextEditingController();
    currency = TextEditingController(text: 'USD');
    specs = TextEditingController();
    // Shared-in content is private by default until a destination is chosen.
    onlyMe = tray == null ? false : tray['visibility'] != 'shared';
    load();
  }

  @override void dispose() {
    for (final c in [title, url, notes, price, currency, specs]) { c.dispose(); }
    super.dispose();
  }

  Future<void> load() async {
    try {
      final id = await CurrentSpaceCache.instance.get();
      if (id == null) {
        if (mounted) setState(() { loading = false; error = 'Connect a shared space first.'; });
        return;
      }
      if (mounted) setState(() => spaceId = id);
      final rows = await db.from('activities').select('id,title,visibility,archived_at')
          .eq('space_id', id).isFilter('archived_at', null)
          .order('updated_at', ascending: false).limit(100);
      final plans = await db.from('occasion_plans').select('id,title,occasion_on,status')
          .eq('space_id', id).isFilter('archived_at', null)
          .not('status', 'in', '(celebrated,cancelled)')
          .order('occasion_on', ascending: true).limit(60);
      if (!mounted) return;
      setState(() {
        activities = List<Map<String, dynamic>>.from(rows);
        occasions = List<Map<String, dynamic>>.from(plans);
        selectedActivity = activities.isEmpty ? null : activities.first['id'].toString();
        selectedOccasion = occasions.isEmpty ? null : occasions.first['id'].toString();
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { loading = false; });
    }
  }

  String? _validate({bool requireBody = false}) {
    final name = title.text.trim(), link = url.text.trim();
    if (name.isEmpty) return 'Add a title.';
    if (link.isNotEmpty && !ShareIntakeRules.isWebLink(link)) {
      return 'Only http or https links can be saved.';
    }
    if (requireBody && link.isEmpty && notes.text.trim().isEmpty) return 'Add a link or note first.';
    return null;
  }

  String get _bodyWithLink {
    final body = notes.text.trim(), link = url.text.trim();
    return body + (link.isEmpty ? '' : (body.isEmpty ? '' : '\n\n') + link);
  }

  /// One tap: keep it in the tray, private to me.
  Future<void> saveToTray() async {
    final problem = _validate();
    if (problem != null) { setState(() => error = problem); return; }
    if (spaceId == null || saving) return;
    setState(() { saving = true; error = null; });
    try {
      await db.from('items_to_sort').insert({
        'space_id': spaceId,
        'title': title.text.trim().length > 180 ? title.text.trim().substring(0, 180) : title.text.trim(),
        'link': url.text.trim().isEmpty ? null : url.text.trim(),
        'note': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'visibility': 'private',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Saved to Items to sort. Sort it whenever you like.')));
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => const ItemsToSortScreen()));
    } catch (_) {
      if (mounted) setState(() { saving = false; error = 'Could not save. Please try again.'; });
    }
  }

  Future<void> _markSorted(String to) async {
    final tray = widget.trayItem;
    if (tray == null) return;
    try {
      await db.from('items_to_sort').update({
        'sorted_at': DateTime.now().toUtc().toIso8601String(), 'sorted_to': to,
      }).eq('id', tray['id'].toString());
    } catch (_) {/* The item stays in the tray; nothing is lost. */}
  }

  Future<void> saveToDestination() async {
    final d = destination;
    if (d == null || spaceId == null || saving) return;
    final problem = _validate(requireBody: d == ShareDestination.activityOption);
    if (problem != null) { setState(() => error = problem); return; }
    setState(() { saving = true; error = null; });
    final name = title.text.trim(), link = url.text.trim(), body = notes.text.trim();
    final visibility = onlyMe ? 'private' : 'shared';
    try {
      Widget? next;
      bool done = true;
      switch (d) {
        case ShareDestination.newActivity:
          final created = await db.from('activities').insert({
            'space_id': spaceId, 'title': name, 'body': _bodyWithLink,
            'visibility': visibility,
          }).select('id').single();
          final id = created['id'].toString();
          if (link.isNotEmpty) {
            try {
              await db.from('activity_components').insert({
                'activity_id': id, 'kind': 'link', 'label': name,
                'payload': {'value': link, 'note': body},
              });
            } catch (_) {/* The link is kept in the description. */}
          }
          next = ActivityScreen(id: id);
        case ShareDestination.activityOption:
          if (selectedActivity == null) {
            setState(() { saving = false; error = 'Choose an Activity first.'; });
            return;
          }
          final amount = price.text.trim().isEmpty ? null : double.tryParse(price.text.trim());
          if (price.text.trim().isNotEmpty && (amount == null || amount < 0)) {
            setState(() { saving = false; error = 'Enter a valid price or leave it blank.'; });
            return;
          }
          await db.from('activity_components').insert({
            'activity_id': selectedActivity,
            'kind': link.isEmpty ? 'note' : 'option',
            'label': name,
            'payload': link.isEmpty ? {'value': body} : {
              'value': link, 'url': link, 'note': body, 'price': price.text.trim(),
              'currency': currency.text.trim().toUpperCase(),
              'specs': specs.text.trim(), 'state': 'considering',
            },
          });
          next = ActivityScreen(id: selectedActivity!);
        case ShareDestination.experience:
          final created = await db.from('shared_experiences').insert({
            'space_id': spaceId, 'category': category, 'title': name,
            'description': body, 'source_url': link,
          }).select('id').single();
          next = SharedExperiencesScreen(initialExperienceId: created['id'].toString());
        case ShareDestination.giftIdea:
          if (selectedOccasion == null) {
            setState(() { saving = false; error = 'Plan an occasion first, then add gift ideas to it.'; });
            return;
          }
          await db.from('occasion_budget_items').insert({
            'plan_id': selectedOccasion, 'title': name.length > 200 ? name.substring(0, 200) : name,
            'source_url': link.isEmpty ? null : link,
            'notes': body.isEmpty ? null : (body.length > 2500 ? body.substring(0, 2500) : body),
            'status': 'wish',
          });
          next = OccasionsScreen(initialPlanId: selectedOccasion);
        case ShareDestination.todo:
          await db.from('tasks').insert({
            'space_id': spaceId, 'created_by': db.auth.currentUser!.id,
            'title': name, 'status': 'open', 'visibility': visibility,
          });
          next = const PlansScreen();
        case ShareDestination.note:
          final created = await db.from('notes').insert({
            'space_id': spaceId, 'created_by': db.auth.currentUser!.id,
            'title': name, 'body': _bodyWithLink, 'visibility': visibility,
          }).select('id').single();
          next = NotesScreen(initialNoteId: created['id'].toString());
        case ShareDestination.reminder:
          done = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
            builder: (_) => ReminderEditorScreen(spaceId: spaceId!,
              initialTitle: name, initialDetails: _bodyWithLink))) == true;
        case ShareDestination.event:
          done = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
            builder: (_) => CalendarEventEditor(spaceId: spaceId!,
              initialDate: DateTime.now(), initialTitle: name,
              initialDetails: _bodyWithLink))) == true;
        case ShareDestination.trip:
          done = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
            builder: (_) => TripEditor(spaceId: spaceId!,
              prefill: {'title': name, 'notes': _bodyWithLink}))) == true;
      }
      if (!mounted) return;
      if (!done) { setState(() => saving = false); return; }
      await _markSorted(d.name);
      if (!mounted) return;
      if (next != null) {
        await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => next!));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved as ${d.label}.')));
        Navigator.of(context).pop();
      }
    } on PostgrestException catch (e) {
      if (mounted) setState(() { saving = false; error = e.message; });
    } catch (_) {
      if (mounted) setState(() { saving = false; error = 'Could not save. Nothing was shared; please try again.'; });
    }
  }

  Widget _destinationChip(ShareDestination d) => ChoiceChip(
    label: Text(d.label),
    selected: destination == d,
    onSelected: (_) => setState(() { destination = d; error = null; }));

  Widget _destinationDetails(BuildContext context) {
    final d = destination;
    if (d == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final privacy = d == ShareDestination.activityOption || d == ShareDestination.giftIdea
        || d == ShareDestination.experience || d == ShareDestination.reminder
        || d == ShareDestination.event || d == ShareDestination.trip
        ? null
        : SwitchListTile(contentPadding: EdgeInsets.zero,
            value: onlyMe, onChanged: (v) => setState(() => onlyMe = v),
            title: const Text('Only me'),
            subtitle: Text(onlyMe ? 'Kept private to you.' : 'Both of you can see it.'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 10),
      if (d == ShareDestination.activityOption) ...[
        if (loading) const LinearProgressIndicator(),
        if (activities.isEmpty && !loading)
          const Text('There are no Activities yet. Choose "New Activity" instead.')
        else if (activities.isNotEmpty) ChoicePickerField<String>(label: 'Activity', required: true, icon: Icons.hub_outlined,
          options: {for (final a in activities) a['id'].toString():
            '${a['title']}${a['visibility'] == 'private' ? ' · Only me' : ''}'},
          selected: selectedActivity,
          onSelected: (v) => setState(() => selectedActivity = v)),
        if (url.text.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(flex: 2, child: TextField(controller: price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Price (optional)', border: OutlineInputBorder()))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: currency, maxLength: 3,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Currency', border: OutlineInputBorder(),
                counterText: ''))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: specs, maxLength: 2500, minLines: 2, maxLines: 4,
            decoration: const InputDecoration(labelText: 'Specifications or pros/cons',
              border: OutlineInputBorder())),
        ],
        Text('Follows the Activity\'s own privacy.', style: theme.textTheme.bodySmall),
      ],
      if (d == ShareDestination.giftIdea) ...[
        if (occasions.isEmpty && !loading)
          const Text('There is no upcoming occasion yet. Plan one in Occasions first.')
        else if (occasions.isNotEmpty) ChoicePickerField<String>(label: 'Occasion', required: true, icon: Icons.card_giftcard_outlined,
          options: {for (final o in occasions) o['id'].toString():
            '${o['title']}${o['occasion_on'] == null ? '' : ' · ${o['occasion_on']}'}'},
          selected: selectedOccasion,
          onSelected: (v) => setState(() => selectedOccasion = v)),
        Text('Saved as a gift idea in that occasion\'s plan.', style: theme.textTheme.bodySmall),
      ],
      if (d == ShareDestination.experience) ...[
        ChoiceRow<String>(label: 'Watchlist', options: experienceTypes, selected: category,
          onSelected: (v) => setState(() => category = v ?? category)),
        Text('Shared experiences are visible to both of you.', style: theme.textTheme.bodySmall),
      ],
      if (d == ShareDestination.reminder || d == ShareDestination.event || d == ShareDestination.trip)
        Text('Opens the ${d.label.toLowerCase()} page with this filled in; choose the date and save there.',
          style: theme.textTheme.bodySmall),
      if (privacy != null) privacy,
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: saving || spaceId == null ? null : saveToDestination,
        icon: const Icon(Icons.check),
        label: Text(saving ? 'Saving…' : 'Save as ${d.label}')),
    ]);
  }

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final share = current;
    final suggested = ShareSuggestions.forShare(share);
    final others = ShareSuggestions.more(share);
    return Scaffold(
      appBar: AppBar(title: Text(sorting ? 'Sort item' : 'Save to OneSpace')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
        Card(elevation: 0, color: theme.colorScheme.surfaceContainerLow,
          child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
            TextField(controller: title, maxLength: 120,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
            const SizedBox(height: 6),
            TextField(controller: url, maxLength: 1800, keyboardType: TextInputType.url,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Link (optional)', border: OutlineInputBorder())),
            const SizedBox(height: 6),
            TextField(controller: notes, maxLength: 5000, minLines: 2, maxLines: 5,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Comment (optional)',
                border: OutlineInputBorder())),
          ]))),
        if (!sorting) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: saving || spaceId == null ? null : saveToTray,
            icon: const Icon(Icons.inbox_outlined),
            label: const Text('Save to Items to sort')),
          Padding(padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text('Done for now; sort it later. Only you can see it.',
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall)),
        ],
        const SizedBox(height: 12),
        Text(sorting ? 'Where should it go?' : 'Or put it somewhere now',
          style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text('Suggested', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final d in suggested) _destinationChip(d),
          ActionChip(
            avatar: Icon(showMore ? Icons.expand_less : Icons.expand_more, size: 18),
            label: const Text('More…'),
            onPressed: () => setState(() => showMore = !showMore)),
        ]),
        if (showMore) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [for (final d in others) _destinationChip(d)]),
        ],
        _destinationDetails(context),
        if (error != null) Padding(padding: const EdgeInsets.all(6),
          child: Text(error!, style: TextStyle(color: theme.colorScheme.error))),
      ]),
    );
  }
}
