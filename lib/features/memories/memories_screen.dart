import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../../core/performance_timings.dart';
import '../../l10n/onespace_strings.dart';
import '../calendar/calendar_rules.dart';
import '../sharing/object_permissions.dart';
import '../sharing/private_share_button.dart';
import '../sharing/share_grant_watcher.dart';

class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key});

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  final _client = Supabase.instance.client;
  String? _spaceId;
  Stream<List<Map<String, dynamic>>>? _stream;
  StreamSubscription<List<Map<String,dynamic>>>? _grants;
  bool _loading = true;
  bool _archived = false;
  String _scope = 'all';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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
        _stream = id == null ? null : _createStream(id);
        _loading = false;
      });
      if (id != null) {
        _grants = watchObjectShares(
          client: _client, spaceId: id, objectType: 'memory',
          onChanged: () {
            if (mounted && _spaceId == id) {
              setState(() => _stream = _createStream(id));
            }
          },
        );
      }
      PerformanceTimings.instance.record('Memories setup', timer.elapsed);
    } on PostgrestException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = tr(context,'loadFailed'); _loading = false; });
    }
  }

  Future<void> _edit({Map<String,dynamic>? existing}) async {
    final id = _spaceId;
    if (id == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) =>
        MemoryEditorScreen(spaceId: id, existing: existing)),
    );
    if (mounted && changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'memories'))),
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
            const SizedBox(height: 14),
            Wrap(spacing: 8, children: ['all','shared','private'].map((value) =>
              ChoiceChip(
                label: Text(tr(context,value)),
                selected: _scope == value,
                onSelected: (_) => setState(() => _scope = value),
              )).toList()),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _archived,
              title: Text(tr(context,'showArchived')),
              onChanged: (v) => setState(() => _archived = v),
            ),
            StreamBuilder<List<Map<String,dynamic>>>(
              stream: _stream,
              builder: (context,snapshot) {
                if (snapshot.hasError) return Text(tr(context,'loadFailed'));
                if (!snapshot.hasData) return const Center(
                    child: CircularProgressIndicator());
                final shown = snapshot.data!.where((m) =>
                  (_archived || m['archived_at'] == null) &&
                  (_scope == 'all' || m['visibility'] == _scope))
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
                        leading: Icon(memory['pinned'] == true
                            ? Icons.push_pin : Icons.auto_stories_outlined),
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
            Text(tr(context,'memoriesNoPhotosYet'),
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
  const MemoryEditorScreen({super.key,required this.spaceId,this.existing});
  final String spaceId;
  final Map<String,dynamic>? existing;

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
    appBar: AppBar(title: Text(tr(context,_editing?'editMemory':'newMemory'))),
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
