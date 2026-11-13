import 'package:material_ui/material_ui.dart';

import '../../l10n/onespace_strings.dart';
import 'task_date_rules.dart';
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

  factory SharedTask.fromMap(Map<String, dynamic> row) => SharedTask(
    id: row['id'] as String,
    title: row['title'] as String,
    priority: TaskPriority.values.firstWhere(
      (v) => v.name == row['priority'], orElse: () => TaskPriority.normal),
    status: TaskStatus.values.firstWhere(
      (v) => v.name == row['status'], orElse: () => TaskStatus.open),
    visibility: TaskVisibility.values.firstWhere(
      (v) => v.name == (row['visibility'] ?? 'shared'),
      orElse: () => TaskVisibility.shared),
    createdBy: row['created_by'] as String? ?? '',
    assignedTo: row['assigned_to'] as String?,
    targetDate: row['target_date'] as String?,
    recurrence:(row['recurrence']??'none').toString(),
  );
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
  });
  final String title;
  final TaskPriority priority;
  final TaskVisibility visibility;
  final String? assignedTo;
  final DateTime? targetDate;
  final String recurrence;

  String? get dateAsSql => targetDate == null ? null :
    '${targetDate!.year}-${targetDate!.month.toString().padLeft(2, '0')}-'
    '${targetDate!.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toEditableFields() => {
    'title': title,
    'priority': priority.name,
    'target_date': dateAsSql,
    'assigned_to': visibility == TaskVisibility.private ? null : assignedTo,
    'recurrence':recurrence,
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
    this.existing,
  });

  final SharedTask? existing;
  final Map<String, String> members;
  final String currentUserId;
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
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '');
    _priority = widget.existing?.priority ?? TaskPriority.normal;
    _recurrence=widget.existing?.recurrence??'none';
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
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(TaskDraft(
        title: title,
        priority: _priority,
        visibility: _visibility,
        assignedTo: _visibility == TaskVisibility.private ? null : _assignedTo,
        targetDate: _date,
        recurrence:_recurrence,
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
              Text(existing==null?'Create to-do list':'Edit to-do list',
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
              PartnerMentionButton(spaceId:widget.members.keys.isEmpty?'':widget.currentUserId,
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
               initialValue:_recurrence,
               decoration:const InputDecoration(
                prefixIcon:Icon(Icons.repeat),labelText:'Repeat checklist'),
               items:const [
                DropdownMenuItem(value:'none',child:Text('One-time')),
                DropdownMenuItem(value:'daily',child:Text('Every day')),
                DropdownMenuItem(value:'weekly',child:Text('Every week')),
                DropdownMenuItem(value:'monthly',child:Text('Every month')),
                DropdownMenuItem(value:'yearly',child:Text('Every year')),
               ],
               onChanged:(v)=>setState(()=>_recurrence=v??'none')),
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
                      label: Text(tr(context, 'unassigned')),
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
