import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/onespace_strings.dart';
import '../sharing/object_permissions.dart';
import 'calendar_rules.dart';

/// Full page owns its controllers; avoids disposing text inputs during
/// bottom-sheet exit animations (a prior source of Flutter red screens).
class CalendarEventEditor extends StatefulWidget {
  const CalendarEventEditor({
    super.key,
    required this.spaceId,
    this.initialDate,
    this.existing,
  });

  final String spaceId;
  final DateTime? initialDate;
  final Map<String, dynamic>? existing;

  @override
  State<CalendarEventEditor> createState() => _CalendarEventEditorState();
}

class _CalendarEventEditorState extends State<CalendarEventEditor> {
  final _client = Supabase.instance.client;
  late final TextEditingController _title;
  late final TextEditingController _details;
  late DateTime _date;
  late String _kind;
  late String _recurrence;
  late String _visibility;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.existing != null;
  bool get _archived => widget.existing?['archived_at'] != null;
  bool get _canEdit => !_editing || ObjectPermissions.canEdit(
      visibility: widget.existing!['visibility'] as String,
      createdBy: widget.existing!['created_by'] as String,
      userId: _client.auth.currentUser!.id,
    );

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _title = TextEditingController(text: existing?['title'] as String? ?? '');
    _details = TextEditingController(text: existing?['details'] as String? ?? '');
    _date = DateTime.tryParse(existing?['event_date'] as String? ?? '') ??
        widget.initialDate ?? DateTime.now();
    _kind = existing?['kind'] as String? ?? 'event';
    _recurrence = existing?['recurrence'] as String? ?? 'none';
    _visibility = existing?['visibility'] as String? ?? 'shared';
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    if (!_canEdit || _saving) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_saving || !_canEdit || _archived) return;
    final title = _title.text.trim();
    final details = _details.text.trim();
    if (title.isEmpty || title.length > 120 || details.length > 2000) {
      setState(() => _error = tr(context, 'eventValidation'));
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final fields = <String,dynamic>{
        'title': title,
        'details': details,
        'event_date': CalendarRules.sqlDate(_date),
        'kind': _kind,
        'recurrence': _recurrence,
      };
      if (!_editing) {
        await _client.from('space_events').insert({
          ...fields,
          'space_id': widget.spaceId,
          'created_by': _client.auth.currentUser!.id,
          'visibility': _visibility,
        });
      } else {
        final rows = await _client.from('space_events')
          .update(fields)
          .eq('id', widget.existing!['id'] as String)
          .eq('space_id', widget.spaceId)
          .select('id');
        if (rows.isEmpty) throw StateError('Event is no longer editable');
      }
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr(context, 'saveFailed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleArchive() async {
    if (!_editing || !_canEdit || _saving) return;
    if (!_archived) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr(context, 'archiveEvent')),
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
      if (confirm != true || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      await _client.from('space_events').update({
        'archived_at': _archived ? null : DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.existing!['id'] as String);
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr(context, 'saveFailed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, _editing ? 'editEvent' : 'newEvent'))),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (!_canEdit)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(tr(context, 'viewOnly'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          if (_archived) Text(tr(context, 'archived')),
          TextField(
            key: const Key('eventTitle'),
            controller: _title,
            readOnly: !_canEdit,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tr(context, 'eventTitle'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Text(tr(context, 'calendarType')),
          Wrap(spacing: 8, children: ['event','occasion'].map((kind) =>
            ChoiceChip(
              label: Text(tr(context, kind)),
              selected: _kind == kind,
              onSelected: !_canEdit || _saving ? null
                : (_) => setState(() => _kind = kind),
            )).toList()),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: !_canEdit || _saving ? null : _pickDate,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(CalendarRules.sqlDate(_date)),
          ),
          const SizedBox(height: 12),
          Text(tr(context, 'repeat')),
          Wrap(spacing: 8, children: ['none','yearly'].map((option) =>
            ChoiceChip(
              label: Text(tr(context, option)),
              selected: _recurrence == option,
              onSelected: !_canEdit || _saving ? null
                  : (_) => setState(() => _recurrence = option),
            )).toList()),
          const SizedBox(height: 12),
          TextField(
            controller: _details,
            maxLength: 2000,
            maxLines: 4,
            readOnly: !_canEdit,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tr(context, 'eventDetails'),
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Text(tr(context, 'visibility')),
          Wrap(spacing: 8, children: ['shared','private'].map((visibility) =>
            ChoiceChip(
              label: Text(tr(context, visibility)),
              selected: _visibility == visibility,
              onSelected: _editing || _saving ? null
                  : (_) => setState(() => _visibility = visibility),
            )).toList()),
          Text(
            tr(context, _editing ? 'privacyAlreadyFixed' : 'privacyFixed'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          if (_canEdit && !_archived)
            FilledButton.icon(
              key: const Key('eventSave'),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(tr(context, 'save')),
            ),
          if (_editing && _canEdit) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _saving ? null : _toggleArchive,
              icon: Icon(_archived ? Icons.unarchive_outlined
                  : Icons.archive_outlined),
              label: Text(tr(context, _archived ? 'restore' : 'archive')),
            ),
          ],
        ],
      ),
    ),
  );
}
