import 'event_time_rules.dart';
import '../../core/form_kit.dart';
import '../../core/editor_scaffold.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/onespace_strings.dart';
import '../../core/device_time_zone.dart';
import '../../core/zone_time.dart';
import '../../core/app_env.dart';
import '../sharing/object_permissions.dart';
import 'calendar_rules.dart';
import '../mentions/partner_mention_button.dart';
import 'package:onespace/l10n/phrases.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/repeat_control.dart';
import '../reminders/reminder_repeat_rules.dart';

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
 @override String get signature=>[_title.text,_details.text,_location.text,_date.toIso8601String(),_repeat.preset,_repeat.interval,(_repeat.weekdays.toList()..sort()).join(','),_repeat.until,_remind,_visibility,_forUser,_allDay,_start.hour,_start.minute,_end.hour,_end.minute,_zoneChoice].join('|');

  final _client = Supabase.instance.client;
  late final TextEditingController _title;
  late final TextEditingController _details;
  late final TextEditingController _location;
  late DateTime _date;
  late String _kind;
  /// R66: same Repeat control as reminders.
  late ReminderRepeat _repeat;
  /// R66: "Remind us before" — none · morning · 1h · 1d · 1w.
  String _remind = 'none';
  late String _visibility;
  bool _saving = false;
  String? _forUser;
  bool _allDay=true;
  TimeOfDay _start=const TimeOfDay(hour:9,minute:0);
  TimeOfDay _end=const TimeOfDay(hour:10,minute:0);
  List<Map<String,dynamic>> _people=const [];
  /// QA: whose clock the start and end times are typed in.
  String _zoneChoice='mine';
  String? _myZone,_partnerZone,_partnerFirst;
  bool get _zonesDiffer=>ZoneTime.differs(_myZone,_partnerZone,_date);
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
    _location = TextEditingController(text: existing?['location']?.toString() ?? '');
    _repeat = existing?['repeat_rule'] is Map
      ? ReminderRepeat.fromRule(existing!['repeat_rule'])
      : existing?['recurrence'] == 'yearly' ? const ReminderRepeat(preset: 'yearly') : const ReminderRepeat();
    _visibility = existing?['visibility'] as String? ??
      (!OneSpaceEnv.usesLegacyBackend && widget.spaceId.isEmpty ? 'private' : 'shared');
    _forUser=existing?['for_user_id']?.toString();
    final initialStart=DateTime.tryParse(existing?['starts_at']?.toString()??'')?.toLocal();
    final initialEnd=DateTime.tryParse(existing?['ends_at']?.toString()??'')?.toLocal();
    if(existing==null&&widget.initialTime!=null){
      _allDay=false;
      _start=widget.initialTime!;
      _end=EventTimeRules.endFor(widget.initialTime!);
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
    _location.dispose();
    super.dispose();
  }

  Future<void> _loadPeople() async {
    if(!OneSpaceEnv.usesLegacyBackend && widget.spaceId.isEmpty)return;
    try {
      final members=await _client.from('space_members').select('user_id')
        .eq('space_id',widget.spaceId);
      final ids=members.map((m)=>m['user_id'].toString()).toList();
      if(ids.isEmpty)return;
      final people=await _client.from('profiles').select('id,display_name,time_zone')
        .inFilter('id',ids);
      final me=_client.auth.currentUser?.id;
      final phone=await DeviceTimeZone.readPhone();
      if(mounted)setState((){
        _people=people;
        for(final p in people){
          if(p['id']==me){_myZone=phone??p['time_zone']?.toString();}
          else{
            _partnerZone=p['time_zone']?.toString();
            _partnerFirst=(p['display_name']??'').toString().trim().split(RegExp(r'\s+')).first;
          }
        }
        _myZone??=phone;
        // An event saved in the partner's clock opens in that clock.
        final saved=widget.existing?['zone_id']?.toString();
        final start=DateTime.tryParse(widget.existing?['starts_at']?.toString()??'');
        if(!OneSpaceEnv.usesLegacyBackend&&_zonesDiffer&&saved!=null&&saved==_partnerZone&&start!=null){
          _zoneChoice='partner';
          final s0=ZoneTime.wall(start,saved);
          _start=TimeOfDay.fromDateTime(s0);
          final end=DateTime.tryParse(widget.existing?['ends_at']?.toString()??'');
          if(end!=null)_end=TimeOfDay.fromDateTime(ZoneTime.wall(end,saved));
          markClean();
        }
      });
    } catch (_) {}
  }
  Future<void> _pickTime(bool starting) async {
    final result=await showTimePicker(context:context,
      initialTime:starting?_start:_end);
    if(result==null||!mounted)return;
    setState((){
      _error=null;
      if(starting){
        if(!EventTimeRules.validStart(result)){
          _error='Choose a start before 23:59 so the event can end after it.';
          return;
        }
        // The end follows the start by one hour; it can be changed after.
        _start=result;_end=EventTimeRules.endFor(result);
      }else if(EventTimeRules.validEnd(_start,result)){
        _end=result;
      }else{
        _error='The end time must be after the start time.';
      }
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
    if(!OneSpaceEnv.usesLegacyBackend && widget.spaceId.isEmpty &&
      _visibility=='shared'){
      setState(()=>_error='Connect with a partner before sharing an event.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final fields = <String,dynamic>{
        'title': title,
        'details': details,
        'event_date': CalendarRules.sqlDate(_date),
        'kind': _kind,
        'location': _location.text.trim().isEmpty ? null : _location.text.trim(),
        // Plain "every year" keeps the old marker so countdowns stay simple.
        'recurrence': _repeat.preset == 'yearly' && _repeat.interval == 1 && _repeat.until == null ? 'yearly' : 'none',
        'repeat_rule': _eventRule(),
      };
      // QA: who it is for (participants) is independent of who can see it.
      fields['for_user_id']=_forUser;
      if(_allDay){
        fields['starts_at']=null;
        fields['ends_at']=null;
        fields['zone_id']=null;
      } else {
        final usePartner=!OneSpaceEnv.usesLegacyBackend&&_zoneChoice=='partner'&&_zonesDiffer;
        final zone=usePartner?_partnerZone:await DeviceTimeZone.readPhone();
        final start=ZoneTime.instant(_date.year,_date.month,_date.day,_start.hour,_start.minute,zone);
        final end=ZoneTime.instant(_date.year,_date.month,_date.day,_end.hour,_end.minute,zone);
        if(!end.isAfter(start)){
          if(mounted)setState((){_saving=false;_error='The end time must be after the start time.';});
          return;
        }
        fields['starts_at']=start.toIso8601String();
        fields['ends_at']=end.toIso8601String();
        fields['zone_id']=zone;
      }
      if (!_editing) {
        final created = await _client.from('space_events').insert({
          ...fields,
          if (!OneSpaceEnv.usesLegacyBackend && _visibility=='private')
            'private_space_id':_client.auth.currentUser!.id
          else 'space_id': widget.spaceId,
          'created_by': _client.auth.currentUser!.id,
          'visibility': _visibility,
        }).select('id').single();
        await _createReminder(created['id'].toString(), title);
        // Do not link account-owned events into shared workspace objects.
        if(OneSpaceEnv.usesLegacyBackend || _visibility=='shared')
          await widget.onCreated?.call(created['id'].toString());
      } else {
        var query=_client.from('space_events')
          .update(fields).eq('id',widget.existing!['id'] as String);
        if(OneSpaceEnv.usesLegacyBackend)query=query.eq('space_id',widget.spaceId);
        final rows=await query.select('id');
        if (rows.isEmpty) throw StateError('Event is no longer editable');
        await _createReminder(widget.existing!['id'] as String, title);
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

  Map<String, dynamic>? _eventRule() {
    if (!_repeat.repeats) return null;
    if (_repeat.preset == 'yearly' && _repeat.interval == 1 && _repeat.until == null) return null;
    final rule = _repeat.toRule(start: _date, timeZone: 'UTC')!;
    rule.remove('times'); rule.remove('tz');
    return rule;
  }

  /// R66: one tap to remind the people it belongs to, linked to the event
  /// (the reminder stops if the event is removed).
  Future<void> _createReminder(String eventId, String title) async {
    if (_remind == 'none') return;
    final base = _allDay
      ? DateTime(_date.year, _date.month, _date.day, 9)
      : DateTime(_date.year, _date.month, _date.day, _start.hour, _start.minute);
    final due = switch (_remind) {
      '1h' => base.subtract(const Duration(hours: 1)),
      '1d' => base.subtract(const Duration(days: 1)),
      '1w' => base.subtract(const Duration(days: 7)),
      _ => base,
    };
    if (!due.isAfter(DateTime.now())) return;
    final me = _client.auth.currentUser!.id;
    final audience = _visibility == 'private' || _forUser == me ? 'me' : _forUser == null ? 'both' : 'partner';
    try {
      final personal=!OneSpaceEnv.usesLegacyBackend && _visibility=='private';
      await _client.from('reminders').insert({
        if(personal) 'private_space_id':me
        else 'space_id':widget.spaceId,
        'title':title.length>160?title.substring(0,160):title,
        'details':_location.text.trim(),'due_at':due.toUtc().toIso8601String(),
        'visibility':_visibility,'audience':personal?'me':audience,
        if(!personal)...{'source_kind':'calendar','source_id':eventId},
      });
    } catch (_) {/* The event is saved; the reminder can be added from Reminders. */}
  }

  String _timeLabel(TimeOfDay t) => MaterialLocalizations.of(context).formatTimeOfDay(t);

  @override
  Widget build(BuildContext context) => EditorScaffold(
   title: _editing ? tt('Edit event') : tt('Add event'),
   isNew:!_editing,isChanged:()=>changed,isComplete:()=>_canEdit && !_archived && _title.text.trim().isNotEmpty,
   listenTo:[_title,_details,_location],saving:_saving,onSave:_save,
   meta: _people.isEmpty && _peopleMeta == null ? null : MetaStrip(personal:widget.spaceId.isEmpty,
     people:_peopleMeta, showDate:false, enabled:_canEdit && !_saving,
     linked:OneSpaceEnv.usesLegacyBackend,
     value:MetaValues(shared:_visibility=='shared',belongsTo:_forUser),
     onChanged:(v)=>setState((){
       if(!_editing)_visibility=(OneSpaceEnv.usesLegacyBackend ||
         widget.spaceId.isNotEmpty)&&v.shared?'shared':'private';
       _forUser=v.belongsTo;
       if(OneSpaceEnv.usesLegacyBackend&&_visibility=='private')_forUser=_peopleMeta?.me;
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
          if (!OneSpaceEnv.usesLegacyBackend && !_allDay && _zonesDiffer) ...[
            const SizedBox(height: 10),
            ChoiceRow<String>(label: tt('These times are in'),
              options: {
                'mine': '${tt('My time')} · ${ZoneTime.city(_myZone)}',
                'partner': '${tt(_partnerFirst?.isNotEmpty == true ? "${_partnerFirst!}'s time" : "Partner's time")} · ${ZoneTime.city(_partnerZone)}',
              },
              icons: const {'mine': Icons.person_outline, 'partner': Icons.favorite_border},
              selected: _zoneChoice,
              onSelected: (v) { if (v != null && _canEdit && !_saving) setState(() => _zoneChoice = v); }),
            Text(tt(_zoneChoice == 'partner'
              ? 'Saved in ${ZoneTime.city(_partnerZone)} time. Each of you sees it in your own local time.'
              : 'Saved in your time. Your partner sees it in their local time.'),
              style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 14),
          RepeatControl(value: _repeat, start: _date, enabled: _canEdit && !_saving,
            onChanged: (r) => setState(() => _repeat = r)),
          const SizedBox(height: 6),
          ChoiceRow<String>(label: tt(_visibility=='private'?
            'Remind me before':'Remind us before'),
            options: _allDay
              ? const {'none': 'No reminder', 'morning': 'That morning', '1d': 'A day before', '1w': 'A week before'}
              : const {'none': 'No reminder', '1h': 'An hour before', '1d': 'A day before', '1w': 'A week before'},
            selected: _remind,
            onSelected: (v) { if (_canEdit && !_saving) setState(() => _remind = v ?? 'none'); }),
          if (!OneSpaceEnv.usesLegacyBackend && _visibility=='private' &&
              _remind!='none')
            Text(tt('Your private reminder is saved independently. '
              'Removing this event will not automatically cancel it.'),
              style:Theme.of(context).textTheme.bodySmall),
          FormSection(tt('Where')),
          TextField(
            controller: _location,
            readOnly: !_canEdit,
            maxLength: 300,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: tt('Location'),
              hintText: tt('Address or place name'),
              prefixIcon: const Icon(Icons.place_outlined),
              suffixIcon: _location.text.trim().isEmpty ? null : IconButton(
                tooltip: tt('Open in Maps'), icon: const Icon(Icons.map_outlined),
                onPressed: () => launchUrl(Uri.https('www.google.com', '/maps/search/',
                  {'api': '1', 'query': _location.text.trim()}), mode: LaunchMode.externalApplication)),
              border: const OutlineInputBorder())),
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
          if (_visibility == 'shared' && widget.spaceId.isNotEmpty)
            Align(alignment: AlignmentDirectional.centerStart,
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
