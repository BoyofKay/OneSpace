import '../../core/form_kit.dart';
import '../../core/editor_scaffold.dart';
import '../../core/account_content_scope.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../calendar/calendar_rules.dart';
import 'activity_detail_screen.dart';
import 'package:onespace/l10n/phrases.dart';

/// Purpose starters for a new Activity (spec 2.1). Each fills the details with
/// a short, editable outline so the Activity starts with the right shape.
enum ActivityPurpose {
  buy('Buy something', Icons.shopping_bag_outlined,
      'What we need and why.', [
        'Agree on a budget', 'Compare at least two options', 'Choose where to buy',
      ]),
  findService('Find a class or service', Icons.school_outlined,
      'What we are looking for, and when.', [
        'List places or people to contact', 'Ask about times and prices', 'Pick a start date',
      ]),
  planEvent('Plan an event', Icons.celebration_outlined,
      'What we are celebrating and why.', [
        'Set the date and place', 'Make the guest list', 'Send invitations', 'Prepare what we need',
      ]),
  decide('Decide something', Icons.balance_outlined,
      'The question we need to answer.', [
        'Write down the options', 'Each of us says what matters most', 'Agree on a decision date',
      ]),
  note('Just a note', Icons.notes_outlined, '', []);

  const ActivityPurpose(this.label, this.icon, this.outline, this.steps);
  final String label;
  final IconData icon;
  final String outline;

  /// R55: sections pre-added to the new Activity as open steps, so it starts
  /// with the right shape (each can be edited, ticked or removed).
  final List<String> steps;

  List<Map<String, dynamic>> sectionsFor(String activityId) => [
    for (final step in steps)
      {'activity_id': activityId, 'kind': 'step', 'label': step,
       'payload': {'value': '', 'status': 'open'}},
  ];
}

/// Pure rules for the new-Activity draft, kept testable.
class NewActivityDraft {
  const NewActivityDraft({required this.title, this.details = '',
    this.shared = true, this.dueOn, this.forUserId});
  final String title, details;
  final bool shared;
  final DateTime? dueOn;
  /// R66: who it belongs to (null = both of us).
  final String? forUserId;

  /// A draft becomes a record only once it has a title (no half-empty records).
  bool get canSave => title.trim().isNotEmpty;

  Map<String, dynamic> toInsert(String spaceId) => {
    'space_id': spaceId,
    'title': title.trim(),
    'body': details.trim(),
    'visibility': shared ? 'shared' : 'private',
    if (dueOn != null) 'due_on': CalendarRules.sqlDate(dueOn!),
    if (forUserId != null) 'for_user_id': forUserId,
  };

  /// QA uses the independent personal namespace for private Activities.
  /// The older toInsert helper remains for legacy-production compatibility.
  Map<String, dynamic> toScopedInsert(AccountContentScope scope) => {
    ...scope.fieldsForNew(shared: shared),
    'title': title.trim(),
    'body': details.trim(),
    if (dueOn != null) 'due_on': CalendarRules.sqlDate(dueOn!),
    if (shared && forUserId != null) 'for_user_id': forUserId,
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
  const NewActivityScreen({super.key, required this.scope,
    this.initialPurpose, this.initialTitle = '', this.initialDetails = ''});
  final AccountContentScope scope;
  final ActivityPurpose? initialPurpose;
  final String initialTitle, initialDetails;
  @override State<NewActivityScreen> createState() => _NewActivityScreenState();
}

class _NewActivityScreenState extends State<NewActivityScreen> with FormChangeTracker<NewActivityScreen> {
 /// R55: current form values; Save turns on only when they change.
 @override String get signature=>[title.text,details.text,shared,dueOn,purpose,forUserId].join('|');

  final db = Supabase.instance.client;
  late final title = TextEditingController(text: widget.initialTitle);
  late final details = TextEditingController(text: widget.initialDetails);
  ActivityPurpose? purpose;
  bool shared = true;
  DateTime? dueOn;
  String? forUserId;
  SpacePeople? people;
  bool saving = false;
  String? error;

  @override void initState() {
    super.initState();
    purpose = widget.initialPurpose == ActivityPurpose.note ? null : widget.initialPurpose;
    shared = widget.scope.canCreateShared;
    SpacePeople.load().then((p) { if (mounted) setState(() => people = p); });
    title.addListener(() => setState(() {}));
  }

  @override void dispose() { title.dispose(); details.dispose(); super.dispose(); }

  NewActivityDraft get draft => NewActivityDraft(title: title.text,
      details: details.text, shared: shared, dueOn: dueOn,
      forUserId: shared ? forUserId : null);

  Future<void> _save() async {
    if (!draft.canSave || saving) return;
    setState(() { saving = true; error = null; });
    try {
      final created = await db.from('activities')
          .insert(draft.toScopedInsert(widget.scope)).select('id').single();
      final sections = purpose?.sectionsFor(created['id'].toString()) ?? const [];
      if (sections.isNotEmpty) {
        try { await db.from('activity_components').insert(sections); }
        catch (_) {/* The Activity exists; steps can be added by hand. */}
      }
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => ActivityScreen(id: created['id'].toString())));
    } on PostgrestException catch (e) {
      if (mounted) setState(() { saving = false; error = e.message; });
    } catch (_) {
      if (mounted) setState(() { saving = false; error = 'Could not create the Activity.'; });
    }
  }

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EditorScaffold(title:tt('Start activity'),
   isNew:true,isChanged:()=>changed,isComplete:()=>draft.canSave,saveLabel:'Next',
   listenTo:[title,details],saving:saving,onSave:_save,
   meta:MetaStrip(value:MetaValues(shared:shared,belongsTo:forUserId,date:dueOn),people:people,
    showBelongs:people!=null,dateLabel:tt('Due date'),
    enabled:!saving,onChanged:(v)=>setState((){shared=v.shared;dueOn=v.date;forUserId=v.belongsTo;})),
   body: SafeArea(child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
        children: [
          TextField(
            controller: title,
            autofocus: true,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            style: theme.textTheme.headlineSmall,
            decoration: InputDecoration(
              hintText: tt('What is this about? *'), border: InputBorder.none,
              counterText: '')),
          const SizedBox(height: 18),
          Text(tt('What is it for?'), style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in ActivityPurpose.values) if (p != ActivityPurpose.note) ChoiceChip(
              avatar: Icon(p.icon, size: 18),
              label: Text(tt(p.label)),
              selected: purpose == p,
              onSelected: (_) => setState(() => purpose = purpose == p ? null : p)),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: details,
            minLines: 5, maxLines: 14, maxLength: 12000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tt('Details'), alignLabelWithHint: true,
              hintText: purpose?.outline,
              border: const OutlineInputBorder())),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(tt(error!), style: TextStyle(color: theme.colorScheme.error))),
          const SizedBox(height: 12),
        ],
      )),
    );
  }
}
