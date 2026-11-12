import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/onespace_strings.dart';
import 'note_draft_rules.dart';

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
  bool _loading = true;
  bool _showArchived = false;
  String _scope = 'all';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final member = await _client.from('space_members')
          .select('space_id')
          .eq('user_id', _client.auth.currentUser!.id)
          .limit(1);
      if (!mounted) return;
      final id = member.isEmpty ? null : member.first['space_id'] as String;
      setState(() {
        _spaceId = id;
        _stream = id == null ? null : _client.from('notes')
            .stream(primaryKey: ['id'])
            .eq('space_id', id)
            .order('updated_at', ascending: false);
      });
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
                    return Card(
                      elevation: 0,
                      child: ListTile(
                        leading: Icon(note['pinned'] == true
                            ? Icons.push_pin : Icons.sticky_note_2_outlined),
                        title: Text(note['title'] as String,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [
                            tr(context, note['visibility'] as String),
                            if (archived) tr(context, 'archived'),
                            if (body.isNotEmpty) body.replaceAll('\n',' '),
                          ].join(' • '),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openEditor(note: note),
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
  String? _error;

  bool get _editing => widget.existing != null;
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
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
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
    if (!_editing) return;
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
            if (_archived)
              Text(tr(context, 'archived'), style: const TextStyle(
                fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _title, maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr(context, 'noteTitle'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _body,
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
              onChanged: _busy ? null
                  : (value) => setState(() => _pinned = value),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || _archived ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(tr(context, 'saveNote')),
            ),
            if (_editing) ...[
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
