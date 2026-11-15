import '../../core/form_kit.dart';
import '../../core/editor_scaffold.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/onespace_strings.dart';
import '../../core/device_time_zone.dart';
import '../sharing/object_permissions.dart';
import 'calendar_rules.dart';
import '../mentions/partner_mention_button.dart';
import 'package:onespace/l10n/phrases.dart';

/// Full page owns its controllers; avoids disposing text inputs during
/// bottom-sheet exit animations (a prior source of Flutter red screens).
class CalendarEventEditor extends StatefulWidget {
  const CalendarEventEditor({
    super.key,
    required this.spaceId,
    this.initialDate,
    this.existing,
    this.initialTitle = '',
    this.initialDetails = '',
    this.onCreated,
    this.initialTime,
  });
  /// R60: a time said by voice ("… at 7 pm") makes it a timed event.
  final TimeOfDay? initialTime;

  final String spaceId;
  final DateTime? initialDate;
  final Map<String, dynamic>? existing;
  /// R52: pre-filled from shared content ("Items to sort").
  final String initialTitle, initialDetails;
  /// R53: called with the new event's id so "Create from this" can link it.
  final Future<void> Function(String id)? onCreated;

  @override
  State<CalendarEventEditor> createState() => _CalendarEventEditorState();
}

class _CalendarEventEditorState extends State<CalendarEventEditor> with FormChangeTracker<CalendarEventEditor> {
 /// R55: current form values; Save turns on only when they change.
 @override String get signature=>[_title.text,_details.text,_date.toIso8601String(),_kind,_recurrence,_visibility,_forUser,_allDay,_start.hour,_start.minute,_end.hour,_end.minute].join('|');

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
  SpacePeople? _peopleMeta;
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
    _title = TextEditingController(text: existing?['title'] as String? ?? widget.initialTitle);
    _details = TextEditingController(text: existing?['details'] as String? ?? widget.initialDetails);
    _date = DateTime.tryParse(existing?['event_date'] as String? ?? '') ??
        widget.initialDate ?? DateTime.now();
    _kind = existing?['kind'] as String? ?? 'event';
    _recurrence = existing?['recurrence'] as String? ?? 'none';
    _visibility = existing?['visibility'] as String? ?? 'shared';
    _forUser=existing?['for_user_id']?.toString();
    final initialStart=DateTime.tryParse(existing?['starts_at']?.toString()??'')?.toLocal();
    final initialEnd=DateTime.tryParse(existing?['ends_at']?.toString()??'')?.toLocal();
    if(existing==null&&widget.initialTime!=null){
      _allDay=false;
      _start=widget.initialTime!;
      _end=TimeOfDay(hour:(widget.initialTime!.hour+1)%24,minute:widget.initialTime!.minute);
    }
    if(initialStart!=null){
      _allDay=false;
      _start=TimeOfDay.fromDateTime(initialStart);
      if(initialEnd!=null){_end=TimeOfDay.fromDateTime(initialEnd);}
    }
    _loadPeople();
    SpacePeople.load().then((p){ if (mounted) setState(() => _peopleMeta = p); });
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
        final created = await _client.from('space_events').insert({
          ...fields,
          'space_id': widget.spaceId,
          'created_by': _client.auth.currentUser!.id,
          'visibility': _visibility,
        }).select('id').single();
        await widget.onCreated?.call(created['id'].toString());
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

  String _timeLabel(TimeOfDay t) => MaterialLocalizations.of(context).formatTimeOfDay(t);

  @override
  Widget build(BuildContext context) => EditorScaffold(
   title: _editing ? tt('Edit event') : tt('Add event'),
   isNew:!_editing,isChanged:()=>changed,isComplete:()=>_canEdit && !_archived && _title.text.trim().isNotEmpty,
   listenTo:[_title,_details],saving:_saving,onSave:_save,
   meta: _people.isEmpty && _peopleMeta == null ? null : MetaStrip(
     people:_peopleMeta, showDate:false, enabled:_canEdit && !_saving,
     value:MetaValues(shared:_visibility=='shared',belongsTo:_forUser),
     onChanged:(v)=>setState((){
       if(!_editing)_visibility=v.shared?'shared':'private';
       _forUser=v.belongsTo;
       if(_visibility=='private')_forUser=_peopleMeta?.me;
     })),
   body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (!_canEdit)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(tr(context, 'viewOnly'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          if (_archived) Padding(padding: const EdgeInsets.only(bottom: 12),
            child: Text(tt('Removed · restore it from the ⋮ menu'), style: Theme.of(context).textTheme.bodySmall)),
          TextField(
            key: const Key('eventTitle'),
            controller: _title,
            readOnly: !_canEdit,
            autofocus: !_editing,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tt('What is happening? *'),
              hintText: tt('Dinner with friends, doctor visit…'),
              border: OutlineInputBorder(),
            ),
          ),
          ChoiceRow<String>(label: tt('Type'), options: {'event': tr(context, 'event'), 'occasion': tr(context, 'occasion')},
            icons: const {'event': Icons.event_outlined, 'occasion': Icons.celebration_outlined},
            selected: _kind,
            onSelected: (v) { if (_canEdit && !_saving && v != null) setState(() => _kind = v); }),
          FormSection(tt('When')),
          DateField(label: tt('Date'), required: true, value: _date, first: DateTime(1900), last: DateTime(2100, 12, 31),
            onChanged: (v) { if (v != null && _canEdit && !_saving) setState(() => _date = v); }),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OptionChip(label: tt('All day'), icon: Icons.wb_sunny_outlined, value: _allDay,
              onChanged: !_canEdit || _saving ? null : (v) => setState(() => _allDay = v)),
            if (!_allDay) ...[
              ActionChip(avatar: const Icon(Icons.schedule, size: 18),
                label: Text('${tt('Starts')} ${_timeLabel(_start)}'), onPressed: () => _pickTime(true)),
              ActionChip(avatar: const Icon(Icons.schedule_outlined, size: 18),
                label: Text('${tt('Ends')} ${_timeLabel(_end)}'), onPressed: () => _pickTime(false)),
            ],
          ]),
          const SizedBox(height: 14),
          ChoiceRow<String>(label: tt('Repeat'), options: const {'none': 'Once', 'yearly': 'Every year'},
            icons: const {'none': Icons.looks_one_outlined, 'yearly': Icons.event_repeat},
            selected: _recurrence,
            onSelected: (v) { if (_canEdit && !_saving && v != null) setState(() => _recurrence = v); }),
          FormSection(tt('More details')),
          TextField(
            controller: _details,
            maxLength: 2000,
            minLines: 2,
            maxLines: 6,
            readOnly: !_canEdit,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tr(context, 'eventDetails'),
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          if (_visibility == 'shared') Align(alignment: AlignmentDirectional.centerStart,
            child: PartnerMentionButton(spaceId:widget.spaceId,controller:_details,enabled:_canEdit)),
          if (_editing) Text(tt('Who can see it was set when it was created.'),
            style: Theme.of(context).textTheme.bodySmall),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(tt(_error!), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    ),
  );
}
