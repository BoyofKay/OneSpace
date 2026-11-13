import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/onespace_strings.dart';
import '../../core/current_space_cache.dart';
import 'list_item_rules.dart';
import '../sharing/object_permissions.dart';
import '../sharing/private_share_button.dart';
import '../sharing/share_grant_watcher.dart';

/// Lists and shopping use the same reliable data model, while each list has its
/// own privacy boundary and separate, realtime item stream.
class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key});
  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  final _client = Supabase.instance.client;
  String? _spaceId;
  Stream<List<Map<String, dynamic>>>? _stream;
  StreamSubscription<List<Map<String, dynamic>>>? _shareWatcher;
  bool _loading = true;
  bool _showArchived = false;
  String _kind = 'all';
  bool _copying=false;
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
      objectType: 'list',
      onChanged: () {
        if (!mounted || _spaceId != id) return;
        setState(() => _stream = _client.from('lists')
            .stream(primaryKey: ['id'])
            .eq('space_id', id)
            .order('created_at', ascending: false));
      },
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = await CurrentSpaceCache.instance.get();
      if (!mounted) return;
      setState(() {
        _spaceId = id;
        _stream = id == null ? null : _client
            .from('lists')
            .stream(primaryKey: ['id'])
            .eq('space_id', id)
            .order('created_at', ascending: false);
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

  Future<void> _editList({Map<String, dynamic>? existing}) async {
    final id = _spaceId;
    if (id == null) return;
    final controller = TextEditingController(
      text: existing?['title'] as String? ?? '',
    );
    String kind = existing?['kind'] as String? ?? 'checklist';
    String scope = existing?['visibility'] as String? ?? 'shared';
    bool saving = false;
    String? error;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, change) => SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20, 8, 20, 20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(context, existing == null ? 'createList' : 'editList'),
                        style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      maxLength: 120,
                      decoration: InputDecoration(
                        labelText: tr(context, 'listTitle'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(tr(context, 'listType')),
                    Wrap(
                      spacing: 8,
                      children: ['checklist', 'shopping'].map((value) => ChoiceChip(
                        selected: kind == value,
                        label: Text(tr(context, value)),
                        onSelected: existing != null || saving
                            ? null : (_) => change(() => kind = value),
                      )).toList(),
                    ),
                    const SizedBox(height: 12),
                    Text(tr(context, 'visibility')),
                    Wrap(
                      spacing: 8,
                      children: ['shared', 'private'].map((value) => ChoiceChip(
                        selected: scope == value,
                        label: Text(tr(context, value)),
                        onSelected: existing != null || saving
                            ? null : (_) => change(() => scope = value),
                      )).toList(),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(context, existing == null
                          ? 'privacyFixed' : 'privacyAlreadyFixed'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: saving ? null : () async {
                          final title = controller.text.trim();
                          if (title.isEmpty) {
                            change(() => error = tr(context, 'titleRequired'));
                            return;
                          }
                          change(() { saving = true; error = null; });
                          try {
                            if (existing == null) {
                              await _client.from('lists').insert({
                                'space_id': id,
                                'created_by': _client.auth.currentUser!.id,
                                'title': title,
                                'kind': kind,
                                'visibility': scope,
                              });
                            } else {
                              await _client.from('lists').update({
                                'title': title,
                              }).eq('id', existing['id'] as String)
                                .eq('space_id', id);
                            }
                            if (sheetContext.mounted) Navigator.pop(sheetContext);
                          } on PostgrestException catch (e) {
                            if (sheetContext.mounted) change(() => error = e.message);
                          } catch (_) {
                            if (sheetContext.mounted) {
                              change(() => error = tr(context, 'saveFailed'));
                            }
                          } finally {
                            if (sheetContext.mounted) change(() => saving = false);
                          }
                        },
                        child: Text(tr(context, 'save')),
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

  Future<void> _toggleReusable(Map<String,dynamic> item,bool enabled) async {
    try{
      await _client.from('lists').update({'is_template':enabled})
        .eq('id',item['id'].toString()).eq('space_id',_spaceId!);
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:Text(enabled?
          'Saved as reusable. Create a fresh copy whenever needed.':
          'No longer reusable. Existing copies are unchanged.')));
    }catch(_){
      if(mounted)setState(()=>_error='Could not update reusable checklist.');
    }
  }

  Future<void> _useTemplate(Map<String,dynamic> item) async {
    if(_copying||_spaceId==null)return;
    setState((){
      _copying=true;_error=null;
    });
    try{
      final now=DateTime.now();
      final date=now.year.toString().padLeft(4,'0')+'-'+
        now.month.toString().padLeft(2,'0')+'-'+
        now.day.toString().padLeft(2,'0');
      final newId=await _client.rpc('create_checklist_from_template',
        params:{'p_template_id':item['id'],'p_local_day':date});
      if(!mounted)return;
      await Navigator.of(context).push<void>(MaterialPageRoute<void>(
        builder:(_)=>ListItemsScreen(
          listId:newId.toString(),spaceId:_spaceId!,
          title:item['title'].toString()+' · '+date,
          isShopping:false,canEdit:true,
        )));
    }on PostgrestException catch(e){
      if(mounted)setState(()=>_error=e.message);
    }catch(_){
      if(mounted)setState(()=>_error='Unable to create today’s checklist.');
    }finally{
      if(mounted)setState(()=>_copying=false);
    }
  }

  Future<void> _setArchived(Map<String, dynamic> list, bool archive) async {
    if (archive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr(context, 'archiveList')),
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
      if (confirmed != true) return;
    }
    try {
      await _client.from('lists').update({
        'archived_at': archive
            ? DateTime.now().toUtc().toIso8601String() : null,
      }).eq('id', list['id'] as String);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr(context, 'saveFailed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:AppBar(title:const Text('Lists & checklists')),
      body:RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(tr(context, 'listsTitle'),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(tr(context, 'listsSubtitle')),
          const SizedBox(height: 16),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          if (_loading)
            const Padding(padding: EdgeInsets.all(36),
              child: Center(child: CircularProgressIndicator()))
          else if (_spaceId == null)
            Text(tr(context, 'noSpace'))
          else ...[
            FilledButton.icon(
              onPressed: () => _editList(),
              icon: const Icon(Icons.add),
              label: Text(tr(context, 'createList')),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 7,
              children: ['all', 'shopping', 'checklist','reusable'].map((value) =>
                ChoiceChip(
                  selected: _kind == value,
                  label: Text(value=='reusable'?'Reusable':tr(context,value)),
                  onSelected: (_) => setState(() => _kind = value),
                )).toList(),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'showArchived')),
              value: _showArchived,
              onChanged: (value) => setState(() => _showArchived = value),
            ),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text(tr(context, 'loadFailed'));
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final visible = snapshot.data!.where((entry) {
                  return (_showArchived || entry['archived_at'] == null) &&
                      (_kind == 'all' || entry['kind'] == _kind ||
                        (_kind=='reusable' && entry['is_template']==true));
                }).toList();
                if (visible.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(38),
                    child: Text(tr(context, 'noLists'), textAlign: TextAlign.center),
                  );
                }
                return Column(
                  children: visible.map((entry) {
                    final archived = entry['archived_at'] != null;
                    final shopping = entry['kind'] == 'shopping';
                    final canEdit = ObjectPermissions.canEdit(
                      visibility: entry['visibility'] as String,
                      createdBy: entry['created_by'] as String,
                      userId: _client.auth.currentUser!.id,
                    );
                    final canShare = ObjectPermissions.canManagePrivateShare(
                      visibility: entry['visibility'] as String,
                      createdBy: entry['created_by'] as String,
                      userId: _client.auth.currentUser!.id,
                    );
                    return Card(
                      elevation: 0,
                      child: Column(
                        children: [
                      ListTile(
                        leading: Icon(shopping
                            ? Icons.shopping_cart_outlined
                            : Icons.checklist_rounded),
                        title: Text(entry['title'] as String),
                        subtitle: Text([
                          tr(context, entry['kind'] as String),
                          tr(context, entry['visibility'] as String),
                          if (entry['is_template']==true) 'Reusable template',
                          if (entry['source_template_id']!=null) 'Daily copy',
                          if (archived) tr(context, 'archived'),
                          if (!canEdit) tr(context, 'viewOnly'),
                        ].join(' • ')),
                        onTap: archived ? null : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ListItemsScreen(
                              listId: entry['id'] as String,
                              title: entry['title'] as String,
                              isShopping: shopping,
                              canEdit: canEdit,
                              spaceId: _spaceId!,
                            ),
                          ),
                        ),
                        trailing: !canEdit ? const Icon(Icons.lock_outline)
                          : PopupMenuButton<String>(
                          tooltip: tr(context, 'actions'),
                          onSelected: (value) {
                            if (value == 'edit') _editList(existing: entry);
                            if (value == 'make_template') _toggleReusable(entry,true);
                            if (value == 'remove_template') _toggleReusable(entry,false);
                            if (value == 'use_today') _useTemplate(entry);
                            if (value == 'archive') _setArchived(entry, true);
                            if (value == 'restore') _setArchived(entry, false);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value:'edit',child:Text(tr(context,'rename'))),
                            if(!shopping&&!archived&&entry['is_template']!=true)
                              const PopupMenuItem(value:'make_template',
                                child:Text('Make reusable')),
                            if(!shopping&&!archived&&entry['is_template']==true)...[
                              const PopupMenuItem(value:'use_today',
                                child:Text('Create today’s copy')),
                              const PopupMenuItem(value:'remove_template',
                                child:Text('Stop reusing')),
                            ],
                            PopupMenuItem(
                              value: archived ? 'restore' : 'archive',
                              child: Text(tr(context, archived ? 'restore' : 'archive')),
                            ),
                          ],
                        ),
                      ),
                        if(entry['kind']=='checklist' &&
                           entry['is_template']==true && !archived)
                          Align(alignment:AlignmentDirectional.centerEnd,
                            child:TextButton.icon(
                              onPressed:_copying?null:()=>_useTemplate(entry),
                              icon:const Icon(Icons.copy_all_outlined),
                              label:const Text('Use today'))),
                        if (canShare)
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: PrivateShareButton(
                              objectType: 'list',
                              objectId: entry['id'] as String,
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
    ));
  }
}

class ListItemsScreen extends StatefulWidget {
  const ListItemsScreen({
    super.key,
    required this.listId,
    required this.title,
    required this.isShopping,
    required this.canEdit,
    required this.spaceId,
  });

  final String spaceId;
  final String listId;
  final String title;
  final bool isShopping;
  final bool canEdit;

  @override
  State<ListItemsScreen> createState() => _ListItemsScreenState();
}

class _ListItemsScreenState extends State<ListItemsScreen> {
  final _client = Supabase.instance.client;
  late Stream<List<Map<String, dynamic>>> _stream;
  StreamSubscription<List<Map<String, dynamic>>>? _revocationWatcher;
  bool _showRemoved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _stream = _makeStream();
    if (!widget.canEdit) {
      _revocationWatcher = watchObjectShares(
        client: _client,
        spaceId: widget.spaceId,
        objectType: 'list',
        onChanged: _validateAccess,
      );
    }
  }

  Stream<List<Map<String, dynamic>>> _makeStream() =>
      _client.from('list_items')
          .stream(primaryKey: ['id'])
          .eq('list_id', widget.listId)
          .order('created_at');

  Future<void> _validateAccess() async {
    try {
      final visible = await _client.from('lists')
          .select('id').eq('id', widget.listId).limit(1);
      if (!mounted) return;
      if (visible.isEmpty) {
        Navigator.of(context).pop();
      } else {
        setState(() => _stream = _makeStream());
      }
    } catch (_) {
      // Do not incorrectly sign a user out during a connection failure.
    }
  }

  @override
  void dispose() {
    _revocationWatcher?.cancel();
    super.dispose();
  }

  Future<void> _itemEditor({Map<String, dynamic>? existing}) async {
    if (!widget.canEdit) return;
    final title = TextEditingController(text: existing?['label'] as String? ?? '');
    final amount = TextEditingController(
      text: existing == null ? '1' : existing['quantity'].toString());
    final unit = TextEditingController(text: existing?['unit'] as String? ?? '');
    final note = TextEditingController(text: existing?['note'] as String? ?? '');
    bool saving = false;
    String? error;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, change) => SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20, 8, 20, 20 + MediaQuery.viewInsetsOf(sheetContext).bottom),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(context, existing == null ? 'addItem' : 'editItem'),
                      style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    TextField(
                      controller: title, maxLength: 200, autofocus: true,
                      decoration: InputDecoration(
                        labelText: tr(context, 'itemName'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (widget.isShopping) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: TextField(
                          controller: amount,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: tr(context, 'quantity'),
                            border: const OutlineInputBorder(),
                          ),
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: TextField(
                          controller: unit, maxLength: 24,
                          decoration: InputDecoration(
                            labelText: tr(context, 'unit'),
                            border: const OutlineInputBorder(),
                          ),
                        )),
                      ]),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: note, maxLength: 500, maxLines: 2,
                      decoration: InputDecoration(
                        labelText: tr(context, 'optionalNote'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (error != null) Text(error!,
                        style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: FilledButton(
                      onPressed: saving ? null : () async {
                        final label = title.text.trim();
                        final qty = widget.isShopping
                            ? double.tryParse(amount.text.trim()) : 1.0;
                        if (qty == null || !ListItemRules.isValid(
                            label: label,
                            quantity: qty,
                            unit: unit.text.trim(),
                            note: note.text.trim(),
                          )) {
                          change(() => error = tr(context, 'itemValidation'));
                          return;
                        }
                        change(() { saving = true; error = null; });
                        final fields = <String, dynamic>{
                          'label': label,
                          'quantity': qty,
                          'unit': widget.isShopping ? unit.text.trim() : '',
                          'note': note.text.trim(),
                        };
                        try {
                          if (existing == null) {
                            await _client.from('list_items').insert({
                              ...fields,
                              'list_id': widget.listId,
                              'created_by': _client.auth.currentUser!.id,
                            });
                          } else {
                            await _client.from('list_items')
                                .update(fields).eq('id', existing['id'] as String)
                                .eq('list_id', widget.listId);
                          }
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        } on PostgrestException catch (e) {
                          if (sheetContext.mounted) change(() => error = e.message);
                        } catch (_) {
                          if (sheetContext.mounted) {
                            change(() => error = tr(context, 'saveFailed'));
                          }
                        } finally {
                          if (sheetContext.mounted) change(() => saving = false);
                        }
                      },
                      child: Text(tr(context, 'save')),
                    )),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      title.dispose();
      amount.dispose();
      unit.dispose();
      note.dispose();
    }
  }

  Future<void> _update(String id, Map<String, dynamic> fields) async {
    if (!widget.canEdit) return;
    try {
      await _client.from('list_items').update(fields)
          .eq('id', id).eq('list_id', widget.listId);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr(context, 'saveFailed'));
    }
  }

  Future<void> _clearChecked() async {
    if (!widget.canEdit) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(context, 'clearChecked')),
        content: Text(tr(context, 'clearCheckedPrompt')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr(context, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr(context, 'clearChecked')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _client.from('list_items').update({
        'removed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('list_id', widget.listId).eq('checked', true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr(context, 'saveFailed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(tr(context, 'loadFailed')));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!;
          final active = all.where((row) => row['removed_at'] == null).toList();
          final visible = all.where((row) =>
              _showRemoved || row['removed_at'] == null).toList()
                ..sort((a,b) {
                  final aDone = a['checked'] == true ? 1 : 0;
                  final bDone = b['checked'] == true ? 1 : 0;
                  return aDone.compareTo(bDone);
                });
          final done = active.where((row) => row['checked'] == true).length;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(tr(context, widget.isShopping ? 'shopping' : 'checklist'),
                style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('$done / ${active.length} ${tr(context, 'completed')}'),
              const SizedBox(height: 12),
              if (_error != null) Text(_error!,
                  style: const TextStyle(color: Colors.red)),
              if (!widget.canEdit)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(tr(context, 'viewOnly')),
                ),
              if (widget.canEdit) FilledButton.icon(
                onPressed: () => _itemEditor(),
                icon: const Icon(Icons.add),
                label: Text(tr(context, 'addItem')),
              ),
              if (widget.canEdit && done > 0)
                TextButton.icon(
                  onPressed: _clearChecked,
                  icon: const Icon(Icons.done_all),
                  label: Text(tr(context, 'clearChecked')),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr(context, 'showRemoved')),
                value: _showRemoved,
                onChanged: (value) => setState(() => _showRemoved = value),
              ),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(42),
                  child: Text(tr(context, 'noItems'), textAlign: TextAlign.center),
                ),
              ...visible.map((row) {
                final removed = row['removed_at'] != null;
                final checked = row['checked'] == true;
                final qty = row['quantity'].toString();
                final subtitle = <String>[
                  if (widget.isShopping)
                    '$qty ${row['unit'] as String? ?? ''}'.trim(),
                  if ((row['note'] as String? ?? '').isNotEmpty)
                    row['note'] as String,
                  if (removed) tr(context, 'removed'),
                ].join(' • ');
                return Card(
                  elevation: 0,
                  child: CheckboxListTile(
                    value: checked,
                    onChanged: removed || !widget.canEdit ? null : (value) =>
                        _update(row['id'] as String, {'checked': value == true}),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(row['label'] as String,
                      style: TextStyle(
                        decoration: checked || removed
                            ? TextDecoration.lineThrough : null,
                      )),
                    subtitle: subtitle.isEmpty ? null : Text(subtitle),
                    secondary: !widget.canEdit ? const Icon(Icons.lock_outline)
                        : PopupMenuButton<String>(
                      tooltip: tr(context, 'actions'),
                      onSelected: (choice) {
                        if (choice == 'edit') {
                          _itemEditor(existing: row);
                        } else if (choice == 'remove') {
                          _update(
                            row['id'] as String,
                            {'removed_at': DateTime.now().toUtc().toIso8601String()},
                          );
                        } else if (choice == 'restore') {
                          _update(row['id'] as String, {'removed_at': null});
                        }
                      },
                      itemBuilder: (_) => [
                        if (!removed) ...[
                          PopupMenuItem(value: 'edit', child: Text(tr(context, 'edit'))),
                          PopupMenuItem(value: 'remove', child: Text(tr(context, 'remove'))),
                        ] else
                          PopupMenuItem(value: 'restore', child: Text(tr(context, 'restore'))),
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
