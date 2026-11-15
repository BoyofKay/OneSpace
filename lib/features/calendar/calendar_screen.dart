import '../../core/item_menu.dart';
import '../../core/record_list_top_actions.dart';
import '../../core/editor_scaffold.dart';
import '../../core/linked_items.dart';
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../../core/performance_timings.dart';
import '../../l10n/onespace_strings.dart';
import '../sharing/object_permissions.dart';
import '../sharing/private_share_button.dart';
import '../sharing/share_grant_watcher.dart';
import 'calendar_event_editor.dart';
import 'calendar_rules.dart';
import 'holiday_calendar_service.dart';
import '../occasions/occasions_screen.dart';
import '../../theme/appearance_settings_screen.dart';
import 'package:onespace/l10n/phrases.dart';

/// Date-based calendar MVP. RLS filters all server queries; yearly events are
/// calculated locally without moving birthdays across timezones.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.onOpenPlans, this.active = true,
    this.initialEventId});
  final VoidCallback? onOpenPlans;
  final String? initialEventId;
  final bool active;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _client = Supabase.instance.client;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = CalendarRules.day(DateTime.now());
  String? _spaceId;
  String? _error;
  bool _loading = true;
  bool _showArchived = false;
  /// R55 filter: who can see (all / shared / private).
  String _who = 'all';
  List<FilterGroupSpec> _filterGroups()=>[FilterGroupSpec(id:'who',label:tt('Who can see'),
    options:const {'all':'All','shared':'Shared','private':'Only me'},selected:_who,defaultValue:'all')];
  String _view='month';
  Map<String,String> _people=const {};
  List<Map<String, dynamic>> _events = const [];
  List<Map<String, dynamic>> _tasks = const [];
  List<Map<String, dynamic>> _daysOff=const [];
  List<Map<String,dynamic>> _occasions=const [];
  List<HolidayDay> _holidays=const [];
  final HolidayCalendarService _holidayService=HolidayCalendarService();
  String? _holidayError;
  int _extrasVersion=0;
  int _loadVersion = 0;
  String? _watchedSpace;
  RealtimeChannel? _changes;
  StreamSubscription<List<Map<String, dynamic>>>? _shareWatcher;
  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    if (widget.active) {
      // Recheck RLS on re-entry: access to a privately shared occasion may
      // have been revoked while this tab was not visible.
      _load();
    } else {
      _reloadDebounce?.cancel();
      _stopWatching();
    }
  }

  @override
  void dispose() {
    _loadVersion++;
    _extrasVersion++;
    _holidayService.close();
    _reloadDebounce?.cancel();
    _stopWatching();
    super.dispose();
  }

  void _stopWatching() {
    _watchedSpace = null;
    _shareWatcher?.cancel();
    _shareWatcher = null;
    final channel = _changes;
    _changes = null;
    if (channel != null) unawaited(_client.removeChannel(channel));
  }

  void _scheduleRefresh() {
    if (!mounted || !widget.active) return;
    _reloadDebounce?.cancel();
    // Coalesce bursts (bulk task edits and partner updates) into one fetch.
    _reloadDebounce = Timer(const Duration(milliseconds: 700), () {
      if (mounted && widget.active) _load();
    });
  }

  void _watchChanges(String id) {
    if (!widget.active || _watchedSpace == id) return;
    _stopWatching();
    _watchedSpace = id;
    final bySpace = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'space_id',
      value: id,
    );
    _changes = _client.channel('calendar-$id')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'space_events',
        filter: bySpace,
        callback: (_) => _scheduleRefresh(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'tasks',
        filter: bySpace,
        callback: (_) => _scheduleRefresh(),
      )
      .onPostgresChanges(event:PostgresChangeEvent.all,
        schema:'public',table:'occasion_plans',filter:bySpace,
        callback:(_)=>_scheduleRefresh(),)
      .onPostgresChanges(event:PostgresChangeEvent.all,
        schema:'public',table:'space_holiday_sources',filter:bySpace,
        callback:(_)=>_scheduleRefresh(),)
      .onPostgresChanges(
        event:PostgresChangeEvent.all,
        schema:'public',table:'personal_days_off',
        filter:bySpace,callback:(_)=>_scheduleRefresh(),
      )
      .subscribe();
    _shareWatcher = watchObjectShares(
      client: _client,
      spaceId: id,
      objectType: 'event',
      onChanged: _scheduleRefresh,
    );
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    final stopwatch = Stopwatch()..start();
    if (mounted) setState(() { _loading = _spaceId == null; _error = null; });
    try {
      final id = await CurrentSpaceCache.instance.get();
      if (!mounted || version != _loadVersion) return;
      if (id == null) {
        _stopWatching();
        setState(() {
          _spaceId = null;
          _events = const [];
          _tasks = const [];
          _daysOff=const [];
          _occasions=const [];
          _holidays=const [];
          _loading = false;
        });
        return;
      }
      _spaceId = id;
      _watchChanges(id);
      final cached=CurrentSpaceCache.instance.memberNamesFor(id);
      if(cached!=null){
        _people=cached;
      }else{
        unawaited(_loadCalendarNames(id));
      }
      final results = await Future.wait<List<Map<String, dynamic>>>([
        _client.from('space_events')
            .select('id,space_id,created_by,title,details,event_date,kind,recurrence,visibility,archived_at,for_user_id,starts_at,ends_at,zone_id')
            .eq('space_id', id).order('event_date').limit(500),
        _client.from('tasks')
            .select('id,title,target_date,status,visibility,created_by')
            .eq('space_id', id).eq('status', 'open').limit(500),
        _client.from('personal_days_off')
            .select('id,off_date,label,user_id')
            .eq('space_id',id).order('off_date').limit(500),
      ]).timeout(const Duration(seconds: 15));
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _events = results[0];
        _tasks = results[1];
        _daysOff=results[2];
        if(widget.initialEventId!=null){
          final event=results[0].where(
            (row)=>row['id']==widget.initialEventId).firstOrNull;
          final date=DateTime.tryParse(event?['event_date']?.toString()??'');
          if(date!=null){
            _selected=CalendarRules.day(date);
            _month=DateTime(date.year,date.month);
            _view='day';
          }
        }
        _loading = false;
      });
      PerformanceTimings.instance.record('Calendar first data', stopwatch.elapsed);
      unawaited(_loadExtras(id));
    } on PostgrestException catch (e) {
      if (mounted && version == _loadVersion) {
        setState(() { _error = e.message; _loading = false; });
      }
    } catch (_) {
      if (mounted && version == _loadVersion) {
        setState(() {
          _error = tr(context, 'loadFailed');
          _loading = false;
        });
      }
    }
  }

  /// Optional overlays never block or replace the ordinary calendar.
  Future<void> _loadExtras(String space)async{
    final request=++_extrasVersion;
    try{
      final rows=await _client.from('occasion_plans').select(
       'id,title,honoree_name,occasion_on,annual,kind,visibility,status,archived_at')
       .eq('space_id',space).limit(300);
      if(!mounted||request!=_extrasVersion||_spaceId!=space)return;
      setState(()=>_occasions=List<Map<String,dynamic>>.from(rows));
    }catch(_){ /* Main calendar remains usable. */ }
    try{
      final sources=await _client.from('space_holiday_sources')
       .select('country_code,enabled').eq('space_id',space);
      if(!mounted||request!=_extrasVersion||_spaceId!=space)return;
      final active=sources.where((x)=>x['enabled']==true)
        .map((x)=>x['country_code'].toString()).toSet();
      if(active.isEmpty){
        setState((){_holidays=[];_holidayError=null;});
        return;
      }
      final activeDate=_view=='month'?_month:_selected;
      final years=<int>{activeDate.year};
      if(activeDate.month==1)years.add(activeDate.year-1);
      if(activeDate.month==12)years.add(activeDate.year+1);
      final data=await Future.wait(years.map((y)=>_holidayService.forYearDetailed(y,active)));
      if(!mounted||request!=_extrasVersion)return;
      final missing=data.expand((x)=>x.unavailableCountries).toSet();
      setState((){
       _holidays=data.expand((x)=>x.days).toList();
       _holidayError=missing.isEmpty?null:
        'Some holiday sources could not load: '+missing.map(HolidayCatalog.label).join(', ');
      });
    }catch(_){
      if(mounted&&request==_extrasVersion)setState(
       ()=>_holidayError='Regional holidays are unavailable. Personal events are unaffected.');
    }
  }
  void _refreshExtras(){
    final space=_spaceId;
    if(space!=null)unawaited(_loadExtras(space));
  }
  List<HolidayDay> _holidaysOn(DateTime date){
    final day=CalendarRules.sqlDate(date);
    return _holidays.where((item)=>item.dayKey==day).toList();
  }
  List<Map<String,dynamic>> _occasionsOn(DateTime date){
    return _occasions.where((row){
      if(row['archived_at']!=null||row['status']=='cancelled')return false;
      final origin=DateTime.tryParse((row['occasion_on']??'').toString());
      if(origin==null)return false;
      if(row['annual']==true&&origin.month==2&&origin.day==29&&
         !CalendarRules.isValid(date.year,2,29)){
        return date.month==2&&date.day==28;
      }
      return CalendarRules.occursOn(
       original:origin,recurrence:row['annual']==true?'yearly':'none',selected:date);
    }).toList();
  }
  Widget _holidayTile(HolidayDay day)=>Card(elevation:0,child:ListTile(
    leading:Icon(Icons.celebration_outlined,
      color:Theme.of(context).colorScheme.tertiary),
    title:Text(tt(day.name)),
    subtitle:Text(tt(HolidayCatalog.label(day.country)+' · Regional holiday · '+day.source)),
  ));
  Widget _occasionTile(Map<String,dynamic> row)=>Card(elevation:0,child:ListTile(
    leading:Icon(Icons.cake_outlined,color:Theme.of(context).colorScheme.primary),
    title:Text(tt(row['title'].toString())),
    subtitle:Text(tt('Personal occasion · ')+
     ((row['honoree_name']??'').toString().isEmpty?'':row['honoree_name'].toString()+' · ')+
     (row['visibility']=='private'?'Only me':'Both of us')+
     (row['annual']==true?' · Annual':'')),
    trailing:const Icon(Icons.chevron_right),
    onTap:()async{
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder:(_)=>OccasionDetail(id:row['id'].toString())));
      if(mounted)_refreshExtras();
    },
  ));

  Future<void> _loadCalendarNames(String id) async {
    try {
      final members=await _client.from('space_members').select('user_id')
        .eq('space_id',id);
      final ids=members.map((entry)=>entry['user_id'].toString()).toList();
      if(ids.isEmpty)return;
      final people=await _client.from('profiles')
        .select('id,display_name').inFilter('id',ids);
      if(mounted&&_spaceId==id){
        setState(()=>_people={
          for(final person in people)
            person['id'].toString():person['display_name'].toString(),
        });
      }
    }catch(_){}
  }

  DateTime? _eventDate(Map<String,dynamic> event) {
    final timed=DateTime.tryParse(event['starts_at']?.toString()??'')?.toLocal();
    return timed ?? DateTime.tryParse(event['event_date']?.toString()??'');
  }

  bool _occurs(Map<String,dynamic> entry, DateTime day) {
    final date = _eventDate(entry);
    return date != null && CalendarRules.occursOn(
      original: date,
      recurrence: entry['recurrence'] as String? ?? 'none',
      selected: day,
    );
  }

  List<Map<String, dynamic>> _entriesOn(DateTime day) =>
    _events.where((e) => (_who=='all' || e['visibility']==_who) && (_showArchived || e['archived_at'] == null)
        && _occurs(e, day)).toList();

  List<Map<String,dynamic>> _offOn(DateTime day){
    final date=CalendarRules.sqlDate(day);
    return _daysOff.where((row)=>row['off_date']==date).toList();
  }

  Widget _offTile(Map<String,dynamic> item)=>Card(elevation:0,
    child:ListTile(
      leading:const Icon(Icons.weekend_outlined),
      title:Text(tt(item['label']?.toString()??'Day off')),
      subtitle:Text(tt('Day off · ')+
        (_people[item['user_id']?.toString()]??'Partner')),
    ));

  List<Map<String, dynamic>> _tasksOn(DateTime day) {
    final date = CalendarRules.sqlDate(day);
    return _tasks.where((e) => e['target_date'] == date).toList();
  }

  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    if (_spaceId == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CalendarEventEditor(
          spaceId: _spaceId!,
          initialDate: _selected,
          existing: existing,
        ),
      ),
    );
    if (mounted && changed == true) await _load();
  }

  Widget _weekAgenda() {
    final first=CalendarRules.day(_selected.subtract(
      Duration(days:_selected.weekday%7)));
    final days=List<DateTime>.generate(7,
      (i)=>first.add(Duration(days:i)));
    return Column(children:[
      Row(children:[
        IconButton(
          tooltip:tt('Previous week'),
          icon:const Icon(Icons.chevron_left),
          onPressed:(){setState(()=>
            _selected=_selected.subtract(const Duration(days:7)));
            _refreshExtras();},
        ),
        Expanded(child:Text(
          tt(CalendarRules.sqlDate(days.first)+' — '+
            CalendarRules.sqlDate(days.last)),
          textAlign:TextAlign.center)),
        IconButton(
          tooltip:tt('Next week'),
          icon:const Icon(Icons.chevron_right),
          onPressed:(){setState(()=>
            _selected=_selected.add(const Duration(days:7)));
            _refreshExtras();},
        ),
      ]),
      for(final date in days)
        Card(elevation:0,child:Column(children:[
          ListTile(
            title:Text(tt(MaterialLocalizations.of(context).formatMediumDate(date))),
            subtitle:Text(
              tt((_entriesOn(date).length+_tasksOn(date).length+
                _holidaysOn(date).length+_occasionsOn(date).length).toString()+
              ' shared calendar items and due dates')),
            trailing:const Icon(Icons.chevron_right),
            onTap:(){setState((){
              _selected=date;
              _view='day';
            });_refreshExtras();},
          ),
          for(final off in _offOn(date))_offTile(off),
          for(final holiday in _holidaysOn(date))_holidayTile(holiday),
          for(final occasion in _occasionsOn(date))_occasionTile(occasion),
          for(final event in _entriesOn(date))_eventTile(event),
          for(final task in _tasksOn(date))ListTile(
            dense:true,
            leading:const Icon(Icons.checklist),
            title:Text(tt(task['title']?.toString()??'To-do')),
            subtitle:Text(tt('Due date')),
            onTap:widget.onOpenPlans,
          ),
        ])),
    ]);
  }

  Future<void> _remindPartner(Map<String,dynamic> event) async {
    final space=_spaceId;
    final me=_client.auth.currentUser?.id;
    if(space==null||me==null)return;
    try{
      final members=await _client.from('space_members')
        .select('user_id').eq('space_id',space);
      final partner=members.where((row)=>row['user_id']!=me).firstOrNull;
      if(partner==null){
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content:Text(tt('Connect your partner first.'))));
        return;
      }
      await _client.from('calendar_partner_reminders').insert({
        'event_id':event['id'].toString(),
        'space_id':space,
        'recipient_id':partner['user_id'].toString(),
      });
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text(tt('Reminder sent to your partner.'))));
    }on PostgrestException catch(e){
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:Text(tt(e.code=='23505'
          ?'You already reminded your partner about this event today.'
          :'Could not send the reminder. Please try again.')),
      ));
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text(tt('Could not send the reminder.'))));
    }
  }

  /// R53: the event's Linked items, in a small sheet (tap opens, long-press unlinks).
  Future<void> _showLinked(Map<String,dynamic> event)=>showModalBottomSheet<void>(
    context:context,showDragHandle:true,
    builder:(ctx)=>SafeArea(child:Padding(
      padding:const EdgeInsetsDirectional.fromSTEB(16,0,16,20),
      child:Column(mainAxisSize:MainAxisSize.min,
        crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(tt(event['title']?.toString()??'Event'),
          style:Theme.of(ctx).textTheme.titleMedium),
        const SizedBox(height:8),
        LinkedItemsStrip(kind:LinkKind.event,id:event['id'].toString()),
        const SizedBox(height:6),
        Text(tt('Nothing shows here until something is linked, for example with Create from this.'),
          style:Theme.of(ctx).textTheme.bodySmall),
      ]))));

  Future<void> _emailEvent(Map<String,dynamic> event) async {
    final title=event['title']?.toString()??'Calendar event';
    final date=event['event_date']?.toString()??'';
    final details=event['details']?.toString()??'';
    final begin=DateTime.tryParse(event['starts_at']?.toString()??'')?.toLocal();
    final time=begin==null?'All day':TimeOfDay.fromDateTime(begin).format(context);
    final body='Event: '+title+'\nDate: '+date+'\nTime: '+time+'\n'+details;
    final destination=Uri(scheme:'mailto',queryParameters:{
      'subject':'OneSpace: '+title,
      'body':body,
    });
    var opened=false;
    try{
      opened=await launchUrl(destination,mode:LaunchMode.externalApplication);
    }catch(_){}
    if(!opened){
      await Clipboard.setData(ClipboardData(text:body));
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content:Text(tt('No email app available. Event copied.'))));
      }
    }
  }

  Widget _monthGrid() {
    final first = DateTime(_month.year, _month.month);
    final offset = first.weekday % 7; // Sunday is the first day of the week.
    final weekdays = [
      tr(context, 'sun'), tr(context, 'mon'), tr(context, 'tue'),
      tr(context, 'wed'), tr(context, 'thu'), tr(context, 'fri'),
      tr(context, 'sat'),
    ];
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: tr(context, 'previousMonth'),
              onPressed: () => setState(() {
                _month = DateTime(_month.year, _month.month - 1);
                _refreshExtras();
              }),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                tt(MaterialLocalizations.of(context).formatMonthYear(_month)),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: tr(context, 'nextMonth'),
              onPressed: () => setState(() {
                _month = DateTime(_month.year, _month.month + 1);
                _refreshExtras();
              }),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(children: [
          for (final label in weekdays)
            Expanded(child: Center(child: Text(tt(label),
              style: Theme.of(context).textTheme.labelSmall))),
        ]),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 42,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7, childAspectRatio: 0.96,
          ),
          itemBuilder: (context, index) {
            final date = DateTime(_month.year, _month.month, index + 1 - offset);
            final selected = CalendarRules.day(date) == _selected;
            final today = CalendarRules.day(date) ==
                CalendarRules.day(DateTime.now());
            final currentMonth = date.month == _month.month;
            final hasEvent = _events.any((entry) =>
                entry['archived_at'] == null && _occurs(entry, date));
            final hasTask = _tasksOn(date).isNotEmpty;
            final hasOff=_offOn(date).isNotEmpty;
            final hasHoliday=_holidaysOn(date).isNotEmpty;
            final hasOccasion=_occasionsOn(date).isNotEmpty;
            return InkWell(
              key: Key('day-${CalendarRules.sqlDate(date)}'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _selected = CalendarRules.day(date)),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
                  border: today && !selected
                      ? Border.all(color: Theme.of(context).colorScheme.primary) : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${date.day}',
                      style: TextStyle(
                        fontWeight: today || selected
                            ? FontWeight.bold : FontWeight.normal,
                        color: selected
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : currentMonth ? null : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    if (hasEvent || hasTask || hasOff || hasHoliday || hasOccasion)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if(hasHoliday) Icon(Icons.circle,size:7,
                            color:Theme.of(context).colorScheme.tertiary),
                          if(hasOccasion) Icon(Icons.circle,size:7,
                            color:Theme.of(context).colorScheme.secondary),
                          if (hasEvent) Icon(Icons.circle, size: 7,
                            color: selected ? Theme.of(context).colorScheme.onPrimaryContainer
                                : Theme.of(context).colorScheme.primary),
                          if(hasOff)Icon(Icons.circle,size:7,
                            color:selected?Theme.of(context).colorScheme.onPrimaryContainer:
                              Theme.of(context).colorScheme.tertiary),
                          if (hasTask) Icon(Icons.circle, size: 7,
                            color: selected ? Theme.of(context).colorScheme.onPrimaryContainer
                                : Theme.of(context).colorScheme.secondary),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _eventTile(Map<String, dynamic> event, {bool upcoming = false}) {
    final id = _client.auth.currentUser?.id ?? '';
    final visibility = event['visibility'] as String? ?? 'shared';
    final creator = event['created_by'] as String? ?? '';
    final canEdit = ObjectPermissions.canEdit(
      visibility: visibility, createdBy: creator, userId: id);
    final canShare = ObjectPermissions.canManagePrivateShare(
      visibility: visibility, createdBy: creator, userId: id);
    final sourceDate = _eventDate(event);
    final next = sourceDate == null ? null : CalendarRules.nextOccurrence(
      original: sourceDate,
      recurrence: event['recurrence'] as String? ?? 'none',
      today: DateTime.now(),
    );
    final countdown = next == null ? '' :
        '${CalendarRules.calendarDaysUntil(DateTime.now(),next)} '
            '${tr(context, 'daysAway')}';
    return Card(
      elevation: 0,
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              radius:17,
              backgroundColor:event['for_user_id']==null
                ? Theme.of(context).colorScheme.tertiaryContainer
                : event['for_user_id']==id
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.secondaryContainer,
              child:Icon(event['kind']=='occasion'
                ?Icons.celebration_outlined:Icons.event_outlined,size:19),
            ),
            title: Text(tt(event['title'] as String? ?? '')),
            subtitle: Text(tt([
              tr(context,event['kind'] as String? ?? 'event'),
              if (upcoming && countdown.isNotEmpty) countdown,
              if (!upcoming && sourceDate != null)
                CalendarRules.sqlDate(sourceDate),
              if (event['recurrence'] == 'yearly') tr(context, 'yearly'),
              event['for_user_id']==null?'Both':
                (_people[event['for_user_id']]??'Partner'),
              if(event['starts_at']!=null)
                TimeOfDay.fromDateTime(DateTime.parse(
                  event['starts_at'].toString()).toLocal()).format(context),
              if (visibility == 'private') tr(context, 'private'),
              if (!canEdit) tr(context, 'viewOnly'),
              if (event['archived_at'] != null) tr(context, 'archived'),
            ].join(' • '))),
            trailing:ItemMenu(kind:'event',recordId:event['id'].toString(),
              title:event['title']?.toString(),
              onOpen:()=>_openEditor(existing:event),openLabel:canEdit?'Edit':'Open',
              moreActions:[
                if(event['space_id']!=null)ItemMenuAction(tt('Create from this'),Icons.add_link,
                  ()=>createFromThis(context,
                    kind:LinkKind.event,id:event['id'].toString(),
                    spaceId:event['space_id'].toString(),
                    title:event['title']?.toString()??'Event',
                    date:DateTime.tryParse(event['event_date']?.toString()??''),
                    shared:event['visibility']!='private')),
                ItemMenuAction(tt('Linked items'),Icons.link,()=>_showLinked(event)),
                ItemMenuAction(tt('Share by email'),Icons.mail_outline,()=>_emailEvent(event)),
                if(visibility=='shared'&&event['archived_at']==null)
                  ItemMenuAction(tt('Remind partner now'),Icons.notifications_active_outlined,
                    ()=>_remindPartner(event)),
              ],
              table:canEdit?'space_events':null,
              removed:event['archived_at']!=null,onChanged:_load),
            onTap: () => _openEditor(existing: event),
          ),
          if (canShare)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: PrivateShareButton(
                objectType: 'event',
                objectId: event['id'] as String,
                onChanged: _load,
              ),
            ),
        ],
      ),
    );
  }

  Widget _selectedDay() {
    final events = _entriesOn(_selected);
    final tasks = _tasksOn(_selected);
    final off=_offOn(_selected);
    final holiday=_holidaysOn(_selected);
    final occasion=_occasionsOn(_selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tt(CalendarRules.sqlDate(_selected)),
          style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        if (events.isEmpty && tasks.isEmpty && off.isEmpty&&holiday.isEmpty&&occasion.isEmpty)
          Text(tr(context, 'noEventsOnDay')),
        ...off.map(_offTile),
        ...holiday.map(_holidayTile),
        ...occasion.map(_occasionTile),
        ...events.map((e) => _eventTile(e)),
        ...tasks.map((task) => Card(
          elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.checklist_outlined),
            title: Text(tt(task['title'] as String? ?? '')),
            subtitle: Text(tr(context, 'taskDue')),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onOpenPlans,
          ),
        )),
      ],
    );
  }

  Widget _dayTimeline() {
    final events=_entriesOn(_selected);
    final allDay=events.where((e)=>e['starts_at']==null).toList();
    final timed=events.where((e)=>e['starts_at']!=null).toList()
      ..sort((a,b)=>a['starts_at'].toString().compareTo(b['starts_at'].toString()));
    final tasks=_tasksOn(_selected);
    final off=_offOn(_selected);
    final holiday=_holidaysOn(_selected);
    final occasion=_occasionsOn(_selected);
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        IconButton(
          tooltip:tt('Previous day'),icon:const Icon(Icons.chevron_left),
          onPressed:(){setState(()=>
            _selected=_selected.subtract(const Duration(days:1)));
            _refreshExtras();}),
        Expanded(child:Text(
          tt(MaterialLocalizations.of(context).formatMediumDate(_selected)),
          textAlign:TextAlign.center,
          style:Theme.of(context).textTheme.titleMedium)),
        IconButton(
          tooltip:tt('Next day'),icon:const Icon(Icons.chevron_right),
          onPressed:(){setState(()=>
            _selected=_selected.add(const Duration(days:1)));
            _refreshExtras();}),
      ]),
      if(allDay.isNotEmpty||tasks.isNotEmpty||off.isNotEmpty||holiday.isNotEmpty||occasion.isNotEmpty)...[
        for(final d in off)_offTile(d),
        for(final d in holiday)_holidayTile(d),
        for(final d in occasion)_occasionTile(d),
        Text(tt('All day & deadlines'),
          style:Theme.of(context).textTheme.titleSmall),
        for(final event in allDay)_eventTile(event),
        for(final task in tasks)Card(elevation:0,child:ListTile(
          leading:const Icon(Icons.checklist_outlined),
          title:Text(tt(task['title']?.toString()??'To-do')),
          subtitle:Text(tt('Due date')),
          onTap:widget.onOpenPlans)),
        const SizedBox(height:12),
      ],
      for(var hour=0;hour<24;hour++)
        Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          SizedBox(width:54,child:Padding(
            padding:const EdgeInsets.only(top:10),
            child:Text(
              tt(hour.toString().padLeft(2,'0')+':00'),
              style:Theme.of(context).textTheme.labelSmall))),
          Expanded(child:Container(
            constraints:const BoxConstraints(minHeight:38),
            decoration:BoxDecoration(border:Border(top:BorderSide(
              color:Theme.of(context).colorScheme.outlineVariant))),
            child:Column(children:[
              for(final event in timed.where((e)=>
                DateTime.tryParse(e['starts_at'].toString())?.toLocal().hour==hour))
                _eventTile(event),
            ]),
          )),
        ]),
      if(events.isEmpty&&tasks.isEmpty&&off.isEmpty&&holiday.isEmpty&&occasion.isEmpty)
        Padding(padding:EdgeInsets.all(12),
          child:Text(tt('Nothing scheduled on this day.'))),
    ]);
  }



  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:Text(tt('Calendar')),actions:[
     RecordListTopActions(
      historyKinds:const ['event'],historyTitle:tt('Calendar'),
      showHistory:_showArchived,
      onToggleHistory:()=>setState(()=>_showArchived=!_showArchived),
      groups:_filterGroups(),
      onApply:(v)=>setState(()=>_who=v['who']!)),
    ],bottom:filterShowingBar(_filterGroups(),removed:_showArchived,
      onClear:()=>setState((){_showArchived=false;_who='all';}))),
    floatingActionButton:_spaceId==null?null:AddFab(label:tt('Add event'),onPressed:()=>_openEditor()),
    body:RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(tr(context, 'calendar'),
          style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(tr(context, 'calendarSubtitle')),
        const SizedBox(height: 12),
        const SeasonalThemePreview(compact:true),
        const SizedBox(height: 12),
        if (_error != null) ...[
          Text(tt(_error!), style:TextStyle(color:Theme.of(context).colorScheme.error)),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: Text(tr(context, 'retry')),
          ),
        ],
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_spaceId == null)
          Text(tr(context, 'noSpace'))
        else ...[
          const SizedBox(height: 12),
          // Regional holidays are managed in Settings > Preferences.
          if(_holidayError!=null)Padding(padding:const EdgeInsets.all(8),
            child:Text(tt(_holidayError!),style:Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments:[
              ButtonSegment(value:'month',label:Text(tt('Month'))),
              ButtonSegment(value:'week',label:Text(tt('Week'))),
              ButtonSegment(value:'day',label:Text(tt('Day'))),
            ],
            selected:{_view},
            onSelectionChanged:(value){
             setState((){
              _view=value.first;
              if(_view=='month')_month=DateTime(_selected.year,_selected.month);
             });
             _refreshExtras();
            },
          ),
          if(_view=='month')Card(
            elevation:0,
            child:Padding(padding:const EdgeInsets.all(9),child:_monthGrid()),
          ),
          if(_view=='week')_weekAgenda(),
          const SizedBox(height: 12),
          if(_view=='month')_selectedDay(),
          if(_view=='day')_dayTimeline(),
          const SizedBox(height: 24),

          if (_showArchived) ..._events.where((e) =>
              e['archived_at'] != null).map((e) => _eventTile(e)),
          const SizedBox(height: 12),
          Text(tr(context, 'calendarScopeInfo'),
            style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    ),
  ));
}
