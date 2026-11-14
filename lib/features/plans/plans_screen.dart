import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/onespace_strings.dart';
import '../../core/current_space_cache.dart';
import '../../core/performance_timings.dart';
import 'task_editor_sheet.dart';
import 'task_checklist_panel.dart';
import 'checklist_list_loader.dart';
import '../sharing/object_permissions.dart';
import '../sharing/private_share_button.dart';
import '../sharing/share_grant_watcher.dart';
export 'task_editor_sheet.dart'
    show SharedTask, TaskPriority, TaskStatus, TaskVisibility, TaskFilter, TaskScope;

/// RLS determines which tasks are visible. Filtering in the UI is convenience,
/// not a privacy boundary: private rows are excluded by the database itself.
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key, this.onOpenSpace, this.focusTaskId});
  final VoidCallback? onOpenSpace;
  final String? focusTaskId;

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final _client = Supabase.instance.client;
  String? _spaceId;
  Stream<List<Map<String, dynamic>>>? _tasksStream;
  StreamSubscription<List<Map<String, dynamic>>>? _shareWatcher;
  Map<String, String> _memberNames = const {};
  TaskFilter _filter = TaskFilter.open;
  bool _todayOnly = false;
  // Only mount per-cycle realtime streams for an expanded checklist.
  final Set<String> _expandedLists = <String>{};
  TaskScope _scope = TaskScope.all;
  bool _loadingSpace = true;
  bool _busy = false;
  String? _error;

  String get _me => _client.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    if(widget.focusTaskId!=null)_expandedLists.add(widget.focusTaskId!);
    _loadSpace();
  }

  @override
  void dispose() {
    _shareWatcher?.cancel();
    super.dispose();
  }

  void _watchGrants(String id) {
    _shareWatcher?.cancel();
    _shareWatcher = watchObjectShares(
      client: _client,
      spaceId: id,
      objectType: 'task',
      onChanged: () {
        if (!mounted || _spaceId != id) return;
        setState(() => _tasksStream = _client.from('tasks')
            .stream(primaryKey: ['id'])
            .eq('space_id', id)
            .order('created_at', ascending: false));
      },
    );
  }

  final Stopwatch _firstTasksClock = Stopwatch();
  bool _tasksFirstDataRecorded = false;

  Future<void> _loadSpace() async {
    if (!mounted) return;
    setState(() {
      _loadingSpace = true;
      _error = null;
    });
    try {
      final userId=_client.auth.currentUser?.id;
      if(userId==null){
        if(mounted)setState((){
          _spaceId=null;
          _tasksStream=null;
          _memberNames=const {};
          _error='Sign in again to load your checklists.';
        });
        return;
      }
      final id = await CurrentSpaceCache.instance.get();
      if (!mounted || _client.auth.currentUser?.id!=userId) return;
      if (id == null) {
        setState(() {
          _spaceId = null;
          _memberNames = const {};
          _tasksStream = null;
        });
        return;
      }
      // Home has already fetched partner names in the same secure snapshot.
      // Reuse them to avoid two more Seoul network round trips.
      final cachedNames = CurrentSpaceCache.instance.memberNamesFor(id);
      _firstTasksClock..reset()..start();
      _tasksFirstDataRecorded = false;
      setState(() {
        _spaceId = id;
        _memberNames = {
          ...?cachedNames,
          _me: tr(context, 'me'),
        };
        _tasksStream = _client.from('tasks')
            .stream(primaryKey: ['id'])
            .eq('space_id', id)
            .order('created_at', ascending: false);
      });
      _watchGrants(id);
      // Direct Plans entry (before Home completes) still has a safe fallback.
      if (cachedNames == null) unawaited(_loadMemberNames(id));
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr(context, 'loadFailed'));
    } finally {
      if (mounted) setState(() => _loadingSpace = false);
    }
  }

  Future<void> _loadMemberNames(String id) async {
    try {
      final members = await _client.from('space_members')
          .select('user_id').eq('space_id', id);
      final ids = members.map((entry) => entry['user_id'] as String).toList();
      if (ids.isEmpty) return;
      final profiles = await _client.from('profiles')
          .select('id,display_name').inFilter('id', ids);
      final names = {
        for (final memberId in ids)
          memberId: profiles.where((profile) => profile['id'] == memberId)
              .map((profile) => profile['display_name'] as String? ?? 'Partner')
              .firstOrNull ?? 'Partner',
      };
      if (mounted && _spaceId == id) {
        setState(() => _memberNames = names);
      }
    } catch (_) {
      // Missing optional names must not stall access to tasks.
    }
  }

  String _displayName(String id) {
    return id == _me ? (_memberNames[id] ?? tr(context, 'me'))
        : (_memberNames[id] ?? tr(context, 'partner'));
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
        spaceId:spaceId,
        onSave: (draft) async {
          final fields = draft.toEditableFields();
          if (existing == null) {
            final created = await _client.from('tasks').insert({
              ...fields,
              'space_id': spaceId,
              'created_by': _me,
              'status': 'open',
              'visibility': draft.visibility.name,
            }).select('id').single();
            if (mounted) setState(() => _expandedLists.add(created['id'].toString()));
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
    final today=DateTime.now();
    final day=[
      today.year.toString().padLeft(4,'0'),
      today.month.toString().padLeft(2,'0'),
      today.day.toString().padLeft(2,'0'),
    ].join('-');
    final due=task.status==TaskStatus.open && task.targetDate!=null &&
      task.targetDate!.compareTo(day)<=0;
    return matchingStatus && matchingScope && (!_todayOnly||due);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:AppBar(title:const Text('To-do and Checklists'),actions:[
       IconButton(tooltip:'Filters',icon:const Icon(Icons.tune_outlined),
        onPressed:()=>showModalBottomSheet<void>(context:context,
         showDragHandle:true,builder:(_)=>StatefulBuilder(
          builder:(ctx,rebuild)=>SafeArea(child:Padding(
           padding:const EdgeInsets.all(18),child:Column(
            mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,
            children:[
             Text('Filters',style:Theme.of(ctx).textTheme.titleLarge),
             const SizedBox(height:12),
             const Text('Visibility'),
             Wrap(spacing:8,children:[
              for(final v in TaskScope.values)ChoiceChip(
               label:Text(v==TaskScope.all?'All visible':v.name),
               selected:_scope==v,
               onSelected:(_){setState(()=>_scope=v);rebuild((){});}),
             ]),
             const SizedBox(height:12),
             const Text('List status'),
             Wrap(spacing:8,children:[
              for(final v in TaskFilter.values)ChoiceChip(
               label:Text(v.name),selected:_filter==v,
               onSelected:(_){setState(()=>_filter=v);rebuild((){});}),
             ]),
             const SizedBox(height:12),
             SwitchListTile(title:const Text('Due today / overdue'),
              value:_todayOnly,
              onChanged:(v){setState(()=>_todayOnly=v);rebuild((){});}),
            ]))))),
       ),
      ]),
      body:RefreshIndicator(
      onRefresh: _loadSpace,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('To-do and Checklists',
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
          else if (_me.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Your session is unavailable. Sign in to open checklists.'),
            )
          else if (_spaceId == null)
            _emptySpace()
          else ...[
            FilledButton.icon(
              onPressed: _busy ? null : () => _taskEditor(),
              icon: const Icon(Icons.add),
              label:const Text('Create checklist'),
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _tasksStream,
              builder: (context, snapshot) {
                if (snapshot.hasData && !_tasksFirstDataRecorded) {
                  _tasksFirstDataRecorded = true;
                  _firstTasksClock.stop();
                  PerformanceTimings.instance.record(
                    'Tasks first data', _firstTasksClock.elapsed);
                }
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
                final parsed=ChecklistListLoader.fromRows(snapshot.data!);
                final visible=<SharedTask>[];
                var viewFailures=parsed.skippedRows;
                for(final task in parsed.items){
                  try{
                    if(_isVisible(task))visible.add(task);
                  }catch(_){
                    viewFailures++;
                  }
                }
                final tiles=<Widget>[];
                for(final task in visible){
                  try{
                    tiles.add(_taskTile(task));
                  }catch(_){
                    viewFailures++;
                    // Never allow a single old checklist to crash the screen.
                  }
                }
                return Column(children:[
                  if(viewFailures>0)Card(
                    child:Padding(
                      padding:const EdgeInsets.all(12),
                      child:Column(children:[
                        const Text('Some older checklists could not be displayed. '
                          'Your saved data has not been deleted.'),
                        TextButton.icon(
                          onPressed:_loadSpace,
                          icon:const Icon(Icons.refresh),
                          label:const Text('Retry checklists'),
                        ),
                      ]),
                    ),
                  ),
                  if(tiles.isEmpty)
                    const Padding(
                      padding:EdgeInsets.all(44),
                      child:Center(child:Text('No checklists in this view.')),
                    )
                  else ...tiles,
                ]);
              },
            ),
          ],
        ],
      ),
    ));
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
      ExpansionTile(
       key:PageStorageKey<String>('todo-'+task.id),
       initiallyExpanded:_expandedLists.contains(task.id),
       onExpansionChanged:(expanded)=>setState((){
        if(expanded){_expandedLists.add(task.id);}else{_expandedLists.remove(task.id);}
       }),
       leading:Icon(cancelled?Icons.cancel_outlined:
        completed?Icons.task_alt_outlined:Icons.format_list_bulleted_outlined),
       title:Text(task.title,style:TextStyle(
        decoration:cancelled||completed?TextDecoration.lineThrough:null,
        color:cancelled?Theme.of(context).colorScheme.error:null)),
       subtitle:Text(details.join(' • ')),
       trailing:!canEdit?const Icon(Icons.lock_outline):
        PopupMenuButton<String>(
         tooltip:'List actions',
         onSelected:(choice){
          if(choice=='edit'){_taskEditor(existing:task);}
          if(choice=='cancel'){_cancelTask(task);}
          if(choice=='complete'){_changeStatus(task,TaskStatus.completed);}
          if(choice=='reopen'){_changeStatus(task,TaskStatus.open);}
         },
         itemBuilder:(_)=>[
          const PopupMenuItem(value:'edit',child:Text('Edit list')),
          if(!cancelled&&!completed)
           const PopupMenuItem(value:'complete',child:Text('Mark list complete')),
          if(!cancelled)
           const PopupMenuItem(value:'cancel',child:Text('Cancel list')),
          if(cancelled||completed)
           const PopupMenuItem(value:'reopen',child:Text('Reopen list')),
         ]),
       childrenPadding:const EdgeInsets.fromLTRB(15,2,15,14),
       children:[
        if(_expandedLists.contains(task.id)) TaskChecklistPanel(
         key:ValueKey(task.id),taskId:task.id,recurrence:task.recurrence,
         rule:task.rule,
         canManage:canEdit&&!cancelled,
         canComplete:canEdit&&!cancelled&&
          (task.assignedTo==null||task.assignedTo==_me)),
       ],
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
