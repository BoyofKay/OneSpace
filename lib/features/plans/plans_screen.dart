import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/onespace_strings.dart';
import 'task_editor_sheet.dart';
import '../sharing/object_permissions.dart';
import '../sharing/private_share_button.dart';
export 'task_editor_sheet.dart'
    show SharedTask, TaskPriority, TaskStatus, TaskVisibility, TaskFilter, TaskScope;

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
        final knownNames = <String, String>{
          for (final entry in profiles)
            entry['id'] as String:
                (entry['display_name'] as String? ?? 'Member'),
        };
        // Every space member is a valid assignment choice even if their
        // profile is temporarily missing or unreadable.
        final names = <String, String>{
          for (final memberId in ids)
            memberId: knownNames[memberId] ?? 'Partner',
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

  Future<void> _taskEditor({SharedTask? existing}) async {
    final spaceId = _spaceId;
    if (_busy || spaceId == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => TaskEditorSheet(
        existing: existing,
        members: _memberNames,
        currentUserId: _me,
        onSave: (draft) async {
          final fields = draft.toEditableFields();
          if (existing == null) {
            await _client.from('tasks').insert({
              ...fields,
              'space_id': spaceId,
              'created_by': _me,
              'status': 'open',
              'visibility': draft.visibility.name,
            });
          } else {
            final rows = await _client.from('tasks')
              .update(fields)
              .eq('id', existing.id)
              .eq('space_id', spaceId)
              .select('id');
            if (rows.isEmpty) {
              throw StateError('Task is no longer available for editing.');
            }
          }
        },
      ),
    );
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
          Text(tr(context, 'plansAndTasks'),
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(tr(context, 'tasksSubtitle')), 
          const SizedBox(height: 14),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.red)),
            TextButton.icon(
              onPressed: _loadSpace,
              icon: const Icon(Icons.refresh),
              label: Text(tr(context, 'retry')),
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
              label: Text(tr(context, 'addTask')),
            ),
            const SizedBox(height: 16),
            const Text('Show'),
            Wrap(
              spacing: 8,
              children: TaskScope.values.map((scope) => ChoiceChip(
                    label: Text(scope == TaskScope.all
                        ? tr(context, 'allVisible')
                        : scope == TaskScope.shared
                            ? tr(context, 'shared')
                            : tr(context, 'private')),
                    selected: scope == _scope,
                    onSelected: (_) => setState(() => _scope = scope),
                  )).toList(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: TaskFilter.values.map((filter) => ChoiceChip(
                    label: Text(tr(context, filter.name)),
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
              Text(tr(context, 'noSpace')),
              const SizedBox(height: 8),
              const Text(
                'Your private tasks and shared tasks both live in your space. '
                'Private tasks are visible only to you.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: widget.onOpenSpace,
                child: Text(tr(context, 'goToSpace')),
              ),
              TextButton.icon(
                onPressed: _loadSpace,
                icon: const Icon(Icons.refresh),
                label: Text(tr(context, 'refreshMembership')),
              ),
            ],
          ),
        ),
      );

  Widget _taskTile(SharedTask task) {
    final cancelled = task.status == TaskStatus.cancelled;
    final completed = task.status == TaskStatus.completed;
    final canEdit = ObjectPermissions.canEdit(
      visibility: task.visibility.name,
      createdBy: task.createdBy,
      userId: _me,
    );
    final canShare = ObjectPermissions.canManagePrivateShare(
      visibility: task.visibility.name,
      createdBy: task.createdBy,
      userId: _me,
    );
    final details = <String>[
      task.visibility == TaskVisibility.private ? tr(context, 'private') : tr(context, 'shared'),
      '${tr(context, task.priority.name)} ${tr(context, 'priority')}',
      if (task.assignedTo != null)
        'Assigned: ${_displayName(task.assignedTo!)}',
      if (task.targetDate != null) 'Target ${task.targetDate}',
      if (cancelled) tr(context, 'cancelled'),
      if (!canEdit) tr(context, 'viewOnly'),
    ];
    return Card(
      elevation: 0,
      child: Column(
        children: [
      CheckboxListTile(
        value: completed,
        onChanged: !canEdit || cancelled || _busy
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
        secondary: !canEdit
            ? const Icon(Icons.lock_outline)
            : PopupMenuButton<String>(
          tooltip: tr(context, 'taskActions'),
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
            PopupMenuItem(value: 'edit', child: Text(tr(context, 'edit'))),
            if (!cancelled)
              PopupMenuItem(value: 'cancel', child: Text(tr(context, 'cancelTask'))),
            if (cancelled || completed)
              PopupMenuItem(value: 'reopen', child: Text(tr(context, 'reopenTask'))),
          ],
        ),
      ),
        if (canShare)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: PrivateShareButton(
              objectType: 'task',
              objectId: task.id,
            ),
          ),
        ],
      ),
    );
  }
}
