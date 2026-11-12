import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  });

  final String id;
  final String title;
  final TaskPriority priority;
  final TaskStatus status;
  final TaskVisibility visibility;
  final String createdBy;
  final String? assignedTo;
  final String? targetDate;

  factory SharedTask.fromMap(Map<String, dynamic> value) {
    return SharedTask(
      id: value['id'] as String,
      title: value['title'] as String,
      priority: TaskPriority.values.firstWhere(
        (item) => item.name == value['priority'],
        orElse: () => TaskPriority.normal,
      ),
      status: TaskStatus.values.firstWhere(
        (item) => item.name == value['status'],
        orElse: () => TaskStatus.open,
      ),
      visibility: TaskVisibility.values.firstWhere(
        (item) => item.name == (value['visibility'] ?? 'shared'),
        orElse: () => TaskVisibility.shared,
      ),
      createdBy: value['created_by'] as String? ?? '',
      assignedTo: value['assigned_to'] as String?,
      targetDate: value['target_date'] as String?,
    );
  }
}

/// RLS determines which tasks are visible. Filtering in the UI is convenience,
/// not a privacy boundary: private rows are excluded by the database itself.
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key, this.onOpenSpace});
  final VoidCallback? onOpenSpace;

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final _client = Supabase.instance.client;
  String? _spaceId;
  Stream<List<Map<String, dynamic>>>? _tasksStream;
  Map<String, String> _memberNames = const {};
  TaskFilter _filter = TaskFilter.open;
  TaskScope _scope = TaskScope.all;
  bool _loadingSpace = true;
  bool _busy = false;
  String? _error;

  String get _me => _client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _loadSpace();
  }

  Future<void> _loadSpace() async {
    if (!mounted) return;
    setState(() {
      _loadingSpace = true;
      _error = null;
    });
    try {
      final memberships = await _client
          .from('space_members')
          .select('space_id')
          .eq('user_id', _me)
          .limit(1);
      if (!mounted) return;
      if (memberships.isEmpty) {
        setState(() {
          _spaceId = null;
          _memberNames = const {};
          _tasksStream = null;
        });
      } else {
        final id = memberships.first['space_id'] as String;
        final members = await _client
            .from('space_members')
            .select('user_id')
            .eq('space_id', id);
        final ids = members
            .map((entry) => entry['user_id'] as String)
            .toList();
        final profiles = await _client
            .from('profiles')
            .select('id, display_name')
            .inFilter('id', ids);
        final names = <String, String>{
          for (final entry in profiles)
            entry['id'] as String:
                (entry['display_name'] as String? ?? 'Member'),
        };
        if (!mounted) return;
        setState(() {
          _spaceId = id;
          _memberNames = names;
          _tasksStream = _client
              .from('tasks')
              .stream(primaryKey: ['id'])
              .eq('space_id', id)
              .order('created_at', ascending: false);
        });
      }
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load your space.');
    } finally {
      if (mounted) setState(() => _loadingSpace = false);
    }
  }

  String _displayName(String id) {
    return id == _me ? 'Me' : (_memberNames[id] ?? 'Partner');
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _taskEditor({SharedTask? existing}) async {
    if (_busy || _spaceId == null) return;

    final controller = TextEditingController(text: existing?.title ?? '');
    var priority = existing?.priority ?? TaskPriority.normal;
    var visibility = existing?.visibility ?? TaskVisibility.shared;
    DateTime? targetDate = existing?.targetDate == null
        ? null
        : DateTime.tryParse(existing!.targetDate!);
    String? assignee = existing?.assignedTo;
    bool saving = false;
    String? dialogError;

    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, updateSheet) => SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing == null ? 'New task' : 'Edit task',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      maxLength: 120,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Task title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('Visibility',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    Wrap(
                      spacing: 8,
                      children: TaskVisibility.values.map((item) {
                        return ChoiceChip(
                          label: Text(item == TaskVisibility.shared
                              ? 'Shared with partner'
                              : 'Only me'),
                          selected: visibility == item,
                          onSelected: saving || existing != null
                              ? null
                              : (_) => updateSheet(() {
                                    visibility = item;
                                    if (item == TaskVisibility.private) {
                                      assignee = null;
                                    }
                                  }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      existing == null
                          ? 'Choose carefully: visibility is fixed after saving.'
                          : visibility == TaskVisibility.private
                              ? 'Only you can see this task.'
                              : 'Both partners can see and edit this task.',
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    const Text('Priority',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    Wrap(
                      spacing: 8,
                      children: TaskPriority.values.map((item) => ChoiceChip(
                            label: Text(item.name),
                            selected: priority == item,
                            onSelected: saving
                                ? null
                                : (_) => updateSheet(() => priority = item),
                          )).toList(),
                    ),
                    const SizedBox(height: 12),
                    if (visibility == TaskVisibility.shared) ...[
                      DropdownButtonFormField<String>(
                        key: ValueKey('assignee-${existing?.id ?? 'new'}'),
                        initialValue: assignee ?? '',
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Assign to',
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: '',
                            child: Text('Unassigned'),
                          ),
                          for (final member in _memberNames.entries)
                            DropdownMenuItem<String>(
                              value: member.key,
                              child: Text(_displayName(member.key)),
                            ),
                        ],
                        onChanged: saving
                            ? null
                            : (value) => updateSheet(() {
                                  assignee = value == null || value.isEmpty
                                      ? null
                                      : value;
                                }),
                      ),
                      const SizedBox(height: 12),
                    ],
                    OutlinedButton.icon(
                      icon: const Icon(Icons.event_outlined),
                      label: Text(targetDate == null
                          ? 'Optional target date'
                          : 'Target: ${_formatDate(targetDate!)}'),
                      onPressed: saving
                          ? null
                          : () async {
                              final picked = await showDatePicker(
                                context: sheetContext,
                                initialDate: targetDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null && sheetContext.mounted) {
                                updateSheet(() => targetDate = picked);
                              }
                            },
                    ),
                    if (targetDate != null)
                      TextButton(
                        onPressed: saving
                            ? null
                            : () => updateSheet(() => targetDate = null),
                        child: const Text('Clear target date'),
                      ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),
                      Text(dialogError!,
                          style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final title = controller.text.trim();
                                if (title.isEmpty) {
                                  updateSheet(() =>
                                      dialogError = 'Enter a task title.');
                                  return;
                                }
                                updateSheet(() {
                                  saving = true;
                                  dialogError = null;
                                });
                                try {
                                  final fields = <String, dynamic>{
                                    'title': title,
                                    'priority': priority.name,
                                    'target_date': targetDate == null
                                        ? null
                                        : _formatDate(targetDate!),
                                    'assigned_to': visibility ==
                                            TaskVisibility.private
                                        ? null
                                        : assignee,
                                  };
                                  if (existing == null) {
                                    await _client.from('tasks').insert({
                                      ...fields,
                                      'space_id': _spaceId,
                                      'created_by': _me,
                                      'status': 'open',
                                      'visibility': visibility.name,
                                    });
                                  } else {
                                    await _client.from('tasks')
                                        .update(fields)
                                        .eq('id', existing.id)
                                        .eq('space_id', _spaceId!);
                                  }
                                  if (sheetContext.mounted) {
                                    Navigator.of(sheetContext).pop();
                                  }
                                } on PostgrestException catch (e) {
                                  if (sheetContext.mounted) {
                                    updateSheet(() => dialogError = e.message);
                                  }
                                } catch (_) {
                                  if (sheetContext.mounted) {
                                    updateSheet(() => dialogError =
                                        'Could not save. Check your connection.');
                                  }
                                } finally {
                                  if (sheetContext.mounted) {
                                    updateSheet(() => saving = false);
                                  }
                                }
                              },
                        child: Text(existing == null
                            ? 'Create task'
                            : 'Save changes'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _changeStatus(SharedTask task, TaskStatus status) async {
    if (_busy || task.status == status || _spaceId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _client.from('tasks').update({'status': status.name})
          .eq('id', task.id).eq('space_id', _spaceId!);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not update task.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelTask(SharedTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel task?'),
        content: const Text(
          'Cancelled tasks remain in history and can be reopened.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel task'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _changeStatus(task, TaskStatus.cancelled);
  }

  bool _isVisible(SharedTask task) {
    final matchingStatus = _filter == TaskFilter.all ||
        task.status.name == _filter.name;
    final matchingScope = _scope == TaskScope.all ||
        task.visibility.name == _scope.name;
    return matchingStatus && matchingScope;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadSpace,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Plans & tasks',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Shared plans and your own private to-dos.'),
          const SizedBox(height: 14),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.red)),
            TextButton.icon(
              onPressed: _loadSpace,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
          if (_loadingSpace)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_spaceId == null)
            _emptySpace()
          else ...[
            FilledButton.icon(
              onPressed: _busy ? null : () => _taskEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Add task'),
            ),
            const SizedBox(height: 16),
            const Text('Show'),
            Wrap(
              spacing: 8,
              children: TaskScope.values.map((scope) => ChoiceChip(
                    label: Text(scope == TaskScope.all
                        ? 'All visible'
                        : scope == TaskScope.shared
                            ? 'Shared'
                            : 'Private'),
                    selected: scope == _scope,
                    onSelected: (_) => setState(() => _scope = scope),
                  )).toList(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: TaskFilter.values.map((filter) => ChoiceChip(
                    label: Text(filter.name),
                    selected: filter == _filter,
                    onSelected: (_) => setState(() => _filter = filter),
                  )).toList(),
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _tasksStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      const Text('Could not refresh your tasks.'),
                      TextButton(
                        onPressed: _loadSpace,
                        child: const Text('Reconnect'),
                      ),
                    ],
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final tasks = snapshot.data!
                    .map(SharedTask.fromMap)
                    .where(_isVisible)
                    .toList();
                if (tasks.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(44),
                    child: Center(child: Text('No tasks in this view.')),
                  );
                }
                return Column(children: tasks.map(_taskTile).toList());
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptySpace() => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.people_outline, size: 42),
              const SizedBox(height: 12),
              const Text('Create or join Our Space first'),
              const SizedBox(height: 8),
              const Text(
                'Your private tasks and shared tasks both live in your space. '
                'Private tasks are visible only to you.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: widget.onOpenSpace,
                child: const Text('Go to Our Space'),
              ),
              TextButton.icon(
                onPressed: _loadSpace,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh membership'),
              ),
            ],
          ),
        ),
      );

  Widget _taskTile(SharedTask task) {
    final cancelled = task.status == TaskStatus.cancelled;
    final completed = task.status == TaskStatus.completed;
    final details = <String>[
      task.visibility == TaskVisibility.private ? 'Private' : 'Shared',
      '${task.priority.name} priority',
      if (task.assignedTo != null)
        'Assigned: ${_displayName(task.assignedTo!)}',
      if (task.targetDate != null) 'Target ${task.targetDate}',
      if (cancelled) 'Cancelled',
    ];
    return Card(
      elevation: 0,
      child: CheckboxListTile(
        value: completed,
        onChanged: cancelled || _busy
            ? null
            : (value) => _changeStatus(
                  task,
                  value == true ? TaskStatus.completed : TaskStatus.open,
                ),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          task.title,
          style: TextStyle(
            decoration: cancelled || completed
                ? TextDecoration.lineThrough
                : null,
            color: cancelled
                ? Colors.red.shade700
                : completed
                    ? Colors.blueGrey
                    : null,
          ),
        ),
        subtitle: Text(details.join(' • ')),
        secondary: PopupMenuButton<String>(
          tooltip: 'Task actions',
          onSelected: (choice) {
            if (choice == 'edit') {
              _taskEditor(existing: task);
            } else if (choice == 'cancel') {
              _cancelTask(task);
            } else if (choice == 'reopen') {
              _changeStatus(task, TaskStatus.open);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit task')),
            if (!cancelled)
              const PopupMenuItem(value: 'cancel', child: Text('Cancel task')),
            if (cancelled || completed)
              const PopupMenuItem(value: 'reopen', child: Text('Reopen task')),
          ],
        ),
      ),
    );
  }
}
