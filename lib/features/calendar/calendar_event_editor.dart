import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/onespace_strings.dart';
import '../../core/device_time_zone.dart';
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
  String? _forUser;
  bool _allDay=true;
  TimeOfDay _start=const TimeOfDay(hour:9,minute:0);
  TimeOfDay _end=const TimeOfDay(hour:10,minute:0);
  List<Map<String,dynamic>> _people=const [];
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
    _forUser=existing?['for_user_id']?.toString();
    final initialStart=DateTime.tryParse(existing?['starts_at']?.toString()??'')?.toLocal();
    final initialEnd=DateTime.tryParse(existing?['ends_at']?.toString()??'')?.toLocal();
    if(initialStart!=null){
      _allDay=false;
      _start=TimeOfDay.fromDateTime(initialStart);
      if(initialEnd!=null){_end=TimeOfDay.fromDateTime(initialEnd);}
    }
    _loadPeople();
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _loadPeople() async {
    try {
      final members=await _client.from('space_members').select('user_id')
        .eq('space_id',widget.spaceId);
      final ids=members.map((m)=>m['user_id'].toString()).toList();
      if(ids.isEmpty)return;
      final people=await _client.from('profiles').select('id,display_name')
        .inFilter('id',ids);
      if(mounted)setState(()=>_people=people);
    } catch (_) {}
  }
  Future<void> _pickTime(bool starting) async {
    final result=await showTimePicker(context:context,
      initialTime:starting?_start:_end);
    if(result!=null&&mounted)setState((){
      if(starting){_start=result;}else{_end=result;}
    });
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
      fields['for_user_id']=_forUser;
      if(_allDay){
        fields['starts_at']=null;
        fields['ends_at']=null;
        fields['zone_id']=null;
      } else {
        final start=DateTime(_date.year,_date.month,_date.day,_start.hour,_start.minute);
        final end=DateTime(_date.year,_date.month,_date.day,_end.hour,_end.minute);
        if(!end.isAfter(start))throw StateError('End time must be after start time');
        fields['starts_at']=start.toUtc().toIso8601String();
        fields['ends_at']=end.toUtc().toIso8601String();
        fields['zone_id']=await DeviceTimeZone.readPhone();
      }
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
          DropdownButtonFormField<String>(
            key:ValueKey('person_${_forUser}_${_people.length}'),
            initialValue:_forUser!=null && _people.any((p)=>p['id']==_forUser)?_forUser:'both',
            decoration:const InputDecoration(
              labelText:'Event belongs to',border:OutlineInputBorder()),
            items:[
              const DropdownMenuItem(value:'both',child:Text('Both of us')),
              for(final person in _people)
                DropdownMenuItem(value:person['id'].toString(),
                  child:Text(person['display_name']?.toString()??'Partner')),
            ],
            onChanged:!_canEdit||_saving?null:(v)=>
              setState(()=>_forUser=v=='both'?null:v),
          ),
          SwitchListTile(
            contentPadding:EdgeInsets.zero,
            title:const Text('All-day event'),
            value:_allDay,
            onChanged:!_canEdit||_saving?null:(v)=>setState(()=>_allDay=v),
          ),
          if(!_allDay)Row(children:[
            Expanded(child:OutlinedButton(
              onPressed:()=>_pickTime(true),
              child:Text('Start ${_start.format(context)}'))),
            const SizedBox(width:8),
            Expanded(child:OutlinedButton(
              onPressed:()=>_pickTime(false),
              child:Text('End ${_end.format(context)}'))),
          ]),
          const SizedBox(height:12),
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
