import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'invitation_code.dart';
import 'space_task_summary.dart';
import 'today_attention_rules.dart';
import 'today_attention_section.dart';
import '../../core/partner_clock_strip.dart';
import '../../core/device_time_zone.dart';
import '../../core/device_weather_service.dart';
import '../calendar/calendar_rules.dart';
import '../coordinate/activity_countdown_rules.dart';
import '../coordinate/activity_detail_screen.dart';
import '../../core/performance_timings.dart';
import '../../core/current_space_cache.dart';
import '../../core/home_member_names.dart';
import '../../l10n/onespace_strings.dart';

class SharedSpaceScreen extends StatefulWidget {
  const SharedSpaceScreen({
    super.key,
    this.onOpenPlans,
    this.onOpenLists,
    this.onOpenNotes,
    this.onOpenCalendar,
    this.onOpenMemories,
    this.onOpenGoals,
    this.onOpenCheckins,
    this.onOpenLetters,
    this.onOpenCoordinate,
    this.onOpenWorld,
    this.onOpenProfile,
    this.refreshToken = 0,
  });

  final VoidCallback? onOpenPlans;
  final VoidCallback? onOpenLists;
  final VoidCallback? onOpenNotes;
  final VoidCallback? onOpenCalendar;
  final VoidCallback? onOpenMemories;
  final VoidCallback? onOpenGoals;
  final VoidCallback? onOpenCheckins;
  final VoidCallback? onOpenLetters;
  final VoidCallback? onOpenCoordinate;
  final VoidCallback? onOpenWorld;
  final VoidCallback? onOpenProfile;
  final int refreshToken;

  @override
  State<SharedSpaceScreen> createState() => _SharedSpaceScreenState();
}

class _SharedSpaceScreenState extends State<SharedSpaceScreen>
    with WidgetsBindingObserver {
  final client = Supabase.instance.client;
  final invitationController = TextEditingController();
  String? spaceId;
  String? spaceName;
  int memberCount = 0;
  List<String> memberDisplayNames = const [];
  List<Map<String, dynamic>> clockMembers = const [];
  SpaceTaskSummary? taskSummary;
  int activeShoppingLists = 0;
  int activeOtherLists = 0;
  int activeNotes = 0;
  int activeCalendarEvents = 0;
  int activeMemories = 0;
  int activeGoals = 0;
  int achievedGoals = 0;
  int recentCheckins = 0;
  int activeActivities = 0;
  int completedActivities = 0;
  int importantActivities = 0;
  int upcomingActivities = 0;
  List<Map<String,dynamic>> recentDiscussions = const [];
  List<TodayAttentionItem> focusItems = const [];
  bool focusLoading=false;
  String? focusError;
  List<TodayCalendarEntry> nearEvents = const [];
  bool recentExpanded=false;
  List<Map<String,dynamic>> milestoneCountdowns=const [];
  String relationshipMode = 'not_set';
  String? partnerLabel;
  DateTime? lastMetOn;
  DateTime? nextMeetOn;
  DateTime? pendingInviteExpiry;
  bool loading = true;
  bool membershipResolved = false;
  bool summaryLoading = false;
  String? summaryIssue;
  int _requestVersion = 0;
  DateTime? _lastDeviceContextSync;
  bool _syncingDeviceContext = false;
  bool working = false;
  String? issue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    unawaited(_loadPartnerLabel());
  }

  @override
  void didUpdateWidget(covariant SharedSpaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken){
      _load();
      unawaited(_loadPartnerLabel());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && spaceId != null) {
      unawaited(_syncDeviceContext(force: true));
    }
  }

  Future<void> _syncDeviceContext({bool force = false}) async {
    if (_syncingDeviceContext || spaceId == null ||
        client.auth.currentUser == null) {
      return;
    }
    final now = DateTime.now();
    if (!force && _lastDeviceContextSync != null &&
        now.difference(_lastDeviceContextSync!) <
            const Duration(minutes: 15)) {
      return;
    }
    _lastDeviceContextSync = now;
    _syncingDeviceContext = true;
    try {
      final myRecord = clockMembers.where(
        (member) => member['is_me'] == true).toList();
      if (myRecord.isEmpty) {
        return;
      }
      final mine = myRecord.first;
      bool changed = false;
      try {
        final saved = mine['time_zone']?.toString();
        final device = await DeviceTimeZone.sync(client,
          storedZone: saved);
        changed = device != null && device != saved;
      } catch (_) {
        // System clock always remains usable without a network connection.
      }
      if (mine['city_weather_shared'] == true) {
        changed = await DeviceWeatherService.refreshIfEnabled(client)
            || changed;
      }
      if (changed && mounted) await _load();
    } finally {
      _syncingDeviceContext = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _requestVersion++;
    invitationController.dispose();
    super.dispose();
  }

  Future<void> _loadPartnerLabel() async {
    final me=client.auth.currentUser?.id;
    if(me==null)return;
    try{
      final profile=await client.from('profiles').select('partner_label,partner_labels')
        .eq('id',me).single();
      if(mounted){
        final labels=[for(final raw in (profile['partner_labels'] as List<dynamic>? ??const []))
          if(raw.toString().trim().isNotEmpty)raw.toString().trim()];
        final fallback=profile['partner_label']?.toString().trim();
        setState(()=>partnerLabel=labels.isNotEmpty
          ?labels[Random().nextInt(labels.length)]
          :fallback==null||fallback.isEmpty?null:fallback);
      }
    }catch(_){}
  }

  /// Countdown cards load after the dashboard RPC; their slower optional
  /// lookup never delays clocks, calendar, or attention cards.
  Future<void> _loadMilestones(String id,int request) async {
    final timer=Stopwatch()..start();
    try{
      final rows=await client.from('activity_components')
        .select('activity_id,label,payload,activities!inner(space_id,archived_at)')
        .eq('kind','countdown')
        .eq('activities.space_id',id)
        .isFilter('archived_at',null)
        .isFilter('activities.archived_at',null)
        .limit(80)
        .timeout(const Duration(seconds:10));
      if(!mounted||_requestVersion!=request||spaceId!=id)return;
      final now=DateTime.now();
      final found=<Map<String,dynamic>>[];
      for(final row in rows){
        final payload=row['payload'] as Map? ?? const {};
        final raw=payload['value']?.toString();
        final annual=payload['repeat_yearly']==true;
        final days=ActivityCountdownRules.remaining(raw,
          repeatYearly:annual,now:now);
        if(days==null)continue;
        found.add({
          'activity_id':row['activity_id'].toString(),
          'label':row['label']?.toString()??'Milestone',
          'date':raw,
          'days':days,
          'annual':annual,
        });
      }
      found.sort((a,b){
        final da=(a['days'] as int).abs();
        final db=(b['days'] as int).abs();
        return da.compareTo(db);
      });
      if(mounted&&_requestVersion==request){
        setState(()=>milestoneCountdowns=found.take(5).toList());
      }
    }catch(_){
      // Optional countdowns must never interrupt the main Today dashboard.
    }finally{
      PerformanceTimings.instance.record(
        'Home countdowns optional network',timer.elapsed);
    }
  }

  Widget _countdownPanel()=>ExpansionTile(
    tilePadding:EdgeInsets.zero,
    leading:const Icon(Icons.hourglass_bottom_outlined),
    title:Text('Our countdowns ('+
      milestoneCountdowns.length.toString()+')'),
    initiallyExpanded:true,
    children:[
      for(final item in milestoneCountdowns)
        ListTile(
          dense:true,
          leading:const Icon(Icons.event_available_outlined),
          title:Text(item['label'].toString()),
          subtitle:Text(item['date'].toString()+
            (item['annual']==true?' · Every year':'')),
          trailing:Text(ActivityCountdownRules.summary(
            item['date'].toString(),
            repeatYearly:item['annual']==true,
            now:DateTime.now()),
            style:Theme.of(context).textTheme.labelMedium),
          onTap:()=>_openFocusActivity(item['activity_id'].toString()),
        ),
    ],
  );

  Future<void> _loadComingUp(String id,int request) async{
    try{
      final raw=await client.rpc('onespace_coming_up',
        params:{'p_today':CalendarRules.sqlDate(DateTime.now())})
        .timeout(const Duration(seconds:12));
      if(!mounted||request!=_requestVersion||spaceId!=id)return;
      final results=<TodayCalendarEntry>[];
      if(raw is List){
        for(final item in raw){
          if(item is! Map)continue;
          final date=DateTime.tryParse(item['event_date']?.toString()??'');
          if(date==null)continue;
          results.add(TodayCalendarEntry(
            title:item['title']?.toString()??'Event',
            kind:item['kind']?.toString()??'event',
            date:date,
            source:item['source']?.toString()??'calendar',
            activityId:item['activity_id']?.toString(),
          ));
        }
      }
      if(mounted&&request==_requestVersion)setState(()=>nearEvents=results);
    }catch(_){
      // Keep the initial snapshot calendar fallback if the optional agenda fails.
    }
  }

  Future<void> _loadActionableFocus(String space,int request)async{
    try{
      final raw=await client.rpc('onespace_my_attention',
        params:{'p_today':CalendarRules.sqlDate(DateTime.now())})
        .timeout(const Duration(seconds:12));
      if(!mounted||request!=_requestVersion||spaceId!=space)return;
      setState((){
        focusItems=TodayAttentionItem.fromActionQueue(
          raw is List?raw:const []);
        focusLoading=false;
        focusError=null;
      });
    }catch(_){
      if(!mounted||request!=_requestVersion)return;
      setState((){
        focusLoading=false;
        focusError='Unable to load your attention queue.';
      });
    }
  }

  /// First load membership; render the space as soon as we have its ID.
  /// Remaining independent groups load concurrently, so one failing optional
  /// query cannot hide the entire dashboard.
  /// One authenticated RPC replaces eight HTTP round trips to Supabase.
  /// Every scalar count inside the RPC obeys the caller's existing RLS.
  Future<void> _load() async {
    final request = ++_requestVersion;
    final watch = Stopwatch()..start();
    if (!mounted) return;
    setState(() {
      loading = spaceId == null;
      summaryLoading = spaceId != null;
      issue = null;
      summaryIssue = null;
      focusLoading=true;
      focusError=null;
    });
    try {
      final result = await client.rpc('get_home_snapshot_v2',
            params: {'p_today': CalendarRules.sqlDate(DateTime.now())})
          .timeout(const Duration(seconds: 14));
      if (!mounted || request != _requestVersion) return;

      if (result == null) {
        CurrentSpaceCache.instance.seed(client.auth.currentUser!.id, null);
        setState(() {
          spaceId = null;
          spaceName = null;
          memberCount = 0;
          memberDisplayNames = const [];
          clockMembers = const [];
          taskSummary = null;
          activeShoppingLists = 0;
          activeOtherLists = 0;
          activeNotes = 0;
          activeCalendarEvents = 0;
          activeMemories = 0;
          activeGoals = 0;
          achievedGoals = 0;
          recentCheckins = 0;
          activeActivities = 0;
          completedActivities = 0;
          importantActivities = 0;
          upcomingActivities = 0;
          recentDiscussions = const [];
          focusItems = const [];
          focusLoading=false;
          nearEvents = const [];
          milestoneCountdowns=const [];
          relationshipMode = 'not_set';
          lastMetOn = null;
          nextMeetOn = null;
          pendingInviteExpiry = null;
          membershipResolved = true;
          summaryLoading = false;
          loading = false;
        });
      } else {
        final data = Map<String, dynamic>.from(result as Map);
        final memberLabel = tr(context, 'member');
        final meLabel = tr(context, 'me');
        final members = (data['members'] as List<dynamic>? ?? const []);
        final names = <String>[
          for (final raw in members)
            if (raw is Map)
              '${raw['name'] ?? memberLabel}'
              '${raw['is_me'] == true ? ' ($meLabel)' : ''}',
        ];
        int metric(String key) => (data[key] as num?)?.toInt() ?? 0;
        setState(() {
          spaceId = data['space_id']?.toString();
          spaceName = data['space_name']?.toString();
          memberCount = metric('member_count');
          memberDisplayNames = names;
          clockMembers = [
            for (final item in members)
              if (item is Map) Map<String, dynamic>.from(item),
          ];
          final rawExpiry = data['pending_invitation_expires_at'];
          pendingInviteExpiry = rawExpiry == null
              ? null : DateTime.tryParse(rawExpiry.toString());
          taskSummary = SpaceTaskSummary(
            openShared: metric('open_shared_tasks'),
            assignedToMe: metric('assigned_to_me'),
            myPrivate: metric('my_private_tasks'),
            completedShared: metric('completed_shared_tasks'),
          );
          activeShoppingLists = metric('shopping_lists');
          activeOtherLists = metric('other_lists');
          activeNotes = metric('notes');
          activeCalendarEvents = metric('calendar_entries');
          activeMemories = metric('memories_count');
          activeGoals = metric('active_goals');
          achievedGoals = metric('completed_goals');
          recentCheckins = metric('recent_checkins');
          activeActivities = metric('active_activities');
          completedActivities = metric('completed_activities');
          importantActivities = metric('important_activities');
          upcomingActivities = metric('upcoming_activities');
          final comments=<String,Map<String,dynamic>>{};
          for(final raw in data['recent_activity_comments'] as List<dynamic>? ?? const []){
            if(raw is! Map)continue;
            final entry=Map<String,dynamic>.from(raw);
            final id=entry['activity_id']?.toString();
            if(id==null||id.isEmpty)continue;
            if(!comments.containsKey(id)){
              entry['comment_count']=1;
              comments[id]=entry;
            }else{
              comments[id]!['comment_count']=
                (comments[id]!['comment_count'] as int)+1;
            }
          }
          recentDiscussions=comments.values.toList();
          // The action queue supersedes the legacy broad-priority snapshot.
          focusItems=const [];
          nearEvents = TodayAttentionItem.upcomingEvents(
            data['next_events'] as List<dynamic>? ?? const [],DateTime.now());
          relationshipMode = data['relationship_mode']?.toString() ?? 'not_set';
          lastMetOn = DateTime.tryParse(data['last_met_on']?.toString() ?? '');
          nextMeetOn = DateTime.tryParse(data['next_meet_on']?.toString() ?? '');
          membershipResolved = true;
          summaryLoading = false;
          loading = false;
        });
      }
      if (spaceId != null && result != null) {
        CurrentSpaceCache.instance.seed(
          client.auth.currentUser!.id,
          spaceId,
          memberNames: HomeMemberNames.parse(
            (result as Map)['members'],
          ),
        );
      }
      PerformanceTimings.instance.record('Home overview network', watch.elapsed);
      if (spaceId != null && mounted) {
        unawaited(_syncDeviceContext());
        unawaited(_loadActionableFocus(spaceId!,request));
        unawaited(_loadMilestones(spaceId!,request));
        unawaited(_loadComingUp(spaceId!,request));
      }
    } on PostgrestException catch (error) {
      PerformanceTimings.instance.record('Home overview failed', watch.elapsed);
      if (mounted && request == _requestVersion) {
        setState(() {
          issue = error.message;
          loading = false;
          summaryLoading = false;
        });
      }
    } catch (_) {
      PerformanceTimings.instance.record('Home overview failed', watch.elapsed);
      if (mounted && request == _requestVersion) {
        setState(() {
          issue = tr(context, 'loadedError');
          loading = false;
          summaryLoading = false;
        });
      }
    }
  }

  Future<void> _openFocusActivity(String activityId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ActivityScreen(id: activityId),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _snoozeFocus(TodayAttentionItem item,int days) async {
    final userId=client.auth.currentUser?.id;
    if(userId==null)return;
    final now=DateTime.now();
    final until=DateTime(now.year,now.month,now.day+days);
    try{
      await client.from('user_attention_snoozes').upsert({
        'source':item.source,
        'object_id':item.id,
        'user_id':userId,
        'snoozed_until':CalendarRules.sqlDate(until),
      },onConflict:'user_id,source,object_id');
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:Text('Hidden from your Today feed until '
          '${CalendarRules.sqlDate(until)}.')));
      await _load();
    } catch(_){
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:Text('Unable to snooze this item. Try again.')));
      }
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    setState(() {
      working = true;
      issue = null;
    });
    try {
      await action();
      if (mounted) await _load();
    } on PostgrestException catch (e) {
      if (mounted) setState(() => issue = e.message);
    } catch (_) {
      if (mounted) setState(() => issue = tr(context, 'actionError'));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _create() => _perform(() async {
        await client.rpc('create_space');
      });

  Future<void> _accept() async {
    final code = normalizedInvitationCode(invitationController.text);
    if (code == null) {
      setState(() => issue = tr(context, 'invalidInvite'));
      return;
    }
    await _perform(() async {
      await client.rpc('accept_invitation', params: {'p_token': code});
      invitationController.clear();
    });
  }

  Future<void> _invite() async {
    final id = spaceId;
    if (id == null) return;
    setState(() {
      working = true;
      issue = null;
    });
    try {
      final token = await client.rpc(
        'create_invitation',
        params: {'p_space_id': id},
      ) as String;
      await Clipboard.setData(ClipboardData(text: token));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr(context, 'inviteTitle')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, 'inviteCopied')),
                const SizedBox(height: 16),
                SelectableText(
                  token,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: token)),
              icon: const Icon(Icons.copy),
              label: Text(tr(context, 'copyAgain')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr(context, 'done')),
            ),
          ],
        ),
      );
      if (mounted) await _load();
    } on PostgrestException catch (e) {
      if (mounted) setState(() => issue = e.message);
    } catch (_) {
      if (mounted) setState(() => issue = tr(context, 'requestInviteError'));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _revokeInvite() async {
    final id = spaceId;
    if (id == null || pendingInviteExpiry == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(context, 'revokeTitle')),
        content: Text(tr(context, 'revokeMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr(context, 'keepInvitation')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr(context, 'revoke')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _perform(() async {
      await client.rpc('revoke_pending_invitation', params: {'p_space_id': id});
    });
  }

  int? _dayDistance(DateTime? target) {
    if (target == null) return null;
    final now=DateTime.now();
    return DateTime(target.year,target.month,target.day)
      .difference(DateTime(now.year,now.month,now.day)).inDays;
  }

  Widget _relationshipPanel(){
    final together=relationshipMode=='living_together';
    return Card(
      elevation:0,
      color:Color.alphaBlend(
        (together?const Color(0xFF40A48A):const Color(0xFF627FC1))
        .withValues(alpha:.09),Theme.of(context).colorScheme.surface),
      child:Padding(
        padding:const EdgeInsets.all(14),
        child:together?Row(children:[
          Icon(Icons.home_rounded,size:34,
            color:Theme.of(context).colorScheme.primary),
          const SizedBox(width:12),
          Expanded(child:Column(
            crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('Together under one roof',
              style:Theme.of(context).textTheme.titleMedium),
            const Text('One home, one shared space. ❤️'),
          ])),
        ]):PartnerClockStrip(
          members:clockMembers,relationshipMode:relationshipMode),
      ),
    );
  }

  Widget _meetingCounters(){
    final ago=_dayDistance(lastMetOn);
    final until=_dayDistance(nextMeetOn);
    if(ago==null&&until==null)return const SizedBox.shrink();
    return Card(elevation:0,child:Padding(
      padding:const EdgeInsets.all(14),child:Row(children:[
        if(ago!=null)Expanded(child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(tr(context,'lastMetLabel'),
              style:Theme.of(context).textTheme.bodySmall),
            Text(ago>=0?'Coming up':(-ago).toString()+' days ago',
              style:Theme.of(context).textTheme.titleSmall),
          ])),
        if(ago!=null&&until!=null)const SizedBox(width:12),
        if(until!=null)Expanded(child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(tr(context,'nextMeetingLabel'),
              style:Theme.of(context).textTheme.bodySmall),
            Text(until<0?'Meeting date passed':
              until==0?tr(context,'meetingToday'):
              until.toString()+' days to go',
              style:Theme.of(context).textTheme.titleSmall),
          ])),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            spaceId == null ? tr(context, 'ourSpace') :
              'Welcome back, ${clockMembers.where((m) => m['is_me'] == true).map((m) => m['name']?.toString() ?? '').firstOrNull ?? 'there'}',
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
          ),
          if(spaceId!=null && !loading && clockMembers.length>1)
            Padding(
              padding:const EdgeInsets.only(top:4,bottom:12),
              child:Text(
                'Your space with '+
                  (partnerLabel??clockMembers.where((member)=>
                    member['is_me']!=true).map((member)=>
                      member['name']?.toString()??'your partner'
                    ).firstOrNull??'your partner'),
                style:Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else const SizedBox(height:16),
          if (issue != null) ...[
            Text(issue!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],
          if (loading)
            Padding(
              padding: const EdgeInsets.all(36),
              child: Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 14),
                    Text(tr(context, 'openingSpace')),
                  ],
                ),
              ),
            )
          else if (!membershipResolved && spaceId == null) ...[
            Text(tr(context, 'loadedError')),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(tr(context, 'retry')),
            ),
          ]
          else if (spaceId == null) ...[
            _panel(
              tr(context, 'createSpaceTitle'),
              tr(context, 'createSpaceDescription'),
              Icons.favorite_border,
              FilledButton(
                onPressed: working ? null : _create,
                child: Text(tr(context, 'createSpaceButton')),
              ),
            ),
            const SizedBox(height: 14),
            _panel(
              tr(context, 'joinPartner'),
              tr(context, 'joinDescription'),
              Icons.people_outline,
              Column(
                children: [
                  TextField(
                    controller: invitationController,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: tr(context, 'invitationCode'),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: tr(context, 'pasteCode'),
                        icon: const Icon(Icons.content_paste),
                        onPressed: () async {
                          final clip = await Clipboard.getData('text/plain');
                          if (!mounted) return;
                          final text = clip?.text;
                          if (text != null) {
                            invitationController.text = text.trim();
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: working ? null : _accept,
                    child: Text(tr(context, 'joinSpace')),
                  ),
                ],
              ),
            ),
          ] else ...[
            _relationshipPanel(),
            if(lastMetOn!=null||nextMeetOn!=null)_meetingCounters(),
            const SizedBox(height:12),
            TodayAttentionSection(
              items:focusItems,
              loading:focusLoading,
              error:focusError,
              onRetry:()=>unawaited(_load()),
              onOpen:_openFocusActivity,
              onOpenPlans:widget.onOpenPlans,
              onOpenCheckins:widget.onOpenCheckins,
              onSnooze:_snoozeFocus,
            ),
            const SizedBox(height:16),
            TodayCalendarSection(entries:nearEvents,
              onOpen:widget.onOpenCalendar ?? () {},
              onOpenPlans:widget.onOpenPlans,
              onOpenActivity:_openFocusActivity),
            const SizedBox(height:12),
            if(milestoneCountdowns.isNotEmpty)...[
              _countdownPanel(),
              const SizedBox(height:8),
            ],
            if (memberCount < 2) _panel(
              spaceName ?? 'Our Space',
              memberCount == 2
                  ? tr(context, 'connected')
                  : tr(context, 'invitePartnerDescription'),
              Icons.favorite_rounded,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${tr(context, 'members')}: $memberCount / 2'),
                  const SizedBox(height: 8),
                  for (final memberName in memberDisplayNames)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(memberName)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (memberCount < 2) ...[
                    FilledButton.icon(
                      onPressed: working ? null : _invite,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: Text(pendingInviteExpiry == null
                          ? tr(context, 'createInvitation')
                          : tr(context, 'replaceInvitation')),
                    ),
                    if (pendingInviteExpiry != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${tr(context, 'invitationExpires')}: '
                        '${pendingInviteExpiry!.toLocal().toString().split('.').first}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      TextButton.icon(
                        onPressed: working ? null : _revokeInvite,
                        icon: const Icon(Icons.link_off),
                        label: Text(tr(context, 'revokeInvitation')),
                      ),
                    ],
                  ],
                  TextButton.icon(
                    onPressed: working ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: Text(tr(context, 'refreshStatus')),
                  ),
                ],
              ),
            ),
          ],
          if (spaceId != null) ...[
            ExpansionTile(
              tilePadding:EdgeInsets.zero,
              initiallyExpanded:false,
              onExpansionChanged:(value)=>setState(()=>recentExpanded=value),
              leading:const Icon(Icons.forum_outlined),
              title:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text('Recent discussions ('+recentDiscussions.length.toString()+')',
                  style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17)),
                if(!recentExpanded)Text(
                  recentDiscussions.isEmpty?'No conversations yet':
                  'Latest conversations from your Activities',
                  style:Theme.of(context).textTheme.bodySmall),
              ]),
              childrenPadding:const EdgeInsets.fromLTRB(8,0,8,10),
              children:[
                if(recentDiscussions.isEmpty)
                  const ListTile(title:Text('No recent discussions yet.')),
                for(final entry in recentDiscussions)Card(
                  elevation:0,
                  child:ListTile(
                    leading:const Icon(Icons.forum_outlined),
                    title:Text(entry['activity']?.toString()??'Activity'),
                    subtitle:Text(
                      (entry['author']?.toString()??'Partner')+': '+
                      (entry['message']?.toString()??'')+
                      ((entry['comment_count'] as int? ?? 1)>1?
                        ' · '+entry['comment_count'].toString()+' recent messages':''),
                      maxLines:2,overflow:TextOverflow.ellipsis),
                    onTap:(){
                      final id=entry['activity_id']?.toString();
                      if(id==null||id.isEmpty){
                        widget.onOpenCoordinate?.call();
                      }else{_openFocusActivity(id);}
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height:12),
            const Text('Explore our space', style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 8),
            LayoutBuilder(builder:(context,limits)=>GridView.count(
              crossAxisCount:limits.maxWidth>650?4:2,
              childAspectRatio:1.38,
              shrinkWrap:true,
              physics:const NeverScrollableScrollPhysics(),
              crossAxisSpacing:10,mainAxisSpacing:10,
              children:[
                _exploreCard('Activities',Icons.hub_outlined,widget.onOpenCoordinate,0),
                _exploreCard('Calendar',Icons.calendar_month_outlined,widget.onOpenCalendar,1),
                _exploreCard('To-dos',Icons.checklist_outlined,widget.onOpenPlans,2),
                _exploreCard('Notes',Icons.sticky_note_2_outlined,widget.onOpenNotes,3),
                _exploreCard('Lists',Icons.shopping_basket_outlined,widget.onOpenLists,4),
                _exploreCard('Letters',Icons.mark_email_unread_outlined,widget.onOpenLetters,5),
                _exploreCard('Memories',Icons.auto_stories_outlined,widget.onOpenMemories,6),
                _exploreCard('Check-ins',Icons.favorite_outline,widget.onOpenCheckins,7),
              ],
            )),
            const SizedBox(height: 8),
 
          ],
        ],
      ),
    );
  }

  Widget _exploreCard(String label,IconData icon,VoidCallback? open,int index){
    final colors=Theme.of(context).colorScheme;
    final color=[colors.primary,colors.tertiary,colors.secondary,
      colors.primary,colors.tertiary,colors.secondary,
      colors.primary,colors.tertiary][index];
    return Card(
      elevation:0,clipBehavior:Clip.antiAlias,
      color:Color.alphaBlend(color.withValues(alpha:.11),colors.surface),
      child:InkWell(
        onTap:open,
        child:Padding(padding:const EdgeInsets.all(9),
          child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
            CircleAvatar(radius:24,
              backgroundColor:color.withValues(alpha:.14),
              child:Icon(icon,color:color,size:25)),
            const SizedBox(height:9),
            Text(label,textAlign:TextAlign.center,maxLines:2,
              overflow:TextOverflow.ellipsis,
              style:Theme.of(context).textTheme.titleSmall),
          ]),
        ),
      ),
    );
  }

  Widget _panel(String title, String description, IconData icon, Widget action) {
    return Card(
      elevation: 0,
      color: const Color(0xFFE4F2F0),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 30, color: const Color(0xFF167E81)),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 14),
            action,
          ],
        ),
      ),
    );
  }
}
