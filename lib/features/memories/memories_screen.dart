import '../../core/form_kit.dart';
import '../../core/item_menu.dart';
import 'selfie_studio_screen.dart';
import '../../core/editor_scaffold.dart';
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../../core/account_content_scope.dart';
import '../../core/app_env.dart';
import '../../core/record_list_top_actions.dart';
import '../../core/performance_timings.dart';
import '../../l10n/onespace_strings.dart';
import '../calendar/calendar_rules.dart';
import '../sharing/object_permissions.dart';
import '../sharing/private_share_button.dart';
import '../sharing/share_grant_watcher.dart';
import 'memory_photo_gallery.dart';
import 'memory_photo_layout_rules.dart';
import 'scrapbook_studio_screen.dart';
import 'scrapbook_viewer_screen.dart';
import 'memory_view_screen.dart';
import 'package:onespace/l10n/phrases.dart';

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
  String? _spaceId;
  String? _privateSpaceId;
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

  Stream<List<Map<String, dynamic>>> _createStream(String? id) =>
      !OneSpaceEnv.isProduction
          ? _client.from('memories').stream(primaryKey: ['id'])
              .order('memory_date', ascending: false)
          : _client.from('memories').stream(primaryKey: ['id'])
              .eq('space_id', id!)
              .order('memory_date', ascending: false);

  Future<void> _load() async {
    final timer = Stopwatch()..start();
    if (mounted) setState(() { _loading = _spaceId == null; _error = null; });
    try {
      final legacy = await CurrentSpaceCache.instance.get();
      final scopes = await AccountContentScope.load(_client, legacySpaceId: legacy);
      final id = scopes.sharedSpaceId;
      if (!mounted) return;
      _grants?.cancel();
      setState(() {
        _spaceId = id;
        _privateSpaceId = scopes.privateSpaceId;
        _photoMetadata = const [];
        _stream = id == null && OneSpaceEnv.isProduction
            ? null : _createStream(id);
        _loading = false;
      });
      if (id != null || !OneSpaceEnv.isProduction) {
        try{
          final photoRows=await _client.from('memory_photos')
           .select('memory_id,people_tags,place_tag,other_tags').limit(500);
          if(mounted)setState(()=>_photoMetadata=List<Map<String,dynamic>>.from(photoRows));
        }catch(_){if(mounted)setState(()=>_photoMetadata=const []);}
        if (id != null) _grants = watchObjectShares(
          client: _client, spaceId: id, objectType: 'memory',
          onChanged: () {
            if (mounted && _spaceId == id) {
              setState(() => _stream = _createStream(id));
            }
          },
        );
      }
      if((id!=null||!OneSpaceEnv.isProduction)&&widget.initialMemoryId!=null&&!_openedDeepLink){
       _openedDeepLink=true;
       try{
        var query = _client.from('memories').select();
        if (OneSpaceEnv.isProduction) query=query.eq('space_id',id!);
        final rows=await query.eq('id',widget.initialMemoryId!).limit(1);
        if(mounted&&rows.isNotEmpty){
         WidgetsBinding.instance.addPostFrameCallback((_){
          if(mounted)_view(rows.first);
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
    if (id == null && OneSpaceEnv.isProduction) return;
    if(existing?['memory_type']=='scrapbook'){
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder:(_)=>ScrapbookStudioScreen(
         spaceId:id,memoryId:existing!['id'].toString())));
      if(mounted)await _load();
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) =>
        MemoryEditorScreen(spaceId: id ?? '', existing: existing,
         initialType:selfie?'daily_selfie':null)),
    );
    if (mounted && changed == true) await _load();
  }

  /// R70: a memory opens to read (story, daily selfie, scrapbook); editing
  /// is a button there or in ⋮.
  Future<void> _view(Map<String,dynamic> memory)async{
    final id=_spaceId;
    if(id==null&&OneSpaceEnv.isProduction)return;
    final type=memory['memory_type']?.toString();
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder:(_)=>type=='scrapbook'
      ?ScrapbookViewerScreen(spaceId:id??'',memoryId:memory['id'].toString())
      :MemoryViewScreen(spaceId:id??'',memoryId:memory['id'].toString(),
        onEdit:(m)=>_edit(existing:m))));
    if(mounted)await _load();
  }

  /// R55: Daily selfie opens its own studio (front camera, polaroid
  /// preview, caption, who can see it, this week's strip).
  Future<void> _dailySelfie()async{
    final space=_spaceId;
    if(space==null&&OneSpaceEnv.isProduction)return;
    final saved=await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder:(_)=>SelfieStudioScreen(spaceId:space??'')));
    if(saved==true&&mounted)await _load();
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
   final content=((memory['title']??'').toString()+' '+(memory['body']??'').toString()+' '+(memory['place']??'').toString()+' '+tags).toLowerCase();
   return words.every(content.contains);
  }

  /// R55: this screen's filter groups (drawn by the shared panel).
 List<FilterGroupSpec> _filterGroups()=>[FilterGroupSpec(id:'who',label:tt('Who can see'),options:const {'all':'All','shared':'Shared','private':'Only me'},selected:_scope,defaultValue:'all')];

 @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'memories')),actions:[
      RecordListTopActions(
        historyKinds:const ['memory'],historyTitle:tt('Memories'),
     showHistory:_archived,
        onToggleHistory:()=>setState(()=>_archived=!_archived),
        groups:_filterGroups(),
      onApply:(v)=>setState((){_scope=v['who']!;}),
     ),
    ],bottom:filterShowingBar(_filterGroups(),removed:_archived,onClear:()=>setState((){_archived=false;_scope='all';}))),
    floatingActionButton:_spaceId==null&&_privateSpaceId==null?null:AddFabMenu(label:tt('Add memory'),options:[
      AddFabOption(tt('Story journal'),Icons.menu_book_outlined,()=>_edit()),
      AddFabOption(tt('Daily selfie'),Icons.photo_camera_outlined,_dailySelfie),
      if(_spaceId!=null) AddFabOption(tt('Scrapbook studio'),Icons.auto_stories_outlined,()async{
        final current=_spaceId;
        if(current==null)return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder:(_)=>ScrapbookStudioScreen(spaceId:current)));
        if(mounted)await _load();
      }),
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
            Text(tt(_error!), style: TextStyle(color:Theme.of(context).colorScheme.error)),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(tr(context,'retry')),
            ),
          ],
          if (_loading)
            const Padding(padding: EdgeInsets.all(38),
              child: Center(child: CircularProgressIndicator()))
          else if (_spaceId == null && OneSpaceEnv.isProduction)
            Text(tr(context, 'noSpace'))
          else ...[
            const SizedBox(height: 14),
            TextField(controller:_search,decoration:InputDecoration(
             prefixIcon:const Icon(Icons.search),
             labelText:tt('Search memories'),hintText:tt('People, places and photo tags'),
             border:const OutlineInputBorder(),
             suffixIcon:_search.text.isEmpty?null:IconButton(
              tooltip:tt('Clear search'),onPressed:_search.clear,
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
                            ? Icons.collections_bookmark_outlined
                            : memory['memory_type']=='daily_selfie' ? Icons.photo_camera_front_outlined
                            : (memory['pinned'] == true ? Icons.push_pin : Icons.auto_stories_outlined)),
                        title: Text(tt(memory['title'] as String? ?? '')),
                        subtitle: Text(tt([
                          date,
                          tr(context,visibility),
                          if (!editable) tr(context,'viewOnly'),
                          if (body.isNotEmpty) body.replaceAll('\n',' '),
                        ].join(' • ')), maxLines: 3, overflow: TextOverflow.ellipsis),
                        trailing: ItemMenu(kind: 'memory', recordId: memory['id'].toString(),
                          title: memory['title']?.toString(),
                          onOpen: () => memory['memory_type']=='daily_selfie'||!editable
                            ? _view(memory) : _edit(existing: memory),
                          openLabel: memory['memory_type']=='daily_selfie'||!editable ? 'Open' : 'Edit',
                          table: editable ? 'memories' : null,
                          removed: memory['archived_at'] != null, onChanged: _load),
                        onTap: () => _view(memory),
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
            Text(tt('Open a memory to add photos, choose a collage layout and write captions.'),
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
  const MemoryEditorScreen({super.key,required this.spaceId,this.existing,this.initialType,
    this.prefill,this.onSaved});
  final String spaceId;
  /// R77: title / place / memory_date for a new story (from a place or counter).
  final Map<String,String>? prefill;
  /// R77: called with the memory id once it is saved, so a place visit or a
  /// counter can link to it.
  final void Function(String id)? onSaved;
  final Map<String,dynamic>? existing;
  final String? initialType;

  @override
  State<MemoryEditorScreen> createState() => _MemoryEditorScreenState();
}

class _MemoryEditorScreenState extends State<MemoryEditorScreen> with FormChangeTracker<MemoryEditorScreen> {
 /// R55: current form values; Save turns on only when they change.
 @override String get signature=>[_title.text,_body.text,_place.text,_date,_visibility,_pinned,_memoryType,_photoLayout].join('|');

  final _client = Supabase.instance.client;
  late final TextEditingController _title;
  late final TextEditingController _body;
  /// R72: where it happened.
  late final TextEditingController _place;
  late DateTime _date;
  late String _visibility;
  late bool _pinned;
  late String _memoryType;
  late String _photoLayout;
  bool _busy = false;
  String? _error;
  StreamSubscription<List<Map<String,dynamic>>>? _grants;

  /// R70: the saved story: the one opened, or the one saved quietly when
  /// photos are added to a new story.
  Map<String,dynamic>? _record;
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
      text: widget.existing?['title'] as String? ?? widget.prefill?['title'] ?? '');
    _body = TextEditingController(
      text: widget.existing?['body'] as String? ?? '');
    _place = TextEditingController(text: widget.existing?['place']?.toString() ?? widget.prefill?['place'] ?? '');
    _date = DateTime.tryParse(widget.existing?['memory_date'] as String? ?? widget.prefill?['memory_date'] ?? '')
        ?? DateTime.now();
    _visibility = widget.existing?['visibility'] as String? ??
        (widget.spaceId.isEmpty && !OneSpaceEnv.isProduction ? 'private' : 'shared');
    _pinned = widget.existing?['pinned'] == true;
    _memoryType=(widget.existing?['memory_type']??widget.initialType??'story').toString();
    _record=widget.existing;
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
    _place.dispose();
    super.dispose();
  }

  /// Saves a new story without leaving, so photos can be added.
  Future<void> _ensureSaved() async {
    if (_record != null || _busy) return;
    final title = _title.text.trim();
    if (title.isEmpty) { setState(() => _error = 'Give it a title first.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final scopes = await AccountContentScope.load(_client,
          legacySpaceId: widget.spaceId.isEmpty ? null : widget.spaceId);
      final row = await _client.from('memories').insert({
        'title': title, 'body': _body.text.trim(), 'place': _place.text.trim(), 'memory_date': CalendarRules.sqlDate(_date),
        'pinned': _pinned, 'memory_type': _memoryType, 'photo_layout': _photoLayout,
        ...scopes.fieldsForNew(shared: _visibility == 'shared'),
        'created_by': _client.auth.currentUser!.id,
      }).select().single();
      if (mounted) setState(() => _record = row);
      widget.onSaved?.call(row['id'].toString());
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        'title': title, 'body': body, 'place': _place.text.trim(),
        'memory_date': CalendarRules.sqlDate(_date),
        'pinned': _pinned,
        'memory_type':_memoryType,'photo_layout':_photoLayout,
      };
      if (_record == null) {
        final scopes = await AccountContentScope.load(_client,
            legacySpaceId: widget.spaceId.isEmpty ? null : widget.spaceId);
        final created = await _client.from('memories').insert({
          ...fields,
          ...scopes.fieldsForNew(shared: _visibility == 'shared'),
          'created_by': _client.auth.currentUser!.id,
        }).select('id').single();
        widget.onSaved?.call(created['id'].toString());
      } else {
        final existing = _record!;
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

  @override
  Widget build(BuildContext context) => EditorScaffold(
   title:_editing?tt('Edit story'):tt('New story'),
   isNew:!_editing,isChanged:()=>changed,isComplete:()=>_editable && !_archived && _title.text.trim().isNotEmpty,
   listenTo:[_title,_body,_place],saving:_busy,onSave:_save,
   meta:MetaStrip(value:MetaValues(shared:_visibility=='shared'),
     showVisibility:widget.spaceId.isNotEmpty || OneSpaceEnv.isProduction,
     showBelongs:false,showDate:false,
     enabled:!_editing&&!_busy,onChanged:(v)=>setState(()=>_visibility=v.shared?'shared':'private')),
   body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (!_editable) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(tr(context,'viewOnly'))),
          if (_archived) Padding(padding: const EdgeInsets.only(bottom: 10),
            child: Text(tt('Removed · restore it from the ⋮ menu'), style: Theme.of(context).textTheme.bodySmall)),
          TextField(
            controller: _title, maxLength: 120, readOnly: !_editable, autofocus: !_editing,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tt('Give it a title *'),
              hintText: tt('Our first winter walk…'),
              border: OutlineInputBorder(),
            ),
          ),
          DateField(label: tt('When did it happen?'), required: true, value: _date,
            first: DateTime(1950), last: DateTime.now(),
            onChanged: (v) { if (v != null && _editable && !_busy) setState(() => _date = v); }),
          TextField(controller: _place, readOnly: !_editable, maxLength: 160,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tt('Where did it happen? (optional)'),
              hintText: tt('A café, a city, home…'), prefixIcon: const Icon(Icons.place_outlined),
              border: const OutlineInputBorder())),
          TextField(
            controller: _body,
            readOnly: !_editable,
            maxLines: 14, minLines: 6, maxLength: 20000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tt('The story'),
              hintText: tt('What happened, how it felt, what you want to remember…'),
              border: OutlineInputBorder(), alignLabelWithHint: true,
            ),
          ),
          Align(alignment: AlignmentDirectional.centerStart, child: OptionChip(label: tt('Pin to the top'),
            icon: Icons.push_pin_outlined, value: _pinned,
            onChanged: !_editable || _busy ? null : (v) => setState(() => _pinned = v))),
          FormSection(tt('Photos')),
          if(_record!=null&&!_archived)MemoryPhotoGallery(
           memoryId:_record!['id'].toString(),
           editable:_editable,layout:_photoLayout,
           onLayoutChanged:(v){if(_editable&&!_busy)setState(()=>_photoLayout=v);})
          else if(_record==null)Align(alignment:AlignmentDirectional.centerStart,child:ActionChip(
           avatar:const Icon(Icons.add_photo_alternate_outlined,size:18),
           label:Text(tt('Add photos')),onPressed:_busy?null:_ensureSaved)),
          if(_editing&&_visibility=='shared')Padding(
           padding:const EdgeInsets.symmetric(vertical:6),
           child:Text(tt('Shared memories are written together: both of you can add photos, captions and tags.'),
            style: Theme.of(context).textTheme.bodySmall)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(tt(_error!),
            style: TextStyle(color:Theme.of(context).colorScheme.error))),
        ],
      ),
    ),
  );
}
