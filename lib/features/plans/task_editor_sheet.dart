import '../../core/form_kit.dart';
import '../../core/editor_scaffold.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/onespace_strings.dart';
import 'task_date_rules.dart';
import 'checklist_schedule.dart';
import '../mentions/partner_mention_button.dart';
import 'package:onespace/l10n/phrases.dart';

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
    _recurrence,_scheduleMode,_interval.text,_timeZone.text,_monthDays.text,_excludedDates.text,
    (_weekdays.toList()..sort()).join(','),_skipDaysOff,_skipUsHolidays].join('|');
  late TaskPriority _priority;
  late TaskVisibility _visibility;
  DateTime? _date;
  String? _assignedTo;
  String _recurrence='none';
  String _scheduleMode='none';
  Map<String,dynamic> _rule={};
  late final TextEditingController _interval,_timeZone,_monthDays,_excludedDates;
  final Set<int> _weekdays={};
  bool _skipDaysOff=false,_skipUsHolidays=false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? widget.initialTitle);
    _priority = widget.existing?.priority ?? TaskPriority.normal;
    _recurrence=widget.existing?.recurrence??'none';
    _rule={...?widget.existing?.rule};
    _scheduleMode=ChecklistSchedule.mode(_rule,_recurrence);
    _interval=TextEditingController(text:(_rule['interval']??1).toString());
    _timeZone=TextEditingController(text:(_rule['timezone']??'').toString());
    _monthDays=TextEditingController(text:(_rule['month_days'] is List?
      (_rule['month_days'] as List).join(', '):'1'));
    _excludedDates=TextEditingController(text:(_rule['exclude_dates'] is List?
      (_rule['exclude_dates'] as List).join(', '):''));
    _weekdays.addAll((_rule['weekdays'] as List? ??const [])
      .whereType<num>().map((x)=>x.toInt()));
    _skipDaysOff=_rule['skip_personal_days_off']==true;
    _skipUsHolidays=_rule['skip_us_holidays']==true;
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
    _interval.dispose();_timeZone.dispose();_monthDays.dispose();_excludedDates.dispose();
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
    final interval=int.tryParse(_interval.text.trim())??1;
    if(interval<1||interval>365){
     setState(()=>_error='Repeating interval must be 1–365.');return;
    }
    if((_scheduleMode=='selected_weekdays'||_scheduleMode=='every_n_weeks')&&_weekdays.isEmpty){
     setState(()=>_error='Select at least one weekday.');return;
    }
    final days=_monthDays.text.split(',').map((s)=>int.tryParse(s.trim())).toList();
    if(_scheduleMode=='month_days'&&(days.isEmpty||days.any(
       (n)=>n==null||n==0||n < -1||n>31))){
      setState(()=>_error='Use month dates 1–31 or -1 for the last day.');return;
    }
    final excluded=_excludedDates.text.split(',').map((x)=>x.trim())
       .where((x)=>x.isNotEmpty).toList();
    if(excluded.any((x){
      final parsed=DateTime.tryParse(x);
      return x.length!=10||parsed==null||ChecklistSchedule.day(parsed)!=x;
    })){
      setState(()=>_error='Excluded dates must use YYYY-MM-DD.');return;
    }
    final zone=_timeZone.text.trim();
    if(zone.isNotEmpty&&!ChecklistSchedule.validTimeZone(zone)){
      setState(()=>_error='Enter a valid IANA timezone such as America/New_York.');
      return;
    }
    final rule=<String,dynamic>{
      if(_scheduleMode!='none')'mode':_scheduleMode,
      'interval':interval,
      'anchor':_rule['anchor']??ChecklistSchedule.day(DateTime.now()),
      'weekdays':_weekdays.toList()..sort(),
      'month_days':days.whereType<int>().toList(),
      if(zone.isNotEmpty)'timezone':zone,
      'skip_personal_days_off':_skipDaysOff,
      'skip_us_holidays':_skipUsHolidays,
      'exclude_dates':excluded,
    };
    setState((){_saving=true;_error=null;});
    try {
      await widget.onSave(TaskDraft(
        items:[for(final line in _items.text.split('\n'))if(line.trim().isNotEmpty)line.trim().length>200?line.trim().substring(0,200):line.trim()],
        title: title,
        priority: _priority,
        visibility: _visibility,
        assignedTo: _visibility == TaskVisibility.private ? null : _assignedTo,
        targetDate: _date,
        recurrence:_recurrence,
        rule:rule,
      ));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _error = tr(context, 'saveFailed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const _repeatLabels = {
    'none': 'One-time', 'daily': 'Every day', 'weekly': 'Every week',
    'monthly': 'Every month', 'yearly': 'Every year', 'weekdays': 'Weekdays (Mon–Fri)',
    'weekends': 'Weekends', 'workdays': 'My working days',
    'selected_weekdays': 'Selected weekdays', 'every_n_days': 'Every N days',
    'every_n_weeks': 'Every N weeks', 'month_days': 'Specific days of the month',
  };

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
      listenTo: [_title, _items, _interval, _timeZone, _monthDays, _excludedDates],
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
          if (shared) Align(alignment: AlignmentDirectional.centerStart,
            child: PartnerMentionButton(spaceId:widget.spaceId??'', controller:_title, enabled:true)),
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
            const SizedBox(height: 12),
          ],
          ChoiceRow<TaskPriority>(label: tt('Priority'),
            options: {for (final v in TaskPriority.values) v: tr(context, v.name)},
            icons: const {TaskPriority.low: Icons.south, TaskPriority.normal: Icons.remove,
              TaskPriority.high: Icons.priority_high},
            selected: _priority,
            onSelected: (v) { if (!_saving && v != null) setState(() => _priority = v); }),
          ChoicePickerField<String>(label: tt('Repeat'), icon: Icons.repeat,
            options: _repeatLabels, selected: _scheduleMode,
            onSelected: (v) => setState(() {
              _scheduleMode = v ?? 'none';
              _recurrence = ['none','daily','weekly','monthly','yearly']
                .contains(_scheduleMode) ? _scheduleMode : 'daily';
            })),
          if (_scheduleMode == 'selected_weekdays' || _scheduleMode == 'every_n_weeks') ...[
            Text(tt('On these days'), style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var d = 1; d <= 7; d++) FilterChip(
                label: Text(tt(['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][d-1])),
                selected: _weekdays.contains(d),
                onSelected: (on) => setState(() { if (on) { _weekdays.add(d); } else { _weekdays.remove(d); } })),
            ]),
            const SizedBox(height: 14),
          ],
          if (_scheduleMode == 'every_n_days' || _scheduleMode == 'every_n_weeks') Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextField(controller: _interval, keyboardType: TextInputType.number,
              decoration: InputDecoration(border: const OutlineInputBorder(),
                labelText: _scheduleMode == 'every_n_days' ? tt('Every how many days? *') : tt('Every how many weeks? *')))),
          if (_scheduleMode == 'month_days') Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextField(controller: _monthDays,
              decoration: InputDecoration(border: OutlineInputBorder(),
                labelText: tt('Days of the month *'), hintText: tt('1, 15, -1 for the last day')))),
          if (_scheduleMode != 'none') ...[
            Wrap(spacing: 8, runSpacing: 6, children: [
              OptionChip(label: tt('Skip days off'), icon: Icons.beach_access_outlined, value: _skipDaysOff,
                help: tt('Uses each person’s Days off'), onChanged: (v) => setState(() => _skipDaysOff = v)),
              OptionChip(label: tt('Skip US holidays'), icon: Icons.flag_outlined, value: _skipUsHolidays,
                help: tt('Federal holidays, including observed weekdays'),
                onChanged: (v) => setState(() => _skipUsHolidays = v)),
            ]),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(tt('Advanced repeat')),
              subtitle: Text(tt('Time zone and dates to skip')),
              children: [
                TextField(controller: _timeZone,
                  decoration: InputDecoration(border: OutlineInputBorder(),
                    labelText: tt('Time zone (optional)'), hintText: tt('America/New_York'),
                    helperText: tt('Blank = each person’s phone time zone'))),
                const SizedBox(height: 10),
                TextField(controller: _excludedDates,
                  decoration: InputDecoration(border: OutlineInputBorder(),
                    labelText: tt('Dates to skip (optional)'), hintText: '2026-12-24, 2027-01-02')),
                const SizedBox(height: 8),
              ]),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(tt(_error!), style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ],
      )),
    );
  }
}
