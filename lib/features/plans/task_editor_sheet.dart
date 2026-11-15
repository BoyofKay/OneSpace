import '../../core/form_kit.dart';
import '../../core/editor_scaffold.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/onespace_strings.dart';
import 'task_date_rules.dart';
import 'checklist_schedule.dart';
import '../mentions/partner_mention_button.dart';
import 'package:onespace/l10n/phrases.dart';
import '../../core/repeat_control.dart';
import '../reminders/reminder_repeat_rules.dart';

enum TaskPriority { low, normal, high }
enum TaskStatus { open, completed, cancelled }
enum TaskVisibility { shared, private }
enum TaskFilter { open, completed, cancelled, all }
enum TaskScope { all, shared, private }

class SharedTask {
  const SharedTask({
    required this.id,
    required this.title,
    required this.priority,
    required this.status,
    required this.createdBy,
    required this.visibility,
    this.assignedTo,
    this.targetDate,
    this.recurrence='none',
    this.rule=const {},
  });
  final String id;
  final String title;
  final TaskPriority priority;
  final TaskStatus status;
  final TaskVisibility visibility;
  final String createdBy;
  final String? assignedTo;
  final String? targetDate;
  final String recurrence;
  final Map<String,dynamic> rule;

  /// Keep older and partially migrated checklist records renderable.
  /// Supabase remains the authority for ownership and edit permission.
  /// Only a missing/invalid ID is unrenderable (handled at list boundary).
  factory SharedTask.fromMap(Map<String, dynamic> row) {
    final rawRules = row['recurrence_rule'];
    final rules = rawRules is Map
      ? <String,dynamic>{
         for (final entry in rawRules.entries)
           if (entry.key is String) entry.key as String: entry.value,
        }
      : <String,dynamic>{};
    final rawTitle = (row['title'] ?? '').toString().trim();
    return SharedTask(
      id: row['id'].toString(),
      title: rawTitle.isEmpty ? 'Untitled checklist' : rawTitle,
      priority: TaskPriority.values.firstWhere(
        (v) => v.name == row['priority'], orElse: () => TaskPriority.normal),
      status: TaskStatus.values.firstWhere(
        (v) => v.name == row['status'], orElse: () => TaskStatus.open),
      visibility: TaskVisibility.values.firstWhere(
        (v) => v.name == (row['visibility'] ?? 'shared'),
        orElse: () => TaskVisibility.shared),
      createdBy: (row['created_by'] ?? '').toString(),
      assignedTo: row['assigned_to']?.toString(),
      targetDate: row['target_date']?.toString(),
      recurrence: (row['recurrence'] ?? 'none').toString(),
      rule: rules,
    );
  }
}

/// Only the fields the user can edit. Privacy never changes after creation.
class TaskDraft {
  const TaskDraft({
    required this.title,
    required this.priority,
    required this.visibility,
    this.assignedTo,
    this.targetDate,
    this.recurrence='none',
    this.rule=const {},
    this.items=const [],
  });
  /// R55: the list's first items, entered on the new-list page (one per line).
  final List<String> items;
  final String title;
  final TaskPriority priority;
  final TaskVisibility visibility;
  final String? assignedTo;
  final DateTime? targetDate;
  final String recurrence;
  final Map<String,dynamic> rule;

  String? get dateAsSql => targetDate == null ? null :
    '${targetDate!.year}-${targetDate!.month.toString().padLeft(2, '0')}-'
    '${targetDate!.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toEditableFields() => {
    'title': title,
    'priority': priority.name,
    'target_date': dateAsSql,
    'assigned_to': visibility == TaskVisibility.private ? null : assignedTo,
    'recurrence':recurrence,
    'recurrence_rule':rule,
  };
}

/// This widget owns its controller until Flutter has disposed the entire
/// bottom-sheet route, including the dismiss animation. Never create a
/// TextEditingController in the function awaiting showModalBottomSheet.
class TaskEditorSheet extends StatefulWidget {
  const TaskEditorSheet({
    super.key,
    required this.members,
    required this.currentUserId,
    required this.onSave,
    this.spaceId,
    this.existing,
    this.initialTitle = '',
  });
  /// R60: pre-filled list name (voice).
  final String initialTitle;

  final SharedTask? existing;
  final Map<String, String> members;
  final String currentUserId;
  final String? spaceId;
  final Future<void> Function(TaskDraft draft) onSave;

  @override
  State<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<TaskEditorSheet> with FormChangeTracker<TaskEditorSheet> {
  late final TextEditingController _title;
  final TextEditingController _items = TextEditingController();
  @override String get signature=>[_title.text,_items.text,_priority,_visibility,_date,_assignedTo,
    _recurrence,_repeat?.preset,_repeat?.interval,(_repeat?.weekdays.toList()?..sort())?.join(','),
    _repeat?.until,_skipDaysOff,_skipHolidays].join('|');
  late TaskPriority _priority;
  late TaskVisibility _visibility;
  DateTime? _date;
  String? _assignedTo;
  String _recurrence='none';
  Map<String,dynamic> _rule={};
  /// R66: the shared Repeat control's value; null = an older custom schedule
  /// (weekends, working days, days of the month) kept as it is.
  ReminderRepeat? _repeat=const ReminderRepeat();
  bool _skipDaysOff=false,_skipHolidays=false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? widget.initialTitle);
    _priority = widget.existing?.priority ?? TaskPriority.normal;
    _recurrence=widget.existing?.recurrence??'none';
    _rule={...?widget.existing?.rule};
    _repeat=ListRepeat.fromList(_recurrence,_rule);
    _skipDaysOff=_rule['skip_personal_days_off']==true;
    _skipHolidays=_rule['skip_public_holidays']==true||_rule['skip_us_holidays']==true;
    _visibility = widget.existing?.visibility ?? TaskVisibility.shared;
    _date = widget.existing?.targetDate == null ? null :
        DateTime.tryParse(widget.existing!.targetDate!);
    final previous = widget.existing?.assignedTo;
    _assignedTo = previous != null && widget.members.containsKey(previous)
        ? previous : null;
  }

  @override
  void dispose() {
    _title.dispose();
    _items.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    if (title.isEmpty || title.length > 120) {
      setState(() => _error = tr(context, 'emptyTaskTitle'));
      return;
    }
    if (!TaskDateRules.isAllowed(_date, DateTime.now())) {
      setState(() => _error = tr(context, 'pastDateError'));
      return;
    }
    // R66: the shared Repeat control; older custom schedules stay as they were.
    var recurrence=_recurrence;
    final rule=<String,dynamic>{..._rule};
    if(_repeat!=null){
      final (r,fields)=ListRepeat.toList(_repeat!);
      recurrence=r;
      rule..remove('month_days')..addAll(fields);
    }
    rule['anchor']=_rule['anchor']??ChecklistSchedule.day(DateTime.now());
    rule['skip_personal_days_off']=_skipDaysOff;
    rule['skip_public_holidays']=_skipHolidays;
    rule.remove('skip_us_holidays');
    setState((){_saving=true;_error=null;});
    try {
      await widget.onSave(TaskDraft(
        items:[for(final line in _items.text.split('\n'))if(line.trim().isNotEmpty)line.trim().length>200?line.trim().substring(0,200):line.trim()],
        title: title,
        priority: _priority,
        visibility: _visibility,
        assignedTo: _visibility == TaskVisibility.private ? null : _assignedTo,
        targetDate: _date,
        recurrence:recurrence,
        rule:rule,
      ));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _error = tr(context, 'saveFailed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  SpacePeople get _people {
    final partner = widget.members.entries.where((e) => e.key != widget.currentUserId).firstOrNull;
    return SpacePeople(me: widget.currentUserId, partnerId: partner?.key,
      partnerName: (partner?.value ?? 'Partner').split(' ').first);
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final shared = _visibility == TaskVisibility.shared;
    return EditorScaffold(
      title: existing == null ? tt('New list') : tt('Edit list'),
      isNew: existing == null,
      isChanged: () => changed,
      isComplete: () => _title.text.trim().isNotEmpty,
      listenTo: [_title, _items],
      saving: _saving,
      onSave: _save,
      meta: MetaStrip(
        people: _people, dateLabel: tt('Due date'), enabled: !_saving,
        value: MetaValues(shared: shared, belongsTo: _assignedTo, date: _date),
        onChanged: (v) => setState(() {
          if (existing == null) {
            _visibility = v.shared ? TaskVisibility.shared : TaskVisibility.private;
          }
          _assignedTo = _visibility == TaskVisibility.private ? null : v.belongsTo;
          _date = v.date;
        })),
      body: SafeArea(child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(18, 12, 18, 24),
        children: [
          TextField(
            key: const Key('taskTitleInput'),
            controller: _title,
            autofocus: true,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tt('List name *'),
              hintText: tt('Groceries, packing for the trip…'),
              border: OutlineInputBorder(),
            ),
          ),
          if (existing == null) ...[
            const SizedBox(height: 6),
            TextField(
              controller: _items,
              minLines: 4, maxLines: 12,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tt("What's on the list?"),
                hintText: tt('One item per line'),
                alignLabelWithHint: true,
                border: OutlineInputBorder())),
            if (shared) Align(alignment: AlignmentDirectional.centerStart,
              child: PartnerMentionButton(spaceId:widget.spaceId??'', controller:_items, enabled:true)),
            const SizedBox(height: 12),
          ],
          ChoiceRow<TaskPriority>(label: tt('Priority'),
            options: {for (final v in TaskPriority.values) v: tr(context, v.name)},
            icons: const {TaskPriority.low: Icons.south, TaskPriority.normal: Icons.remove,
              TaskPriority.high: Icons.priority_high},
            selected: _priority,
            onSelected: (v) { if (!_saving && v != null) setState(() => _priority = v); }),
          if (_repeat == null) ListTile(contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.repeat),
            title: Text(tt('Custom repeat (kept as it is)')),
            subtitle: Text(tt('Set up before the new Repeat options. Change it to use them.'))
              ,trailing: TextButton(onPressed: _saving ? null : () => setState(() => _repeat = const ReminderRepeat(preset: 'daily')),
                child: Text(tt('Change'))))
          else RepeatControl(value: _repeat!, start: _date ?? DateTime.now(), forList: true, enabled: !_saving,
            onChanged: (r) => setState(() => _repeat = r)),
          if ((_repeat?.repeats ?? true)) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              OptionChip(label: tt('Skip days off'), icon: Icons.beach_access_outlined, value: _skipDaysOff,
                help: tt('Uses the days off of the person it belongs to'), onChanged: (v) => setState(() => _skipDaysOff = v)),
              OptionChip(label: tt('Skip public holidays'), icon: Icons.flag_outlined, value: _skipHolidays,
                help: tt('Holidays where the person it belongs to lives'),
                onChanged: (v) => setState(() => _skipHolidays = v)),
            ]),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(tt(_error!), style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ],
      )),
    );
  }
}
