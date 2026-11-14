import 'package:material_ui/material_ui.dart';

import '../../l10n/onespace_strings.dart';
import 'task_date_rules.dart';
import 'checklist_schedule.dart';
import '../mentions/partner_mention_button.dart';

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
  });
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
  });

  final SharedTask? existing;
  final Map<String, String> members;
  final String currentUserId;
  final String? spaceId;
  final Future<void> Function(TaskDraft draft) onSave;

  @override
  State<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<TaskEditorSheet> {
  late final TextEditingController _title;
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
    _title = TextEditingController(text: widget.existing?.title ?? '');
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
    _interval.dispose();_timeZone.dispose();_monthDays.dispose();_excludedDates.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: TaskDateRules.localToday(now),
      initialDate: TaskDateRules.initialForPicker(_date, now),
      lastDate: DateTime(2100),
    );
    if (mounted && picked != null) setState(() => _date = picked);
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

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20, 8, 20, 24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing==null?'Create checklist':'Edit checklist',
                style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                key: const Key('taskTitleInput'),
                controller: _title,
                autofocus: true,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr(context, 'taskTitle'),
                  border: const OutlineInputBorder(),
                ),
              ),
              PartnerMentionButton(spaceId:widget.spaceId??'',
               controller:_title,enabled:_visibility==TaskVisibility.shared),
              const SizedBox(height: 10),
              Text(tr(context, 'visibility'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 8,
                children: TaskVisibility.values.map((value) => ChoiceChip(
                  label: Text(tr(context,
                      value == TaskVisibility.shared ? 'sharedWithPartner' : 'onlyMe')),
                  selected: _visibility == value,
                  onSelected: existing != null || _saving ? null : (_) => setState(() {
                    _visibility = value;
                    if (value == TaskVisibility.private) _assignedTo = null;
                  }),
                )).toList(),
              ),
              const SizedBox(height: 5),
              Text(tr(context, existing == null ? 'chooseVisibility'
                  : _visibility == TaskVisibility.private
                      ? 'privateDescription' : 'sharedDescription'),
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
               initialValue:_scheduleMode,
               decoration:const InputDecoration(
                prefixIcon:Icon(Icons.repeat),labelText:'Repeat checklist'),
               items:const [
                DropdownMenuItem(value:'none',child:Text('One-time')),
                DropdownMenuItem(value:'daily',child:Text('Every day')),
                DropdownMenuItem(value:'weekly',child:Text('Every week (one cycle)')),
                DropdownMenuItem(value:'monthly',child:Text('Every month (one cycle)')),
                DropdownMenuItem(value:'yearly',child:Text('Every year')),
                DropdownMenuItem(value:'weekdays',child:Text('Every weekday (Mon–Fri)')),
                DropdownMenuItem(value:'weekends',child:Text('Weekends only')),
                DropdownMenuItem(value:'workdays',child:Text('My configured working days')),
                DropdownMenuItem(value:'selected_weekdays',child:Text('Selected weekdays')),
                DropdownMenuItem(value:'every_n_days',child:Text('Every N days')),
                DropdownMenuItem(value:'every_n_weeks',child:Text('Every N weeks')),
                DropdownMenuItem(value:'month_days',child:Text('Specific days of each month')),
               ],
               onChanged:(v)=>setState((){
                _scheduleMode=v??'none';
                _recurrence=['none','daily','weekly','monthly','yearly']
                 .contains(_scheduleMode)?_scheduleMode:'daily';
               })),
              if(_scheduleMode=='selected_weekdays'||_scheduleMode=='every_n_weeks')...[
               const SizedBox(height:8),
               const Text('Choose the weekdays:'),
               Wrap(spacing:5,children:[
                for(var d=1;d<=7;d++)FilterChip(
                 label:Text(['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][d-1]),
                 selected:_weekdays.contains(d),onSelected:(on)=>setState((){
                  if(on){_weekdays.add(d);}else{_weekdays.remove(d);}
                 })),
               ]),
              ],
              if(_scheduleMode=='every_n_days'||_scheduleMode=='every_n_weeks')
               TextField(controller:_interval,keyboardType:TextInputType.number,
                decoration:InputDecoration(labelText:_scheduleMode=='every_n_days'
                 ?'Repeat every how many days?':'Repeat every how many weeks?')),
              if(_scheduleMode=='month_days')
               TextField(controller:_monthDays,
                decoration:const InputDecoration(
                 labelText:'Month days (e.g. 1, 15, -1 for last day)')),
              if(_scheduleMode!='none')...[
               const SizedBox(height:10),
               TextField(controller:_timeZone,
                decoration:const InputDecoration(
                 labelText:'Timezone override (optional)',
                 hintText:'America/New_York',
                 helperText:'Leave blank for each responsible partner’s phone timezone')),
               SwitchListTile(value:_skipDaysOff,title:const Text('Skip recorded days off'),
                subtitle:const Text('Uses each person’s Days Off calendar'),
                onChanged:(v)=>setState(()=>_skipDaysOff=v)),
               SwitchListTile(value:_skipUsHolidays,title:const Text('Skip US federal holidays'),
                subtitle:const Text('Federal holidays, including observed weekdays'),
                onChanged:(v)=>setState(()=>_skipUsHolidays=v)),
               TextField(controller:_excludedDates,
                decoration:const InputDecoration(
                 labelText:'Additional dates to skip (optional)',
                 hintText:'2026-12-24, 2027-01-02',
                 helperText:'Comma-separated YYYY-MM-DD; useful for special occasions')),
              ],
              const SizedBox(height: 14),
              Text(tr(context, 'priority'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 8,
                children: TaskPriority.values.map((value) => ChoiceChip(
                  label: Text(tr(context, value.name)),
                  selected: _priority == value,
                  onSelected: _saving ? null :
                      (_) => setState(() => _priority = value),
                )).toList(),
              ),
              if (_visibility == TaskVisibility.shared) ...[
                const SizedBox(height: 14),
                Text(tr(context, 'assignTo'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    ChoiceChip(
                      label: const Text('Both of us'),
                      selected: _assignedTo == null,
                      onSelected: _saving ? null : (_) =>
                          setState(() => _assignedTo = null),
                    ),
                    for (final member in widget.members.entries)
                      ChoiceChip(
                        label: Text(member.key == widget.currentUserId
                            ? tr(context, 'me') : member.value),
                        selected: _assignedTo == member.key,
                        onSelected: _saving ? null :
                          (_) => setState(() => _assignedTo = member.key),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : _selectDate,
                icon: const Icon(Icons.event_outlined),
                label: Text(_date == null ? tr(context, 'optionalDate')
                    : '${tr(context, 'target')}: ${_date!.year}-'
                        '${_date!.month.toString().padLeft(2, '0')}-'
                        '${_date!.day.toString().padLeft(2, '0')}'),
              ),
              if (_date != null)
                TextButton(
                  onPressed: _saving ? null : () => setState(() => _date = null),
                  child: Text(tr(context, 'clearDate')),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('taskSaveButton'),
                  onPressed: _saving ? null : _save,
                  child: Text(tr(context, existing == null
                      ? 'createTask' : 'saveChanges')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
