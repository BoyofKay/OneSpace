import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum TaskPriority { low, normal, high }
enum TaskStatus { open, completed, cancelled }
enum TaskFilter { all, open, completed, cancelled }

class SharedTask {
  const SharedTask({
    required this.id,
    required this.title,
    required this.priority,
    required this.status,
    this.targetDate,
  });

  final String id;
  final String title;
  final TaskPriority priority;
  final TaskStatus status;
  final String? targetDate;

  factory SharedTask.fromMap(Map<String, dynamic> value) {
    return SharedTask(
      id: value['id'] as String,
      title: value['title'] as String,
      priority: TaskPriority.values.firstWhere(
        (p) => p.name == value['priority'],
        orElse: () => TaskPriority.normal,
      ),
      status: TaskStatus.values.firstWhere(
        (s) => s.name == value['status'],
        orElse: () => TaskStatus.open,
      ),
      targetDate: value['target_date'] as String?,
    );
  }
}

/// Database-backed tasks shared by the two members of an existing space.
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
  TaskFilter _filter = TaskFilter.open;
  bool _loadingSpace = true;
  bool _busy = false;
  String? _error;

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
      final userId = _client.auth.currentUser!.id;
      final memberships = await _client
          .from('space_members')
          .select('space_id')
          .eq('user_id', userId)
          .limit(1);
      if (!mounted) return;
      if (memberships.isEmpty) {
        setState(() {
          _spaceId = null;
          _tasksStream = null;
        });
      } else {
        final id = memberships.first['space_id'] as String;
        setState(() {
          _spaceId = id;
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
      if (mounted) {
        setState(() => _error = 'Unable to load your shared space.');
      }
    } finally {
      if (mounted) setState(() => _loadingSpace = false);
    }
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<void> _addTask() async {
    if (_spaceId == null || _busy) return;
    final controller = TextEditingController();
    var priority = TaskPriority.normal;
    DateTime? targetDate;
    bool saving = false;
    String? dialogError;

    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (bottomContext) => StatefulBuilder(
          builder: (bottomContext, updateSheet) => SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                24 + MediaQuery.viewInsetsOf(bottomContext).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('New shared task',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'Task title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Priority',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: TaskPriority.values.map((option) {
                        return ChoiceChip(
                          label: Text(option.name),
                          selected: option == priority,
                          onSelected: saving
                              ? null
                              : (_) => updateSheet(() => priority = option),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.event_outlined),
                      label: Text(targetDate == null
                          ? 'Optional target date'
                          : 'Target: ${_formatDate(targetDate!)}'),
                      onPressed: saving
                          ? null
                          : () async {
                              final picked = await showDatePicker(
                                context: bottomContext,
                                initialDate: targetDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null && bottomContext.mounted) {
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
                    const SizedBox(height: 18),
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
                                  await _client.from('tasks').insert({
                                    'space_id': _spaceId,
                                    'created_by': _client.auth.currentUser!.id,
                                    'title': title,
                                    'priority': priority.name,
                                    'status': 'open',
                                    if (targetDate != null)
                                      'target_date': _formatDate(targetDate!),
                                  });
                                  if (bottomContext.mounted) {
                                    Navigator.of(bottomContext).pop();
                                  }
                                } on PostgrestException catch (e) {
                                  if (bottomContext.mounted) {
                                    updateSheet(() => dialogError = e.message);
                                  }
                                } catch (_) {
                                  if (bottomContext.mounted) {
                                    updateSheet(() => dialogError =
                                        'Unable to save task. Check your connection.');
                                  }
                                } finally {
                                  if (bottomContext.mounted) {
                                    updateSheet(() => saving = false);
                                  }
                                }
                              },
                        child: const Text('Save task'),
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
    if (_busy || task.status == status) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _client.from('tasks').update({
        'status': status.name,
      }).eq('id', task.id).eq('space_id', _spaceId!);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not update the task.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelTask(SharedTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this task?'),
        content: const Text(
          'Cancelled tasks remain in your shared history and can be reopened.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep task'),
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
    switch (_filter) {
      case TaskFilter.all:
        return true;
      case TaskFilter.open:
        return task.status == TaskStatus.open;
      case TaskFilter.completed:
        return task.status == TaskStatus.completed;
      case TaskFilter.cancelled:
        return task.status == TaskStatus.cancelled;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Plans & tasks',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Shared plans for the two of you.'),
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
            onPressed: _busy ? null : _addTask,
            icon: const Icon(Icons.add),
            label: const Text('Add task'),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: TaskFilter.values
                .map((filter) => ChoiceChip(
                      label: Text(filter.name),
                      selected: filter == _filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _tasksStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Column(
                  children: [
                    const Text('Could not refresh shared tasks.'),
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
              return Column(
                children: tasks.map(_taskTile).toList(),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _emptySpace() => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.people_outline, size: 42),
              const SizedBox(height: 10),
              const Text('Create or join Our Space first'),
              const SizedBox(height: 8),
              const Text(
                'Your tasks are shared only with your linked partner.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
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
    return Card(
      elevation: 0,
      child: CheckboxListTile(
        value: completed,
        onChanged: cancelled || _busy
            ? null
            : (value) => _changeStatus(
                  task, value == true ? TaskStatus.completed : TaskStatus.open),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          task.title,
          style: TextStyle(
            decoration: cancelled || completed ? TextDecoration.lineThrough : null,
            color: cancelled
                ? Colors.red.shade700
                : completed
                    ? Colors.blueGrey
                    : null,
          ),
        ),
        subtitle: Text([
          '${task.priority.name} priority',
          if (task.targetDate != null) 'Target ${task.targetDate}',
          if (cancelled) 'Cancelled',
        ].join(' • ')),
        secondary: PopupMenuButton<String>(
          tooltip: 'Task actions',
          onSelected: (choice) {
            if (choice == 'cancel') {
              _cancelTask(task);
            } else if (choice == 'reopen') {
              _changeStatus(task, TaskStatus.open);
            }
          },
          itemBuilder: (_) => [
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
