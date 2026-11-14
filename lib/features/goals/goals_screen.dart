import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../../core/record_list_top_actions.dart';
import '../../core/record_action_history_view.dart';
import '../../l10n/onespace_strings.dart';
import '../sharing/object_permissions.dart';
import '../sharing/private_share_button.dart';
import '../sharing/share_grant_watcher.dart';
import '../connection/connection_rules.dart';

/// Real goals persisted in Supabase. Owner-only private goals can be granted
/// read access, while shared goals are collaboratively editable.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key,this.initialGoalId});
  final String? initialGoalId;
  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final _client = Supabase.instance.client;
  String? _space;
  Stream<List<Map<String,dynamic>>>? _stream;
  String? _error;
  bool _loading = true;
  StreamSubscription<List<Map<String,dynamic>>>? _grants;
  bool _archived = false;
  String _filter = 'active';
  String _query = '';
  bool _openedDeepLink=false;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _grants?.cancel(); super.dispose(); }

  void _watchGrants(String id) {
    _grants?.cancel();
    _grants = watchObjectShares(
      client:_client,spaceId:id,objectType:'goal',
      onChanged:() {
        if (!mounted || _space != id) return;
        setState(() {
          _stream = _client.from('goals')
            .stream(primaryKey:['id']).eq('space_id',id)
            .order('updated_at',ascending:false);
        });
      },
    );
  }


  Future<void> _load() async {
    if (mounted) setState(() { _loading = _space == null; _error = null; });
    try {
      final space = await CurrentSpaceCache.instance.get();
      if (!mounted) return;
      setState(() {
        _space = space;
        _stream = space == null ? null : _client.from('goals')
            .stream(primaryKey: ['id']).eq('space_id',space)
            .order('updated_at',ascending:false);
        _loading = false;
      });
      if (space != null) {
        _watchGrants(space);
        if(widget.initialGoalId!=null&&!_openedDeepLink){
         _openedDeepLink=true;
         final rows=await _client.from('goals').select()
          .eq('space_id',space).eq('id',widget.initialGoalId!).limit(1);
         if(mounted&&rows.isNotEmpty){
          WidgetsBinding.instance.addPostFrameCallback((_){
           if(mounted)_edit(rows.first);
          });
         }
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = tr(context,'loadFailed'); _loading = false;
        });
      }
    }
  }

  Future<void> _edit([Map<String,dynamic>? goal]) async {
    final space = _space;
    if (space == null) return;
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => GoalEditor(spaceId:space,existing:goal),
    ));
  }

  Future<void> _archive(Map<String,dynamic> goal) async {
    try {
      await _client.from('goals').update({
        'archived_at': goal['archived_at'] == null
            ? DateTime.now().toUtc().toIso8601String() : null,
      }).eq('id',goal['id'] as String);
    } catch (_) {
      if (mounted) setState(() => _error = tr(context,'saveFailed'));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context,'goalsTitle')),actions:[
      RecordListTopActions(
        showHistory:_archived,
        onToggleHistory:()=>setState(()=>_archived=!_archived),
        hasActiveFilters:_filter!='active',
        filters:(_)=>StatefulBuilder(builder:(ctx,update)=>Column(
         mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,
         children:[
          const Text('Status'),
          Wrap(spacing:8,children:[
           for(final status in ['active','paused','achieved','all'])
            ChoiceChip(selected:_filter==status,
             label:Text(tr(ctx,status)),
             onSelected:(_){
              setState(()=>_filter=status);
              update((){});
             }),
          ]),
          TextButton.icon(onPressed:(){
           setState(()=>_filter='active');update((){});
          },icon:const Icon(Icons.restart_alt),
           label:const Text('Reset filters')),
         ])),
      ),
    ]),
    body: RefreshIndicator(
      onRefresh:_load,
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Text(tr(context,'goalsSubtitle')),
        const SizedBox(height:14),
        if (_error != null) Text(_error!,style:const TextStyle(color:Colors.red)),
        if (_loading)
          const Padding(padding:EdgeInsets.all(28),
            child:Center(child:CircularProgressIndicator()))
        else if (_space == null)
          Text(tr(context,'noSpace'))
        else ...[
          FilledButton.icon(
            onPressed:()=>_edit(),
            icon:const Icon(Icons.flag_outlined),
            label:Text(tr(context,'newGoal'))),
          const SizedBox(height:12),
          TextField(
           onChanged:(value)=>setState(()=>_query=value.trim().toLowerCase()),
           decoration:const InputDecoration(
            prefixIcon:Icon(Icons.search),labelText:'Search goals',
            hintText:'Search goal titles and descriptions',
            border:OutlineInputBorder())),
          const SizedBox(height:10),
          StreamBuilder<List<Map<String,dynamic>>>(
            stream:_stream,
            builder:(context,snapshot) {
              if (snapshot.hasError) { return Text(tr(context,'loadFailed')); }
              if (!snapshot.hasData) {
                return const Center(child:CircularProgressIndicator());
              }
              final entries=snapshot.data!.where((g)=>
                (_archived || g['archived_at']==null) &&
                (_filter=='all' || g['status']==_filter) &&
                (_query.isEmpty ||
                 (g['title']??'').toString().toLowerCase().contains(_query) ||
                 (g['description']??'').toString().toLowerCase().contains(_query))
                ).toList();
              if (entries.isEmpty) {
                return Padding(
                  padding:const EdgeInsets.all(36),
                  child:Text(tr(context,'noGoals'),textAlign:TextAlign.center));
              }
              final me=_client.auth.currentUser?.id ?? '';
              return Column(children:entries.map((g) {
                final owner=g['created_by'] as String? ?? '';
                final vis=g['visibility'] as String? ?? 'shared';
                final canEdit=ObjectPermissions.canEdit(
                  visibility:vis,createdBy:owner,userId:me);
                final canShare=ObjectPermissions.canManagePrivateShare(
                  visibility:vis,createdBy:owner,userId:me);
                final progress=(g['progress'] as num?)?.toInt() ?? 0;
                return Card(elevation:0,child:Column(children:[
                  ListTile(
                    leading:Icon(g['status']=='achieved'
                      ? Icons.emoji_events_outlined : Icons.flag_outlined),
                    title:Text(g['title'] as String? ?? ''),
                    subtitle:Text([
                      tr(context,vis),
                      tr(context,g['status'] as String? ?? 'active'),
                      if (!canEdit) tr(context,'viewOnly'),
                      if (g['target_date']!=null)
                        '${tr(context,'target')}: ${g['target_date']}',
                    ].join(' • ')),
                    onTap:()=>_edit(g),
                    trailing:const Icon(Icons.chevron_right)),
                  Padding(
                    padding:const EdgeInsets.symmetric(horizontal:16),
                    child:Row(children:[
                      Expanded(child:LinearProgressIndicator(
                        value:progress/100,minHeight:7,
                        borderRadius:BorderRadius.circular(6))),
                      const SizedBox(width:12),
                      Text('$progress%'),
                    ])),
                  if (canEdit || canShare) Row(
                    mainAxisAlignment:MainAxisAlignment.end,
                    children:[
                      if (canEdit) TextButton(
                        onPressed:()=>_archive(g),
                        child:Text(tr(context,g['archived_at']==null
                          ? 'archive' : 'restore'))),
                      if (canShare) PrivateShareButton(
                        objectType:'goal',objectId:g['id'] as String),
                    ]),
                ]));
              }).toList());
            }),
        ],
      ]),
    ),
  );
}

/// Editing happens on a dedicated route, so controllers live until disposed.
class GoalEditor extends StatefulWidget {
  const GoalEditor({super.key,required this.spaceId,this.existing});
  final String spaceId;
  final Map<String,dynamic>? existing;
  @override
  State<GoalEditor> createState()=>_GoalEditorState();
}
class _GoalEditorState extends State<GoalEditor> {
  final _client=Supabase.instance.client;
  late final TextEditingController _title,_description;
  late String _visibility,_status;
  late int _progress;
  DateTime? _target;
  bool _saving=false;
  String? _error;
  bool get _canEdit=>widget.existing==null ||
      ObjectPermissions.canEdit(
        visibility:widget.existing!['visibility'] as String,
        createdBy:widget.existing!['created_by'] as String,
        userId:_client.auth.currentUser!.id);

  @override
  void initState() {
    super.initState();
    _title=TextEditingController(text:widget.existing?['title'] as String? ?? '');
    _description=TextEditingController(
      text:widget.existing?['description'] as String? ?? '');
    _visibility=widget.existing?['visibility'] as String? ?? 'shared';
    _status=widget.existing?['status'] as String? ?? 'active';
    _progress=(widget.existing?['progress'] as num?)?.toInt() ?? 0;
    _target=DateTime.tryParse(widget.existing?['target_date'] as String? ?? '');
  }
  @override
  void dispose() { _title.dispose();_description.dispose();super.dispose(); }

  Future<void> _save() async {
    if (!_canEdit || _saving) return;
    final title=_title.text.trim();
    if (!ConnectionRules.validGoal(title:title,
      description:_description.text,progress:_progress)) {
      setState(()=>_error=tr(context,'goalValidation'));return;
    }
    setState(() { _saving=true;_error=null;});
    try {
      final fields=<String,dynamic>{
        'title':title,'description':_description.text.trim(),
        'target_date':_target==null ? null :
          '${_target!.year}-${_target!.month.toString().padLeft(2,'0')}-'
          '${_target!.day.toString().padLeft(2,'0')}',
        'progress':_progress,
        'status':_status,
      };
      if(widget.existing==null) {
        await _client.from('goals').insert({
          ...fields,'space_id':widget.spaceId,
          'created_by':_client.auth.currentUser!.id,
          'visibility':_visibility,
        });
      } else {
        final rows=await _client.from('goals').update(fields)
          .eq('id',widget.existing!['id'] as String).select('id');
        if(rows.isEmpty) throw StateError('Goal no longer editable');
      }
      if(mounted) Navigator.of(context).pop();
    } on PostgrestException catch(e) {
      if(mounted)setState(()=>_error=e.message);
    } catch(_) {
      if(mounted)setState(()=>_error=tr(context,'saveFailed'));
    } finally {
      if(mounted)setState(()=>_saving=false);
    }
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(tr(context,widget.existing==null
      ? 'newGoal':'editGoal')),actions:[
      if(widget.existing!=null)RecordActionHistoryButton(
       kind:'goal',recordId:widget.existing!['id'].toString()),
    ]),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
      if (!_canEdit) Text(tr(context,'viewOnly')),
      TextField(controller:_title,readOnly:!_canEdit,maxLength:120,
        decoration:InputDecoration(
          labelText:tr(context,'goalTitle'),border:const OutlineInputBorder())),
      const SizedBox(height:12),
      TextField(controller:_description,readOnly:!_canEdit,maxLength:3000,
        minLines:2,maxLines:6,
        decoration:InputDecoration(
          labelText:tr(context,'goalDescription'),
          border:const OutlineInputBorder())),
      const SizedBox(height:12),
      Text(tr(context,'visibility')),
      Wrap(spacing:8,children:['shared','private'].map((v)=>ChoiceChip(
        label:Text(tr(context,v)),selected:_visibility==v,
        onSelected:widget.existing!=null || _saving ? null :
          (_)=>setState(()=>_visibility=v))).toList()),
      const SizedBox(height:12),
      Text(tr(context,'goalProgress')),
      Slider(value:_progress.toDouble(),min:0,max:100,divisions:20,
        label:'$_progress%',
        onChanged:_canEdit && !_saving ? (v)=>
          setState(()=>_progress=v.round()):null),
      Center(child:Text('$_progress%')),
      const SizedBox(height:10),
      Wrap(spacing:8,children:['active','paused','achieved'].map((v)=>
        ChoiceChip(label:Text(tr(context,v)),selected:_status==v,
          onSelected:_canEdit && !_saving ? (_)=>
            setState(()=>_status=v):null)).toList()),
      const SizedBox(height:12),
      OutlinedButton.icon(
        onPressed:!_canEdit || _saving ? null : () async {
          final now=DateTime.now();
          final pick=await showDatePicker(context:context,
            initialDate:_target??now,firstDate:DateTime(2000),
            lastDate:DateTime(2100));
          if(mounted && pick!=null)setState(()=>_target=pick);
        },
        icon:const Icon(Icons.calendar_today_outlined),
        label:Text(_target==null?tr(context,'optionalDate'):
          '${_target!.year}-${_target!.month}-${_target!.day}')),
      if (_target!=null && _canEdit)
        TextButton(onPressed:()=>setState(()=>_target=null),
          child:Text(tr(context,'clearDate'))),
      if(_error!=null)Text(_error!,style:const TextStyle(color:Colors.red)),
      const SizedBox(height:18),
      if(_canEdit)FilledButton(
        onPressed:_saving?null:_save,
        child:Text(tr(context,'save'))),
    ])),
  );
}
