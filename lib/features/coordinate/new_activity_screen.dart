import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../calendar/calendar_rules.dart';
import 'activity_detail_screen.dart';

/// Purpose starters for a new Activity (spec 2.1). Each fills the details with
/// a short, editable outline so the Activity starts with the right shape.
enum ActivityPurpose {
  buy('Buy something', Icons.shopping_bag_outlined,
      'What we need:\nBudget:\nOptions we are comparing:\nWhere to buy:'),
  findService('Find a class or service', Icons.school_outlined,
      'What we are looking for:\nWhen and how often:\nPeople or places to contact:\nNext step:'),
  planEvent('Plan an event', Icons.celebration_outlined,
      'What and why:\nDate and place:\nWho is coming:\nChecklist:'),
  decide('Decide something', Icons.balance_outlined,
      'The question:\nOptions:\nWhat matters most to us:\nDecide by:'),
  note('Just a note', Icons.notes_outlined, '');

  const ActivityPurpose(this.label, this.icon, this.outline);
  final String label;
  final IconData icon;
  final String outline;
}

/// Pure rules for the new-Activity draft, kept testable.
class NewActivityDraft {
  const NewActivityDraft({required this.title, this.details = '',
    this.shared = true, this.dueOn});
  final String title, details;
  final bool shared;
  final DateTime? dueOn;

  /// A draft becomes a record only once it has a title (no half-empty records).
  bool get canSave => title.trim().isNotEmpty;

  Map<String, dynamic> toInsert(String spaceId) => {
    'space_id': spaceId,
    'title': title.trim(),
    'body': details.trim(),
    'visibility': shared ? 'shared' : 'private',
    if (dueOn != null) 'due_on': CalendarRules.sqlDate(dueOn!),
  };

  /// Switching purpose replaces the outline only while the details still hold
  /// an untouched outline (or nothing), never text the person typed.
  static String detailsFor(ActivityPurpose purpose, String current) {
    final untouched = current.trim().isEmpty ||
        ActivityPurpose.values.any((p) => p.outline.isNotEmpty && current == p.outline);
    return untouched ? purpose.outline : current;
  }
}

/// R51 (B-15): a new Activity opens as a full page in draft, never a dialog.
/// Leaving without a title creates nothing.
class NewActivityScreen extends StatefulWidget {
  const NewActivityScreen({super.key, required this.spaceId,
    this.initialPurpose, this.initialTitle = '', this.initialDetails = ''});
  final String spaceId;
  final ActivityPurpose? initialPurpose;
  final String initialTitle, initialDetails;
  @override State<NewActivityScreen> createState() => _NewActivityScreenState();
}

class _NewActivityScreenState extends State<NewActivityScreen> {
  final db = Supabase.instance.client;
  late final title = TextEditingController(text: widget.initialTitle);
  late final details = TextEditingController(text: widget.initialDetails.isNotEmpty
      ? widget.initialDetails : widget.initialPurpose?.outline ?? '');
  ActivityPurpose? purpose;
  bool shared = true;
  DateTime? dueOn;
  bool saving = false;
  String? error;

  @override void initState() {
    super.initState();
    purpose = widget.initialPurpose;
    title.addListener(() => setState(() {}));
  }

  @override void dispose() { title.dispose(); details.dispose(); super.dispose(); }

  NewActivityDraft get draft => NewActivityDraft(title: title.text,
      details: details.text, shared: shared, dueOn: dueOn);

  Future<void> _save() async {
    if (!draft.canSave || saving) return;
    setState(() { saving = true; error = null; });
    try {
      final created = await db.from('activities')
          .insert(draft.toInsert(widget.spaceId)).select('id').single();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => ActivityScreen(id: created['id'].toString())));
    } on PostgrestException catch (e) {
      if (mounted) setState(() { saving = false; error = e.message; });
    } catch (_) {
      if (mounted) setState(() { saving = false; error = 'Could not create the Activity.'; });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context,
        initialDate: dueOn ?? now, firstDate: DateTime(now.year - 1),
        lastDate: DateTime(now.year + 5));
    if (picked != null && mounted) setState(() => dueOn = picked);
  }

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Add new Activity')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: title,
            autofocus: true,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            style: theme.textTheme.headlineSmall,
            decoration: const InputDecoration(
              hintText: 'What is this about?', border: InputBorder.none,
              counterText: '')),
          Wrap(spacing: 8, runSpacing: 4, children: [
            FilterChip(
              avatar: Icon(shared ? Icons.people_outline : Icons.lock_outline, size: 18),
              label: Text(shared ? 'Shared' : 'Only me'),
              selected: !shared,
              onSelected: (_) => setState(() => shared = !shared)),
            InputChip(
              avatar: const Icon(Icons.event_outlined, size: 18),
              label: Text(dueOn == null ? 'Add date' : CalendarRules.sqlDate(dueOn!)),
              onPressed: _pickDate,
              onDeleted: dueOn == null ? null : () => setState(() => dueOn = null)),
          ]),
          const SizedBox(height: 18),
          Text('Start from a purpose', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in ActivityPurpose.values) ChoiceChip(
              avatar: Icon(p.icon, size: 18),
              label: Text(p.label),
              selected: purpose == p,
              onSelected: (_) => setState(() {
                purpose = p;
                details.text = NewActivityDraft.detailsFor(p, details.text);
              })),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: details,
            minLines: 5, maxLines: 14, maxLength: 12000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Details', alignLabelWithHint: true,
              border: OutlineInputBorder())),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(error!, style: TextStyle(color: theme.colorScheme.error))),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: draft.canSave && !saving ? _save : null,
            icon: saving ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
            label: const Text('Create Activity')),
          if (!draft.canSave) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Give it a title to save. Leaving now creates nothing.',
              style: theme.textTheme.bodySmall, textAlign: TextAlign.center)),
        ],
      )),
    );
  }
}
