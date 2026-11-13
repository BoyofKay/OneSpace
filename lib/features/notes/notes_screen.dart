import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/onespace_strings.dart';
import '../../core/current_space_cache.dart';
import 'note_draft_rules.dart';
import '../sharing/object_permissions.dart';
import '../sharing/private_share_button.dart';
import '../sharing/share_grant_watcher.dart';

/// Partner-visible and creator-only notes. Live list updates are streamed, while
/// edits use optimistic concurrency to avoid silently overwriting another edit.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _client = Supabase.instance.client;
  String? _spaceId;
  Stream<List<Map<String, dynamic>>>? _stream;
  StreamSubscription<List<Map<String, dynamic>>>? _shareWatcher;
  bool _loading = true;
  bool _showArchived = false;
  String _scope = 'all';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
      objectType: 'note',
      onChanged: () {
        if (!mounted || _spaceId != id) return;
        setState(() => _stream = _client.from('notes')
            .stream(primaryKey: ['id'])
            .eq('space_id', id)
            .order('updated_at', ascending: false));
      },
    );
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final id = await CurrentSpaceCache.instance.get();
      if (!mounted) return;
      setState(() {
        _spaceId = id;
        _stream = id == null ? null : _client.from('notes')
            .stream(primaryKey: ['id'])
            .eq('space_id', id)
            .order('updated_at', ascending: false);
      });
      if (id != null) _watchGrants(id);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr(context, 'loadFailed'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? note}) async {
    final id = _spaceId;
    if (id == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NoteEditorScreen(spaceId: id, existing: note),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(tr(context, 'notesTitle'),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(tr(context, 'notesSubtitle')),
          const SizedBox(height: 14),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          if (_loading)
            const Padding(padding: EdgeInsets.all(36),
              child: Center(child: CircularProgressIndicator()))
          else if (_spaceId == null)
            Text(tr(context, 'noSpace'))
          else ...[
            FilledButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.note_add_outlined),
              label: Text(tr(context, 'newNote')),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 7, children: ['all','shared','private'].map((scope) =>
              ChoiceChip(
                selected: _scope == scope,
                label: Text(tr(context, scope)),
                onSelected: (_) => setState(() => _scope = scope),
              )).toList()),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _showArchived,
              title: Text(tr(context, 'showArchived')),
              onChanged: (value) => setState(() => _showArchived = value),
            ),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text(tr(context, 'loadFailed'));
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final shown = snapshot.data!.where((note) =>
                  (_showArchived || note['archived_at'] == null) &&
                  (_scope == 'all' || note['visibility'] == _scope))
                  .toList()
                    ..sort((a,b) {
                      final pinned = (b['pinned'] == true ? 1 : 0) -
                          (a['pinned'] == true ? 1 : 0);
                      if (pinned != 0) return pinned;
                      return (b['updated_at'] as String)
                          .compareTo(a['updated_at'] as String);
                    });
                if (shown.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(44),
                    child: Text(tr(context, 'noNotes'), textAlign: TextAlign.center),
                  );
                }
                return Column(
                  children: shown.map((note) {
                    final archived = note['archived_at'] != null;
                    final body = note['body'] as String? ?? '';
                    final canEdit = ObjectPermissions.canEdit(
                      visibility: note['visibility'] as String,
                      createdBy: note['created_by'] as String,
                      userId: _client.auth.currentUser!.id,
                    );
                    final canShare = ObjectPermissions.canManagePrivateShare(
                      visibility: note['visibility'] as String,
                      createdBy: note['created_by'] as String,
                      userId: _client.auth.currentUser!.id,
                    );
                    return Card(
                      elevation: 0,
                      child: Column(
                        children: [
                      ListTile(
                        leading: Icon(note['pinned'] == true
                            ? Icons.push_pin : Icons.sticky_note_2_outlined),
                        title: Text(note['title'] as String,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [
                            tr(context, note['visibility'] as String),
                            if (archived) tr(context, 'archived'),
                            if (!canEdit) tr(context, 'viewOnly'),
                            if (body.isNotEmpty) body.replaceAll('\n',' '),
                          ].join(' • '),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openEditor(note: note),
                      ),
                      if (canShare)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: PrivateShareButton(
                            objectType: 'note',
                            objectId: note['id'] as String,
                          ),
                        ),
                      ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    required this.spaceId,
    this.existing,
  });
  final String spaceId;
  final Map<String, dynamic>? existing;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final _client = Supabase.instance.client;
  late final TextEditingController _title;
  late final TextEditingController _body;
  late String _visibility;
  late bool _pinned;
  bool _busy = false;
  bool _preview = false;
  String? _error;
  StreamSubscription<List<Map<String, dynamic>>>? _revocationWatcher;

  bool get _editing => widget.existing != null;
  bool get _canEdit => widget.existing == null ||
      ObjectPermissions.canEdit(
        visibility: widget.existing!['visibility'] as String,
        createdBy: widget.existing!['created_by'] as String,
        userId: _client.auth.currentUser!.id,
      );
  bool get _archived => widget.existing?['archived_at'] != null;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(
      text: widget.existing?['title'] as String? ?? '',
    );
    _body = TextEditingController(
      text: widget.existing?['body'] as String? ?? '',
    );
    _visibility = widget.existing?['visibility'] as String? ?? 'shared';
    _pinned = widget.existing?['pinned'] == true;
    if (_editing && !_canEdit) {
      _revocationWatcher = watchObjectShares(
        client: _client,
        spaceId: widget.spaceId,
        objectType: 'note',
        onChanged: _validateViewingPermission,
      );
    }
  }

  Future<void> _validateViewingPermission() async {
    final id = widget.existing?['id'] as String?;
    if (id == null) return;
    try {
      final visible = await _client.from('notes')
          .select('id').eq('id', id).limit(1);
      if (mounted && visible.isEmpty) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      // A network failure should not automatically close a note.
    }
  }

  @override
  void dispose() {
    _revocationWatcher?.cancel();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _insertFormatting(String before,{String after='',String placeholder='text'}) {
    if(!_canEdit || _busy || _archived){return;}
    final selection=_body.selection;
    final start=selection.isValid?selection.start:_body.text.length;
    final end=selection.isValid?selection.end:_body.text.length;
    final selected=start==end?placeholder:_body.text.substring(start,end);
    final replacement='$before$selected$after';
    _body.value=TextEditingValue(
      text:_body.text.replaceRange(start,end,replacement),
      selection:TextSelection.collapsed(offset:start+replacement.length),
    );
  }

  Widget _formattingToolbar()=>SingleChildScrollView(
    scrollDirection:Axis.horizontal,
    child:Row(children:[
      IconButton(tooltip:'Heading',icon:const Icon(Icons.title),
        onPressed:()=>_insertFormatting('## ',placeholder:'Heading')),
      IconButton(tooltip:'Bold',icon:const Icon(Icons.format_bold),
        onPressed:()=>_insertFormatting('**',after:'**')),
      IconButton(tooltip:'Italic',icon:const Icon(Icons.format_italic),
        onPressed:()=>_insertFormatting('*',after:'*')),
      IconButton(tooltip:'Checklist',icon:const Icon(Icons.check_box_outlined),
        onPressed:()=>_insertFormatting('- [ ] ',placeholder:'To-do')),
      IconButton(tooltip:'Bullets',icon:const Icon(Icons.format_list_bulleted),
        onPressed:()=>_insertFormatting('- ',placeholder:'List item')),
      IconButton(tooltip:'Numbers',icon:const Icon(Icons.format_list_numbered),
        onPressed:()=>_insertFormatting('1. ',placeholder:'List item')),
      IconButton(tooltip:'Link',icon:const Icon(Icons.link),
        onPressed:()=>_insertFormatting('[',after:'](https://)',placeholder:'Link name')),
    ]),
  );

  Widget _previewRow(String line,int index){
    final heading=line.startsWith('# ');
    final subheading=line.startsWith('## ');
    final task=line.startsWith('- [ ] ')||line.startsWith('- [x] ');
    final done=line.startsWith('- [x] ');
    final content=heading?line.substring(2):
      subheading?line.substring(3):task?line.substring(6):line;
    final style=heading?Theme.of(context).textTheme.titleLarge:
      subheading?Theme.of(context).textTheme.titleMedium:
      Theme.of(context).textTheme.bodyMedium;
    final spans=<TextSpan>[];
    final matcher=RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*)');
    var position=0;
    for(final match in matcher.allMatches(content)){
      if(match.start>position){
        spans.add(TextSpan(text:content.substring(position,match.start)));
      }
      final raw=match.group(0)!;
      if(raw.startsWith('**')){
        spans.add(TextSpan(text:raw.substring(2,raw.length-2),
          style:const TextStyle(fontWeight:FontWeight.bold)));
      }else{
        spans.add(TextSpan(text:raw.substring(1,raw.length-1),
          style:const TextStyle(fontStyle:FontStyle.italic)));
      }
      position=match.end;
    }
    if(position<content.length){
      spans.add(TextSpan(text:content.substring(position)));
    }
    final preview=Text.rich(TextSpan(style:style,children:spans));
    if(!task){
      return Padding(
        padding:const EdgeInsets.symmetric(vertical:4),
        child:preview);
    }
    return CheckboxListTile(
      contentPadding:EdgeInsets.zero,
      controlAffinity:ListTileControlAffinity.leading,
      value:done,
      onChanged:!_canEdit||_busy?null:(value){
        final lines=_body.text.split('\n');
        if(index>=lines.length){return;}
        lines[index]=lines[index].replaceFirst(
          RegExp(r'^- \[[ x]\] '),
          value==true?'- [x] ':'- [ ] ');
        setState(()=>_body.text=lines.join('\n'));
      },
      title:DefaultTextStyle.merge(
        style:TextStyle(decoration:done?TextDecoration.lineThrough:null,
          color:done?Theme.of(context).colorScheme.outline:null),
        child:preview,
      ),
    );
  }

  Future<void> _save() async {
    if (!_canEdit) return;
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (!NoteDraftRules.isValid(title: title, body: body)) {
      setState(() => _error = tr(context, 'noteValidation'));
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final fields = <String,dynamic>{
        'title': title, 'body': body, 'pinned': _pinned,
      };
      if (!_editing) {
        await _client.from('notes').insert({
          ...fields,
          'space_id': widget.spaceId,
          'created_by': _client.auth.currentUser!.id,
          'visibility': _visibility,
        });
      } else {
        final existing = widget.existing!;
        final matches = await _client.from('notes')
            .update(fields)
            .eq('id', existing['id'] as String)
            .eq('space_id', widget.spaceId)
            .eq('updated_at', existing['updated_at'] as String)
            .select('id');
        if (matches.isEmpty) {
          if (mounted) {
            setState(() => _error = tr(context, 'noteConflict'));
          }
          return;
        }
      }
      if (mounted) Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr(context, 'saveFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archiveOrRestore() async {
    if (!_editing || !_canEdit) return;
    final restoring = _archived;
    if (!restoring) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr(context, 'archiveNote')),
          content: Text(tr(context, 'archiveExplanation')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr(context, 'cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr(context, 'archive')),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    setState(() => _busy = true);
    try {
      final matches = await _client.from('notes').update({
        'archived_at': restoring
            ? null : DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.existing!['id'] as String)
        .eq('space_id', widget.spaceId)
        .eq('updated_at', widget.existing!['updated_at'] as String)
        .select('id');
      if (matches.isEmpty) {
        if (mounted) setState(() => _error = tr(context, 'noteConflict'));
        return;
      }
      if (mounted) Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr(context, 'saveFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context,
          _editing ? 'editNote' : 'newNote'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (!_canEdit)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(tr(context, 'viewOnly')),
              ),
            if (_archived)
              Text(tr(context, 'archived'), style: const TextStyle(
                fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _title, maxLength: 120,
              readOnly: !_canEdit,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr(context, 'noteTitle'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(children:[
              Expanded(child:Text('Content',
                style:Theme.of(context).textTheme.titleSmall)),
              TextButton.icon(
                onPressed:()=>setState(()=>_preview=!_preview),
                icon:Icon(_preview?Icons.edit_outlined:Icons.visibility_outlined),
                label:Text(_preview?'Edit':'Preview'),
              ),
            ]),
            if(!_preview&&_canEdit)_formattingToolbar(),
            if(_preview)Card(elevation:0,child:Padding(
              padding:const EdgeInsets.all(12),
              child:Column(crossAxisAlignment:CrossAxisAlignment.start,
                children:[
                  for(final line in _body.text.split('\n').indexed)
                    _previewRow(line.$2,line.$1),
                ]),
            ))
            else TextField(
              controller: _body,
              readOnly: !_canEdit,
              maxLength: 30000, maxLines: 12, minLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr(context, 'noteBody'),
                hintText: tr(context, 'noteHint'),
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            Text(tr(context, 'visibility')),
            Wrap(
              spacing: 8,
              children: ['shared','private'].map((scope) => ChoiceChip(
                selected: _visibility == scope,
                label: Text(tr(context, scope)),
                onSelected: _busy || _editing ? null
                    : (_) => setState(() => _visibility = scope),
              )).toList(),
            ),
            const SizedBox(height: 5),
            Text(tr(context,
                _editing ? 'privacyAlreadyFixed' : 'privacyFixed'),
                style: Theme.of(context).textTheme.bodySmall),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'pinNote')),
              value: _pinned,
              onChanged: _busy || !_canEdit ? null
                  : (value) => setState(() => _pinned = value),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            if (_canEdit) FilledButton.icon(
              onPressed: _busy || _archived ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(tr(context, 'saveNote')),
            ),
            if (_editing && _canEdit) ...[
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: _busy ? null : _archiveOrRestore,
                child: Text(tr(context, _archived ? 'restore' : 'archive')),
              ),
            ],
            const SizedBox(height: 12),
            Text(tr(context, 'notesEditingInfo'),
              style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
