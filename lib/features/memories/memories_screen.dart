import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../../core/record_list_top_actions.dart';
import '../../core/record_action_history_view.dart';
import '../../core/performance_timings.dart';
import '../../l10n/onespace_strings.dart';
import '../calendar/calendar_rules.dart';
import '../sharing/object_permissions.dart';
import '../sharing/private_share_button.dart';
import '../sharing/share_grant_watcher.dart';
import 'memory_photo_gallery.dart';
import 'memory_photo_service.dart';
import 'memory_photo_layout_rules.dart';
import 'scrapbook_studio_screen.dart';

class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key,this.initialMemoryId});
  final String? initialMemoryId;

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  final _client = Supabase.instance.client;
  final _search = TextEditingController();
  List<Map<String,dynamic>> _photoMetadata = const [];
  bool _capturing = false;
  String? _spaceId;
  Stream<List<Map<String, dynamic>>>? _stream;
  StreamSubscription<List<Map<String,dynamic>>>? _grants;
  bool _loading = true;
  bool _archived = false;
  bool _openedDeepLink=false;
  String _scope = 'all';
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(_searchChanged);
    _load();
  }

  void _searchChanged(){if(mounted)setState((){});}

  @override
  void dispose() {
    _search.removeListener(_searchChanged);
    _search.dispose();
    _grants?.cancel();
    super.dispose();
  }

  Stream<List<Map<String, dynamic>>> _createStream(String id) =>
      _client.from('memories')
          .stream(primaryKey: ['id'])
          .eq('space_id', id)
          .order('memory_date', ascending: false);

  Future<void> _load() async {
    final timer = Stopwatch()..start();
    if (mounted) setState(() { _loading = _spaceId == null; _error = null; });
    try {
      final id = await CurrentSpaceCache.instance.get();
      if (!mounted) return;
      _grants?.cancel();
      setState(() {
        _spaceId = id;
        if(id==null)_photoMetadata=const [];
        _stream = id == null ? null : _createStream(id);
        _loading = false;
      });
      if (id != null) {
        try{
          final photoRows=await _client.from('memory_photos')
           .select('memory_id,people_tags,place_tag,other_tags').limit(500);
          if(mounted)setState(()=>_photoMetadata=List<Map<String,dynamic>>.from(photoRows));
        }catch(_){if(mounted)setState(()=>_photoMetadata=const []);}
        _grants = watchObjectShares(
          client: _client, spaceId: id, objectType: 'memory',
          onChanged: () {
            if (mounted && _spaceId == id) {
              setState(() => _stream = _createStream(id));
            }
          },
        );
      }
      if(id!=null&&widget.initialMemoryId!=null&&!_openedDeepLink){
       _openedDeepLink=true;
       try{
        final rows=await _client.from('memories').select()
         .eq('space_id',id).eq('id',widget.initialMemoryId!).limit(1);
        if(mounted&&rows.isNotEmpty){
         WidgetsBinding.instance.addPostFrameCallback((_){
          if(mounted)_edit(existing:rows.first);
         });
        }
       }catch(_){}
      }
      PerformanceTimings.instance.record('Memories setup', timer.elapsed);
    } on PostgrestException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = tr(context,'loadFailed'); _loading = false; });
    }
  }

  Future<void> _edit({Map<String,dynamic>? existing,bool selfie=false}) async {
    final id = _spaceId;
    if (id == null) return;
    if(existing?['memory_type']=='scrapbook'){
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder:(_)=>ScrapbookStudioScreen(
         spaceId:id,memoryId:existing!['id'].toString())));
      if(mounted)await _load();
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) =>
        MemoryEditorScreen(spaceId: id, existing: existing,
         initialType:selfie?'daily_selfie':null)),
    );
    if (mounted && changed == true) await _load();
  }

  /// Camera-first, single-step Daily selfie. The user chooses privacy before
  /// a memory is created. Cancellation never creates an empty database row.
  Future<void> _dailySelfie()async{
    final space=_spaceId;
    final user=_client.auth.currentUser?.id;
    if(space==null||user==null||_capturing)return;
    final choice=await showModalBottomSheet<String>(context:context,
     showDragHandle:true,builder:(ctx)=>SafeArea(child:Column(
      mainAxisSize:MainAxisSize.min,children:[
       const ListTile(title:Text('Add a daily photo'),
        subtitle:Text('Choose who can see it and where the photo comes from.')),
       ListTile(leading:const Icon(Icons.photo_camera_outlined),
        title:const Text('Take a shared selfie'),
        onTap:()=>Navigator.pop(ctx,'shared_camera')),
       ListTile(leading:const Icon(Icons.photo_library_outlined),
        title:const Text('Choose a shared photo'),
        onTap:()=>Navigator.pop(ctx,'shared_gallery')),
       ListTile(leading:const Icon(Icons.lock_outline),
        title:const Text('Take a private selfie'),
        onTap:()=>Navigator.pop(ctx,'private_camera')),
       ListTile(leading:const Icon(Icons.collections_outlined),
        title:const Text('Choose a private photo'),
        onTap:()=>Navigator.pop(ctx,'private_gallery')),
      ])));
    if(choice==null||!mounted)return;
    setState(()=>_capturing=true);
    String? createdId;
    try{
     final photo=await ImagePicker().pickImage(
      source:choice.endsWith('camera')?ImageSource.camera:ImageSource.gallery,
      imageQuality:82,maxWidth:1600,maxHeight:1600);
     if(photo==null)return;
     final today=CalendarRules.sqlDate(DateTime.now());
     final newMemory=await _client.from('memories').insert({
      'space_id':space,'created_by':user,
      'title':'Daily selfie · $today','body':'',
      'memory_date':today,'visibility':choice.startsWith('private')?'private':'shared',
      'memory_type':'daily_selfie','photo_layout':'polaroid',
     }).select().single();
     createdId=newMemory['id'].toString();
     await MemoryPhotoService(_client).addFiles(createdId,[photo]);
     if(!mounted)return;
     await _load();
     if(mounted)await _edit(existing:newMemory);
    }on PostgrestException catch(e){
     if(mounted)setState(()=>_error='Selfie could not be saved: '+e.message+
      (createdId==null?'':' · The memory was created and can be edited.'));
    }catch(_){
     if(mounted)setState(()=>_error=createdId==null?
      'Unable to capture or save the daily photo.':
      'Memory created, but the photo upload did not finish. Open it to retry.');
    }finally{if(mounted)setState(()=>_capturing=false);}
  }

  bool _matchesSearch(Map<String,dynamic> memory){
   final words=_search.text.toLowerCase().trim().split(RegExp(r'\s+'))
    .where((v)=>v.isNotEmpty).toList();
   if(words.isEmpty)return true;
   final id=memory['id'].toString();
   final tags=_photoMetadata.where((p)=>p['memory_id'].toString()==id)
    .expand((p)=>[
      p['place_tag']?.toString()??'',
      ...(p['people_tags'] as List? ??const []).map((v)=>v.toString()),
      ...(p['other_tags'] as List? ??const []).map((v)=>v.toString()),
    ]).join(' ');
   final content=((memory['title']??'').toString()+' '+(memory['body']??'').toString()+' '+tags).toLowerCase();
   return words.every(content.contains);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'memories')),actions:[
      RecordListTopActions(
        showHistory:_archived,
        onToggleHistory:()=>setState(()=>_archived=!_archived),
        hasActiveFilters:_scope!='all',
        filters:(_)=>StatefulBuilder(builder:(ctx,update)=>Column(
          mainAxisSize:MainAxisSize.min,
          crossAxisAlignment:CrossAxisAlignment.start,children:[
           const Text('Visibility'),
           Wrap(spacing:8,children:[
            for(final choice in ['all','shared','private'])
             ChoiceChip(label:Text(tr(ctx,choice)),selected:_scope==choice,
              onSelected:(_){
               setState(()=>_scope=choice);update((){});
              }),
           ]),
           TextButton.icon(onPressed:(){
            setState(()=>_scope='all');update((){});
           },icon:const Icon(Icons.restart_alt),
            label:const Text('Reset filters')),
          ])),
      ),
    ]),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(tr(context, 'ourMemories'),
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(tr(context, 'memoriesSubtitle')),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.red)),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(tr(context,'retry')),
            ),
          ],
          if (_loading)
            const Padding(padding: EdgeInsets.all(38),
              child: Center(child: CircularProgressIndicator()))
          else if (_spaceId == null)
            Text(tr(context, 'noSpace'))
          else ...[
            FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.edit_note),
              label: Text(tr(context, 'newMemory')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed:_capturing?null:_dailySelfie,
             icon:const Icon(Icons.photo_camera_outlined),
             label:Text(_capturing?'Saving photo…':'Daily selfie · Camera or Gallery')),
            const SizedBox(height:8),
            OutlinedButton.icon(
              icon:const Icon(Icons.auto_stories_outlined),
              label:const Text('Scrapbook Studio · Designed pages'),
              onPressed:() async{
                final current=_spaceId;
                if(current==null)return;
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder:(_)=>ScrapbookStudioScreen(
                   spaceId:current)));
                if(mounted)await _load();
              },
            ),
            if(_capturing)const LinearProgressIndicator(),
            const SizedBox(height: 14),
            TextField(controller:_search,decoration:InputDecoration(
             prefixIcon:const Icon(Icons.search),
             hintText:'Search memories, people, places and photo tags',
             border:const OutlineInputBorder(),
             suffixIcon:_search.text.isEmpty?null:IconButton(
              tooltip:'Clear search',onPressed:_search.clear,
              icon:const Icon(Icons.clear)))),
            const SizedBox(height: 12),
            StreamBuilder<List<Map<String,dynamic>>>(
              stream: _stream,
              builder: (context,snapshot) {
                if (snapshot.hasError) return Text(tr(context,'loadFailed'));
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final shown = snapshot.data!.where((m) =>
                  (_archived || m['archived_at'] == null) &&
                  (_scope == 'all' || m['visibility'] == _scope) &&
                  _matchesSearch(m))
                  .toList()
                    ..sort((a,b) {
                      final pin = (b['pinned'] == true ? 1 : 0) -
                          (a['pinned'] == true ? 1 : 0);
                      return pin != 0 ? pin : (b['memory_date'] as String)
                          .compareTo(a['memory_date'] as String);
                    });
                if (shown.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(36),
                    child: Text(tr(context,'noMemories'),textAlign: TextAlign.center),
                  );
                }
                final userId = _client.auth.currentUser?.id ?? '';
                return Column(children: shown.map((memory) {
                  final creator = memory['created_by'] as String? ?? '';
                  final visibility = memory['visibility'] as String? ?? 'shared';
                  final editable = ObjectPermissions.canEdit(
                    visibility: visibility, createdBy: creator, userId: userId);
                  final ownerShare = ObjectPermissions.canManagePrivateShare(
                    visibility: visibility, createdBy: creator, userId: userId);
                  final date = memory['memory_date'] as String? ?? '';
                  final body = memory['body'] as String? ?? '';
                  return Card(
                    elevation: 0,
                    child: Column(children: [
                      ListTile(
                        leading: Icon(memory['memory_type']=='scrapbook'
                            ? Icons.collections_bookmark_outlined :
                              (memory['pinned'] == true
                            ? Icons.push_pin : Icons.auto_stories_outlined)),
                        title: Text(memory['title'] as String? ?? ''),
                        subtitle: Text([
                          date,
                          tr(context,visibility),
                          if (!editable) tr(context,'viewOnly'),
                          if (body.isNotEmpty) body.replaceAll('\n',' '),
                        ].join(' • '), maxLines: 3, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _edit(existing: memory),
                      ),
                      if (ownerShare) Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: PrivateShareButton(
                          objectType: 'memory',
                          objectId: memory['id'] as String,
                        ),
                      ),
                    ]),
                  );
                }).toList());
              },
            ),
            const SizedBox(height: 18),
            Text('Open a memory to add photos, choose a collage layout and write captions.',
              style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    ),
  );
}

/// Dated journal entry editor. Viewer-only recipients cannot edit, pin or
/// archive someone else's private memory.
class MemoryEditorScreen extends StatefulWidget {
  const MemoryEditorScreen({super.key,required this.spaceId,this.existing,this.initialType});
  final String spaceId;
  final Map<String,dynamic>? existing;
  final String? initialType;

  @override
  State<MemoryEditorScreen> createState() => _MemoryEditorScreenState();
}

class _MemoryEditorScreenState extends State<MemoryEditorScreen> {
  final _client = Supabase.instance.client;
  late final TextEditingController _title;
  late final TextEditingController _body;
  late DateTime _date;
  late String _visibility;
  late bool _pinned;
  late String _memoryType;
  late String _photoLayout;
  bool _busy = false;
  String? _error;
  StreamSubscription<List<Map<String,dynamic>>>? _grants;

  bool get _editing => widget.existing != null;
  bool get _archived => widget.existing?['archived_at'] != null;
  bool get _editable => !_editing || ObjectPermissions.canEdit(
    visibility: widget.existing!['visibility'] as String,
    createdBy: widget.existing!['created_by'] as String,
    userId: _client.auth.currentUser!.id,
  );

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(
      text: widget.existing?['title'] as String? ?? '');
    _body = TextEditingController(
      text: widget.existing?['body'] as String? ?? '');
    _date = DateTime.tryParse(widget.existing?['memory_date'] as String? ?? '')
        ?? DateTime.now();
    _visibility = widget.existing?['visibility'] as String? ?? 'shared';
    _pinned = widget.existing?['pinned'] == true;
    _memoryType=(widget.existing?['memory_type']??widget.initialType??'story').toString();
    _photoLayout=MemoryPhotoLayoutRules.safe(widget.existing?['photo_layout']);
    if (_editing && !_editable) {
      _grants = watchObjectShares(
        client: _client, spaceId: widget.spaceId, objectType: 'memory',
        onChanged: _checkViewingAccess,
      );
    }
  }

  Future<void> _checkViewingAccess() async {
    try {
      final rows = await _client.from('memories').select('id')
          .eq('id',widget.existing!['id'] as String).limit(1);
      if (mounted && rows.isEmpty) Navigator.of(context).pop(false);
    } catch (_) {
      // A transient connection failure does not imply access was revoked.
    }
  }

  @override
  void dispose() {
    _grants?.cancel();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context, initialDate: _date,
      firstDate: DateTime(1900), lastDate: DateTime(2100,12,31),
    );
    if (mounted && date != null) setState(() => _date = date);
  }

  Future<void> _save() async {
    if (_busy || !_editable || _archived) return;
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || title.length > 120 || body.length > 20000) {
      setState(() => _error = tr(context,'memoryValidation'));
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final fields = <String,dynamic>{
        'title': title, 'body': body,
        'memory_date': CalendarRules.sqlDate(_date),
        'pinned': _pinned,
        'memory_type':_memoryType,'photo_layout':_photoLayout,
      };
      if (!_editing) {
        await _client.from('memories').insert({
          ...fields,
          'space_id': widget.spaceId,
          'created_by': _client.auth.currentUser!.id,
          'visibility': _visibility,
        });
      } else {
        final existing = widget.existing!;
        final result = await _client.from('memories')
          .update(fields)
          .eq('id',existing['id'] as String)
          .eq('updated_at',existing['updated_at'] as String)
          .select('id');
        if (result.isEmpty) {
          if (mounted) setState(() => _error = tr(context,'noteConflict'));
          return;
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr(context,'saveFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleArchive() async {
    if (!_editable || !_editing || _busy) return;
    if (!_archived) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr(context,'archiveMemory')),
          content: Text(tr(context,'archiveExplanation')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext,false),
              child: Text(tr(context,'cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext,true),
              child: Text(tr(context,'archive')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final result = await _client.from('memories').update({
        'archived_at': _archived ? null : DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.existing!['id'] as String)
        .eq('updated_at', widget.existing!['updated_at'] as String)
        .select('id');
      if (result.isEmpty) {
        if (mounted) setState(() => _error = tr(context,'noteConflict'));
        return;
      }
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr(context,'saveFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context,_editing?'editMemory':'newMemory')),
     actions:[
      if(_editing)RecordActionHistoryButton(
       kind:'memory',recordId:widget.existing!['id'].toString()),
     ]),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (!_editable) Text(tr(context,'viewOnly')),
          if (_archived) Text(tr(context,'archived')),
          TextField(
            controller: _title, maxLength: 120, readOnly: !_editable,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tr(context,'memoryTitle'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: !_editable || _busy ? null : _selectDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(CalendarRules.sqlDate(_date)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            readOnly: !_editable,
            maxLines: 9, minLines: 4, maxLength: 20000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tr(context,'memoryStory'),
              border: const OutlineInputBorder(), alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(initialValue:_memoryType,
           decoration:const InputDecoration(labelText:'Memory type',border:OutlineInputBorder()),
           items:const [
            DropdownMenuItem(value:'story',child:Text('Story / journal')),
            DropdownMenuItem(value:'daily_selfie',child:Text('Daily selfie')),
            DropdownMenuItem(value:'collage',child:Text('Photo collage')),
           ],onChanged:!_editable||_busy?null:(v)=>setState(()=>_memoryType=v??_memoryType)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(initialValue:_photoLayout,
           decoration:const InputDecoration(labelText:'Photo layout',border:OutlineInputBorder()),
           items:const [
            DropdownMenuItem(value:'grid',child:Text('Photo grid')),
            DropdownMenuItem(value:'feature',child:Text('One large, others below')),
            DropdownMenuItem(value:'polaroid',child:Text('Polaroid-style collage')),
            DropdownMenuItem(value:'overlap',child:Text('Overlapping photo stack')),
           ],onChanged:!_editable||_busy?null:(v)=>setState(()=>_photoLayout=v??_photoLayout)),
          const SizedBox(height: 8),
          Text(tr(context,'visibility')),
          Wrap(spacing: 8,children: ['shared','private'].map((v) =>
            ChoiceChip(
              label: Text(tr(context,v)),
              selected: _visibility == v,
              onSelected: _editing || _busy ? null :
                  (_) => setState(() => _visibility = v),
            )).toList()),
          Text(tr(context,_editing?'privacyAlreadyFixed':'privacyFixed'),
            style: Theme.of(context).textTheme.bodySmall),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(context,'pinNote')),
            value: _pinned,
            onChanged: !_editable || _busy ? null
              : (value) => setState(() => _pinned = value),
          ),
          if(_editing&&_visibility=='shared')const Padding(
           padding:EdgeInsets.symmetric(vertical:6),
           child:Text('This shared memory is collaborative: both partners can add photos, captions and tags.')),
          if(_editing&&!_archived)MemoryPhotoGallery(
           memoryId:widget.existing!['id'].toString(),
           editable:_editable,layout:_photoLayout),
          if(!_editing)const Padding(padding:EdgeInsets.only(top:12),
           child:Text('Save this memory first, then reopen it to attach photos.')),
          if (_error != null) Text(_error!,
            style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          if (_editable && !_archived) FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(tr(context,'save')),
          ),
          if (_editing && _editable) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _toggleArchive,
              icon: const Icon(Icons.archive_outlined),
              label: Text(tr(context,_archived?'restore':'archive')),
            ),
          ],
        ],
      ),
    ),
  );
}
