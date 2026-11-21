import '../../core/item_menu.dart';
import '../../core/record_list_top_actions.dart';
import '../../core/editor_scaffold.dart';
import '../../core/status_look.dart';
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/onespace_strings.dart';
import '../../core/current_space_cache.dart';
import '../../core/app_env.dart';
import '../../core/performance_timings.dart';
import 'task_editor_sheet.dart';
import 'task_checklist_panel.dart';
import 'checklist_list_loader.dart';
import '../sharing/object_permissions.dart';
import '../sharing/private_share_button.dart';
import '../sharing/share_grant_watcher.dart';
import 'package:onespace/l10n/phrases.dart';
export 'task_editor_sheet.dart'
    show SharedTask, TaskPriority, TaskStatus, TaskVisibility, TaskFilter, TaskScope;

/// RLS determines which tasks are visible. Filtering in the UI is convenience,
/// not a privacy boundary: private rows are excluded by the database itself.
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key, this.onOpenSpace, this.focusTaskId,
    this.startNewTask = false, this.newListTitle = ''});
  /// R60: name for the new list when opened by voice.
  final String newListTitle;
  final VoidCallback? onOpenSpace;
  final String? focusTaskId;
  /// R51 Quick add: open the new to-do editor as soon as the space is known.
  final bool startNewTask;

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final _client = Supabase.instance.client;
  String? _spaceId;
  bool _personalScopeReady = false;
  Stream<List<Map<String, dynamic>>>? _tasksStream;
  StreamSubscription<List<Map<String, dynamic>>>? _shareWatcher;
  Map<String, String> _memberNames = const {};
  TaskFilter _filter = TaskFilter.open;
  bool _todayOnly = false;
  // Only mount per-cycle realtime streams for an expanded checklist.
  final Set<String> _expandedLists = <String>{};
  TaskScope _scope = TaskScope.all;
  String _query = '';
  List<FilterGroupSpec> _filterGroups()=>[
    FilterGroupSpec(id:'status',label:tt('Lists'),options:const {'open':'Open','completed':'Completed','cancelled':'Cancelled','all':'All'},
      selected:_filter.name,defaultValue:'open'),
    FilterGroupSpec(id:'who',label:tt('Who can see'),options:const {'all':'All','shared':'Shared','private':'Only me'},
      selected:_scope.name,defaultValue:'all'),
    FilterGroupSpec(id:'due',label:tt('Due'),options:const {'any':'Any time','today':'Today or overdue'},
      selected:_todayOnly?'today':'any',defaultValue:'any'),
  ];
  bool _loadingSpace = true;
  bool _busy = false;
  String? _error;

  String get _me => _client.auth.currentUser?.id ?? '';

  bool _startedNewTask = false;

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
        setState(() => _tasksStream = OneSpaceEnv.usesLegacyBackend
           ? _client.from('tasks').stream(primaryKey: ['id'])
               .eq('space_id', id).order('created_at', ascending: false)
           : _client.from('tasks').stream(primaryKey: ['id'])
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
      String? id = await CurrentSpaceCache.instance.get();
      bool personalReady = false;
      if (!OneSpaceEnv.usesLegacyBackend) {
        final scopes = await _client.rpc('my_storage_scopes');
        if (scopes is! Map || scopes['private_space_id']?.toString()!=userId) {
          throw StateError('Personal scope unavailable');
        }
        id = scopes['shared_space_id']?.toString();
        personalReady = true;
      }
      if (!mounted || _client.auth.currentUser?.id!=userId) return;
      if (id == null && OneSpaceEnv.usesLegacyBackend) {
        setState(() {
          _spaceId = null;
          _memberNames = const {};
          _tasksStream = null;
        });
        return;
      }
      // Home has already fetched partner names in the same secure snapshot.
      // Reuse them to avoid two more Seoul network round trips.
      final cachedNames = id==null
        ? null : CurrentSpaceCache.instance.memberNamesFor(id);
      _firstTasksClock..reset()..start();
      _tasksFirstDataRecorded = false;
      setState(() {
        _spaceId = id;
        _personalScopeReady = personalReady;
        _memberNames = {
          ...?cachedNames,
          _me: tr(context, 'me'),
        };
        _tasksStream = OneSpaceEnv.usesLegacyBackend
          ? _client.from('tasks').stream(primaryKey: ['id'])
             .eq('space_id', id!).order('created_at', ascending: false)
          : _client.from('tasks').stream(primaryKey: ['id'])
             .order('created_at', ascending: false);
      });
      if(id!=null) _watchGrants(id);
      if (widget.startNewTask && !_startedNewTask) {
        _startedNewTask = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_taskEditor());
        });
      }
      // Direct Plans entry (before Home completes) still has a safe fallback.
      if (cachedNames == null && id!=null) unawaited(_loadMemberNames(id));
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
    if (_busy || (!(_personalScopeReady) && spaceId == null) || !mounted) return;
    // R55: a full page (no bottom sheet), starting with the list's items.
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => TaskEditorSheet(
        existing: existing,
        initialTitle: existing == null ? widget.newListTitle : '',
        members: _memberNames,
        currentUserId: _me,
        spaceId:spaceId,
        allowShared: spaceId != null,
        onSave: (draft) async {
          final fields = draft.toEditableFields();
          if (existing == null) {
            if(draft.visibility==TaskVisibility.shared && spaceId==null)
              throw StateError('Connect with a partner to share a checklist.');
            final created = await _client.from('tasks').insert({
              ...fields,
              if (!OneSpaceEnv.usesLegacyBackend &&
                  draft.visibility==TaskVisibility.private)
                'private_space_id':_me
              else 'space_id': spaceId,
              'created_by': _me,
              'status': 'open',
              'visibility': draft.visibility.name,
            }).select('id').single();
            if (draft.items.isNotEmpty) {
              await _client.from('task_checklist_items').insert([
                for (final item in draft.items)
                  {'task_id': created['id'], 'title': item},
              ]);
            }
            if (mounted) setState(() => _expandedLists.add(created['id'].toString()));
          } else {
            var query = _client.from('tasks')
              .update(fields).eq('id', existing.id);
            if (OneSpaceEnv.usesLegacyBackend) query=query.eq('space_id',spaceId!);
            final rows=await query.select('id');
            if (rows.isEmpty) {
              throw StateError('Task is no longer available for editing.');
            }
          }
        },
      ),
    ));
  }

  Future<void> _changeStatus(SharedTask task, TaskStatus status) async {
    if (_busy || task.status == status ||
      (OneSpaceEnv.usesLegacyBackend && _spaceId == null)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var query=_client.from('tasks').update({'status': status.name})
        .eq('id',task.id);
      if (OneSpaceEnv.usesLegacyBackend) query=query.eq('space_id',_spaceId!);
      await query.select('id');
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
        title: Text(tt('Cancel task?')),
        content: Text(
          tt('Cancelled tasks remain in history and can be reopened.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tt('Keep')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tt('Cancel task')),
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
    final matchingQuery = _query.isEmpty || task.title.toLowerCase().contains(_query);
    return matchingStatus && matchingScope && matchingQuery && (!_todayOnly||due);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:AppBar(title:Text(tt('To-do lists')),actions:[
       RecordListTopActions(
        historyKinds:const ['task'],historyTitle:tt('To-do lists'),
        showHistory:false,onToggleHistory:(){},allowRemoved:false,
        groups:_filterGroups(),
        onApply:(v)=>setState((){
         _filter=TaskFilter.values.byName(v['status']!);
         _scope=TaskScope.values.byName(v['who']!);
         _todayOnly=v['due']=='today';
        })),
      ],bottom:filterShowingBar(_filterGroups(),removed:false,onClear:()=>setState((){
        _filter=TaskFilter.open;_scope=TaskScope.all;_todayOnly=false;}))),
      floatingActionButton:(_spaceId==null&&!_personalScopeReady)||_me.isEmpty?null:
        AddFab(label:tt('New list'),onPressed:_busy?null:()=>_taskEditor()),
      body:RefreshIndicator(
      onRefresh: _loadSpace,
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(20,16,20,96),
        children: [
          TextField(
            onChanged:(v)=>setState(()=>_query=v.trim().toLowerCase()),
            decoration:InputDecoration(
              prefixIcon:Icon(Icons.search),
              labelText:tt('Search lists'),
              border:OutlineInputBorder())),
          const SizedBox(height: 14),
          if (_error != null) ...[
            Text(tt(_error!), style: const TextStyle(color: Colors.red)),
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
            Padding(
              padding: EdgeInsets.all(20),
              child: Text(tt('Your session is unavailable. Sign in to open checklists.')),
            )
          else if (_spaceId == null && !_personalScopeReady)
            _emptySpace()
          else ...[
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
                      Text(tt('Could not refresh your tasks.')),
                      TextButton(
                        onPressed: _loadSpace,
                        child: Text(tt('Reconnect')),
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
                        Text(tt('Some older checklists could not be displayed. '
                          'Your saved data has not been deleted.')),
                        TextButton.icon(
                          onPressed:_loadSpace,
                          icon:const Icon(Icons.refresh),
                          label:Text(tt('Retry checklists')),
                        ),
                      ]),
                    ),
                  ),
                  if(tiles.isEmpty)
                    Padding(
                      padding:EdgeInsets.all(44),
                      child:Center(child:Text(tt('No checklists in this view.'))),
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
              Text(
                tt('Your private tasks and shared tasks both live in your space. '
                'Private tasks are visible only to you.'),
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
    final canShare = (OneSpaceEnv.usesLegacyBackend ||
       task.privateSpaceId==null) &&
       ObjectPermissions.canManagePrivateShare(
       visibility: task.visibility.name,
       createdBy: task.createdBy,
       userId: _me,
    );
    // R55: only what helps decide what to do next; no "Shared · Normal priority" noise.
    final details = <String>[
      if (task.visibility == TaskVisibility.private) 'Only me',
      if (task.assignedTo != null)
        task.assignedTo == _me ? 'For me' : 'For ${_displayName(task.assignedTo!)}',
      if (task.targetDate != null) 'Due ${task.targetDate}',
      if (task.recurrence != 'none') 'Repeats',
      if (task.priority == TaskPriority.high)
        tr(context, task.priority.name),
      if (cancelled) tr(context, 'cancelled'),
      if (!canEdit) tr(context, 'viewOnly'),
    ];
    return Card(
      elevation: 0,
      child: Column(
        children: [
      ExpansionTile(
       // Do not use PageStorageKey here: ExpansionTile persists a bool,
       // while a nested EditableText scrollable expects a double offset.
       // The in-memory _expandedLists already tracks expansion state.
       key:ValueKey<String>('todo-'+task.id),
       initiallyExpanded:_expandedLists.contains(task.id),
       onExpansionChanged:(expanded)=>setState((){
        if(expanded){_expandedLists.add(task.id);}else{_expandedLists.remove(task.id);}
       }),
       leading:StatusLook.mark(task.status.name)??const Icon(Icons.format_list_bulleted_outlined),
       title:Text(tt(task.title),style:StatusLook.title(context,task.status.name)),
       subtitle:details.isEmpty?null:Text(tt(details.join(' · '))),
       trailing:!canEdit?const Icon(Icons.lock_outline):
        ItemMenu(kind:'task',recordId:task.id,title:task.title,
         statusActions:[
          if(!cancelled&&!completed)ItemMenuAction(tt('Mark complete'),MenuIcons.complete,()=>_changeStatus(task,TaskStatus.completed)),
          if(!cancelled&&!completed)ItemMenuAction(tt('Cancel list'),MenuIcons.cancel,()=>_cancelTask(task)),
          if(cancelled||completed)ItemMenuAction(tt('Reopen list'),MenuIcons.reopen,()=>_changeStatus(task,TaskStatus.open)),
         ],
         onOpen:()=>_taskEditor(existing:task)),
       childrenPadding:const EdgeInsetsDirectional.fromSTEB(15,2,15,14),
       children:[
        if(_expandedLists.contains(task.id)) TaskChecklistPanel(ownerId:task.assignedTo,
         key:ValueKey(task.id),taskId:task.id,listTitle:task.title,
         recurrence:task.recurrence,
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
