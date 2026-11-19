import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'invitation_code.dart';
import 'invitation_link_inbox.dart';
import '../../core/app_env.dart';
import 'invitation_qr.dart';
import '../places/places_screen.dart';
import '../counters/counters_screen.dart';
import '../../core/phone_calendar_sync.dart';
import 'space_task_summary.dart';
import 'today_attention_rules.dart';
import 'today_attention_section.dart';
import '../../core/partner_clock_strip.dart';
import '../../core/device_time_zone.dart';
import '../../core/device_weather_service.dart';
import '../calendar/calendar_rules.dart';
import '../coordinate/activity_countdown_rules.dart';
import '../coordinate/activity_detail_screen.dart';
import '../connect/partner_gestures_screen.dart';
import '../connect/shared_experiences_screen.dart';
import '../world/trips_screen.dart';
import '../occasions/occasions_screen.dart';
import '../reminders/reminders_screen.dart';
import '../notifications/notifications_screen.dart';
import '../search/global_search_screen.dart';
import '../world/world_contacts_screen.dart';
import 'today_talk_window.dart';
import 'love_nudge_rules.dart';
import '../quick_add/quick_add_sheet.dart';
import '../share_in/items_to_sort_screen.dart';
import '../memories/memories_screen.dart';
import '../../core/partner_time_zones.dart';
import '../../core/performance_timings.dart';
import '../../theme/appearance_settings_screen.dart';
import '../../core/current_space_cache.dart';
import '../../core/home_member_names.dart';
import '../../l10n/onespace_strings.dart';
import '../../core/first_name.dart';
import 'package:onespace/l10n/phrases.dart';

class SharedSpaceScreen extends StatefulWidget {
  const SharedSpaceScreen({
    super.key,
    this.onOpenPlans,
    this.onOpenNotes,
    this.onOpenCalendar,
    this.onOpenMemories,
    this.onOpenCheckins,
    this.onOpenLetters,
    this.onOpenCoordinate,
    this.onOpenWorld,
    this.onOpenProfile,
    this.refreshToken = 0,
  });

  final VoidCallback? onOpenPlans;
  final VoidCallback? onOpenNotes;
  final VoidCallback? onOpenCalendar;
  final VoidCallback? onOpenMemories;
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
  List<TodayAttentionItem> focusItems = const [];
  bool focusLoading=false;
  String? focusError;
  List<TodayCalendarEntry> nearEvents = const [];
  List<Map<String,dynamic>> milestoneCountdowns=const [];
  String relationshipMode = 'not_set';
  String? partnerLabel;
  bool partnerLabelIsEndearment=false;
  // R49 Today 2.0
  List<Map<String,dynamic>> sinceAway=const [];
  int sinceAwayTotal=0;
  bool sinceAwayCollapsed=false;
  int lettersBadge=0;
  int itemsToSort=0;
  Map<String,dynamic>? onThisDay;
  DateTime? lastLoveSent;
  DateTime? loveDismissedOn;
  Set<String> hiddenOnThisDay=const {};
  List<StatedSchedule> schedulesMine=const [];
  List<StatedSchedule> schedulesPartner=const [];
  String? myZone;
  Map<String,dynamic>? activeTrip;
  DateTime? lastUpdated;
  bool offline=false;
  bool _cacheTried=false;
  DateTime? lastMetOn;
  DateTime? nextMeetOn;
  DateTime? pendingInviteExpiry;
  bool inviteCollapsed = true;
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
    InvitationLinkInbox.instance.addListener(_useIncomingInvite);
    _useIncomingInvite();
    unawaited(PhoneCalendarSync.syncNow());
    unawaited(_loadPartnerLabel());
    unawaited(_loadHiddenOnThisDay());
    unawaited(_loadLoveDismissed());
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
    InvitationLinkInbox.instance.removeListener(_useIncomingInvite);
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
        setState((){
          partnerLabelIsEndearment=labels.isNotEmpty;
          partnerLabel=labels.isNotEmpty
            ?labels[Random().nextInt(labels.length)]
            :fallback==null||fallback.isEmpty?null:fallback;
        });
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

  Future<void> _openReminder(String id)async{
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder:(_)=>RemindersScreen(initialReminderId:id)));
    if(mounted)unawaited(_load());
  }

  /// First load membership; render the space as soon as we have its ID.
  /// Remaining independent groups load concurrently, so one failing optional
  /// query cannot hide the entire dashboard.
  /// One authenticated RPC replaces eight HTTP round trips to Supabase.
  /// Every scalar count inside the RPC obeys the caller's existing RLS.
  String get _cacheKey=>'onespace_today_v1_${client.auth.currentUser?.id}';
  String get _seenKey=>'onespace_today_seen_v1_${client.auth.currentUser?.id}';

  /// R49 (B-07): show the last saved Today straight away, then refresh.
  Future<void> _loadSavedCopy() async {
    if(_cacheTried)return;
    _cacheTried=true;
    final watch=Stopwatch()..start();
    try{
      final raw=await SharedPreferencesAsync().getString(_cacheKey);
      if(raw==null||!mounted||spaceId!=null)return;
      final saved=jsonDecode(raw);
      if(saved is! Map)return;
      final data=Map<String,dynamic>.from(saved['data'] as Map);
      _apply(data,seenBefore:null);
      setState(()=>lastUpdated=DateTime.tryParse(saved['saved_at']?.toString()??''));
      PerformanceTimings.instance.record('Today saved copy shown',watch.elapsed);
    }catch(_){/* A damaged saved copy is simply ignored. */}
  }

  Future<void> _load() async {
    final request = ++_requestVersion;
    final watch = Stopwatch()..start();
    if (!mounted) return;
    await _loadSavedCopy();
    if (!mounted || request != _requestVersion) return;
    setState(() {
      loading = spaceId == null;
      summaryLoading = spaceId != null;
      issue = null;
      summaryIssue = null;
      focusLoading=focusItems.isEmpty;
      focusError=null;
    });
    try {
      // B-08: one server call for every Today section.
      final result = await client.rpc('onespace_today',
            params: {'p_today': CalendarRules.sqlDate(DateTime.now())})
          .timeout(const Duration(seconds: 14));
      if (!mounted || request != _requestVersion) return;
      final prefs=SharedPreferencesAsync();
      if (result == null) {
        CurrentSpaceCache.instance.seed(client.auth.currentUser!.id, null);
        await prefs.remove(_cacheKey);
        if(!mounted)return;
        _apply(null,seenBefore:null);
      } else {
        final data = Map<String, dynamic>.from(result as Map);
        final seen=DateTime.tryParse(await prefs.getString(_seenKey)??'');
        if(!mounted||request!=_requestVersion)return;
        _apply(data,seenBefore:seen);
        final now=DateTime.now();
        setState((){lastUpdated=now;offline=false;});
        unawaited(prefs.setString(_cacheKey,jsonEncode({
          'saved_at':now.toIso8601String(),'data':data})));
        final newest=sinceAway.isEmpty?null:
          DateTime.tryParse(sinceAway.first['created_at']?.toString()??'');
        if(newest!=null)unawaited(prefs.setString(_seenKey,newest.toIso8601String()));
        CurrentSpaceCache.instance.seed(
          client.auth.currentUser!.id,
          spaceId,
          memberNames: HomeMemberNames.parse(data['members']),
        );
      }
      PerformanceTimings.instance.record('Today one call network', watch.elapsed);
      if (spaceId != null && mounted) {
        unawaited(_syncDeviceContext());
        unawaited(_loadMilestones(spaceId!,request));
      }
    } catch (error) {
      PerformanceTimings.instance.record('Today failed', watch.elapsed);
      if (!mounted || request != _requestVersion) return;
      setState(() {
        loading = false;
        summaryLoading = false;
        focusLoading=false;
        if(spaceId!=null){
          // B-07: keep the saved copy on screen with "Last updated · Retry".
          offline=true;
        }else{
          issue = error is PostgrestException ? error.message : tr(context, 'loadedError');
        }
      });
    }
  }

  void _apply(Map<String,dynamic>? data,{required DateTime? seenBefore}){
    if(data==null){
      setState(() {
        spaceId = null;
        spaceName = null;
        memberCount = 0;
        memberDisplayNames = const [];
        clockMembers = const [];
        taskSummary = null;
        focusItems = const [];
        focusLoading=false;
        nearEvents = const [];
        milestoneCountdowns=const [];
        sinceAway=const [];
        sinceAwayTotal=0;
        relationshipMode = 'not_set';
        lastMetOn = null;
        nextMeetOn = null;
        pendingInviteExpiry = null;
        membershipResolved = true;
        summaryLoading = false;
        loading = false;
      });
      return;
    }
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
    final away=data['since_away'] is Map?Map<String,dynamic>.from(data['since_away'] as Map):const <String,dynamic>{};
    final awayItems=[
      for(final raw in (away['items'] as List<dynamic>? ?? const []))
        if(raw is Map)Map<String,dynamic>.from(raw),
    ];
    final newest=awayItems.isEmpty?null:
      DateTime.tryParse(awayItems.first['created_at']?.toString()??'');
    final schedules=[
      for(final raw in (data['schedules'] as List<dynamic>? ?? const []))
        if(raw is Map)Map<String,dynamic>.from(raw),
    ];
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
      focusItems=TodayAttentionItem.fromActionQueue(
        data['attention'] is List?data['attention'] as List:const []);
      focusLoading=false;
      focusError=null;
      nearEvents=_parseComingUp(data['coming_up']);
      sinceAway=awayItems;
      sinceAwayTotal=(away['total'] as num?)?.toInt()??awayItems.length;
      // After you have seen them once, the same updates fold into one line.
      sinceAwayCollapsed=newest!=null&&seenBefore!=null&&!newest.isAfter(seenBefore);
      final badges=data['badges'] is Map?data['badges'] as Map:const {};
      lettersBadge=(badges['letters'] as num?)?.toInt()??0;
      itemsToSort=(badges['items_to_sort'] as num?)?.toInt()??0;
      schedulesMine=[for(final x in schedules)if(x['is_me']==true)StatedSchedule.fromJson(x)];
      schedulesPartner=[for(final x in schedules)if(x['is_me']!=true)StatedSchedule.fromJson(x)];
      myZone=schedules.where((x)=>x['is_me']==true)
        .map((x)=>x['time_zone']?.toString()).firstOrNull;
      lastLoveSent=DateTime.tryParse(data['last_love_sent_at']?.toString()??'')?.toLocal();
      onThisDay=data['on_this_day'] is Map?
        Map<String,dynamic>.from(data['on_this_day'] as Map):null;
      activeTrip=data['active_trip'] is Map?
        Map<String,dynamic>.from(data['active_trip'] as Map):null;
      relationshipMode = data['relationship_mode']?.toString() ?? 'not_set';
      lastMetOn = DateTime.tryParse(data['last_met_on']?.toString() ?? '');
      nextMeetOn = DateTime.tryParse(data['next_meet_on']?.toString() ?? '');
      membershipResolved = true;
      summaryLoading = false;
      loading = false;
    });
  }

  List<TodayCalendarEntry> _parseComingUp(Object? raw){
    final results=<TodayCalendarEntry>[];
    if(raw is! List)return results;
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
        experienceId:item['source']=='experience'?item['id']?.toString():null,
        tripId:item['trip_id']?.toString(),
        occasionId:item['occasion_id']?.toString(),
        reminderId:item['source']=='reminder'?item['id']?.toString():null,
      ));
    }
    return results;
  }

  Future<void> _openFocusActivity(String activityId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ActivityScreen(id: activityId),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openAttentionActivity(String id) async{
    final user=client.auth.currentUser?.id;
    if(user!=null){
      try{
        // Opening a requested Activity acknowledges its mention and reply
        // notifications for this viewer; it never edits the Activity itself.
        await client.from('space_notifications').update({
          'read_at':DateTime.now().toUtc().toIso8601String(),
        }).eq('recipient_id',user).eq('activity_id',id)
          .inFilter('kind',['mention','reply'])
          .isFilter('read_at',null);
      }catch(_){
        // Opening the Activity is always more important than read status.
      }
    }
    if(!mounted)return;
    await _openFocusActivity(id);
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
        content:Text(tt('Hidden from your Today feed until '
          '${CalendarRules.sqlDate(until)}.'))));
      await _load();
    } catch(_){
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:Text(tt('Unable to snooze this item. Try again.'))));
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
      await InvitationLinkInbox.instance.clear();
    });
  }

  void _useIncomingInvite() {
    final code = InvitationLinkInbox.instance.pendingCode;
    if (code == null || invitationController.text == code) return;
    invitationController.text = code;
    invitationController.selection =
        TextSelection.collapsed(offset: code.length);
    if (mounted) setState(() {});
  }

  bool get _hasActiveInvite => pendingInviteExpiry != null &&
      pendingInviteExpiry!.isAfter(DateTime.now());

  /// Only the person who created the invitation can read its code under RLS.
  /// Reusing it does not write to the database and cannot extend its expiry.
  Future<String?> _activeInvitationCode(String space) async {
    final user = client.auth.currentUser?.id;
    if (user == null) return null;
    final row = await client.from('space_invitations')
        .select('token')
        .eq('space_id', space)
        .eq('invited_by', user)
        .isFilter('accepted_at', null)
        .isFilter('revoked_at', null)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('expires_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return normalizedInvitationCode(row?['token']?.toString() ?? '');
  }

  Future<void> _shareInvitation(String token) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(dialogContext, 'inviteTitle')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(dialogContext, 'inviteShareDescription')),
              const SizedBox(height: 12),
              SelectableText(invitationWebLink(token,
                qa: !OneSpaceEnv.isProduction).toString()),
              const SizedBox(height: 14),
              Text(tr(dialogContext, 'inviteQrHint'),
                style: Theme.of(dialogContext).textTheme.bodySmall),
              const SizedBox(height: 8),
              InvitationQr(code: token),
              const SizedBox(height: 12),
              Text(tr(dialogContext, 'inviteManualCode'),
                style: Theme.of(dialogContext).textTheme.bodySmall),
              SelectableText(token, style:const TextStyle(fontFamily:'monospace')),
            ],
          ),
        ),
        actions: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final way in const [
              ('whatsapp', Icons.chat_outlined, 'WhatsApp'),
              ('sms', Icons.sms_outlined, 'Text message'),
              ('email', Icons.email_outlined, 'Email'),
            ])
              OutlinedButton.icon(
                icon: Icon(way.$2, size: 18),
                label: Text(tt(way.$3)),
                onPressed: () async {
                  final message = invitationMessage(token,
                      qa: !OneSpaceEnv.isProduction,
                      email: way.$1 == 'email');
                  final uri = switch (way.$1) {
                    'whatsapp' => Uri.parse(
                      'https://wa.me/?text=${Uri.encodeComponent(message)}'),
                    'sms' => Uri.parse(
                      'sms:?body=${Uri.encodeComponent(message)}'),
                    _ => Uri(scheme: 'mailto', queryParameters: {
                      'subject': 'A little space for us — OneSpace invitation',
                      'body': message,
                    }),
                  };
                  try {
                    final opened = await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                    if (!opened && mounted) {
                      ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
                        content: Text(tr(this.context, 'inviteShareUnavailable'))));
                    }
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
                        content: Text(tr(this.context, 'inviteShareUnavailable'))));
                    }
                  }
                },
              ),
          ]),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text:
                  invitationMessage(token, qa: !OneSpaceEnv.isProduction)));
              if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(content: Text(tr(this.context, 'inviteLinkCopied'))));
            },
            icon: const Icon(Icons.copy),
            label: Text(tr(dialogContext, 'copyAgain')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(tr(dialogContext, 'done')),
          ),
        ],
      ),
    );
  }

  Future<void> _resendInvitation() async {
    final id = spaceId;
    if (id == null || working) return;
    setState(() { working = true; issue = null; });
    try {
      final token = await _activeInvitationCode(id);
      if (!mounted) return;
      if (token == null) {
        await _load();
        if (mounted) setState(() => issue = tr(context, 'inviteNoActiveCode'));
        return;
      }
      await _shareInvitation(token);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => issue = e.message);
    } catch (_) {
      if (mounted) setState(() => issue = tr(context, 'inviteResendError'));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _invite({bool replacing = false}) async {
    final id = spaceId;
    if (id == null || working) return;
    setState(() { working = true; issue = null; });
    try {
      // Server-side state is authoritative. A stale Today cache must not
      // silently invalidate a code if the user pressed "Create".
      final activeCode = await _activeInvitationCode(id);
      if (!mounted) return;
      if (activeCode != null && !replacing) {
        await _shareInvitation(activeCode);
        return;
      }
      if (activeCode != null && replacing) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(tr(dialogContext, 'replaceInvitationConfirmTitle')),
            content: Text(tr(dialogContext, 'replaceInvitationConfirmBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(tr(dialogContext, 'keepInvitation')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(tr(dialogContext, 'replaceInvitationConfirmAction')),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      final token = await client.rpc('create_invitation',
          params: {'p_space_id': id}) as String;
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      await _shareInvitation(token);
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

  static const _loveDismissKey='onespace_love_nudge_dismissed_v1';

  String? _loveNudge()=>clockMembers.length<2?null:LoveNudgeRules.nudge(
    lastSent:lastLoveSent,now:DateTime.now(),apart:!_together,dismissedOn:loveDismissedOn);

  Future<void> _loadLoveDismissed() async {
    try{
      final raw=await SharedPreferencesAsync().getString(_loveDismissKey);
      if(mounted&&raw!=null)setState(()=>loveDismissedOn=DateTime.tryParse(raw));
    }catch(_){}
  }

  static const _hiddenOnThisDayKey='onespace_hidden_on_this_day_v1';

  Future<void> _loadHiddenOnThisDay() async {
    try{
      final raw=await SharedPreferencesAsync().getStringList(_hiddenOnThisDayKey);
      if(mounted&&raw!=null)setState(()=>hiddenOnThisDay=raw.toSet());
    }catch(_){}
  }

  /// Spec 3.5: at most one past memory from today's date, hideable per memory.
  Widget? _onThisDayTile(){
    final memory=onThisDay;
    final id=memory?['id']?.toString();
    if(memory==null||id==null||hiddenOnThisDay.contains(id))return null;
    final years=(memory['years_ago'] as num?)?.toInt()??1;
    return ListTile(
      dense:true,
      contentPadding:const EdgeInsets.symmetric(horizontal:4),
      leading:const Icon(Icons.auto_awesome_outlined),
      title:Text(tt(memory['title']?.toString()??'A memory')),
      subtitle:Text(tt('On this day · $years year${years==1?'':'s'} ago')),
      onTap:()=>_push(MemoriesScreen(initialMemoryId:id)),
      trailing:IconButton(
        tooltip:tt('Hide this memory from Today'),
        icon:const Icon(Icons.close,size:18),
        onPressed:()async{
          final next={...hiddenOnThisDay,id};
          setState(()=>hiddenOnThisDay=next);
          try{await SharedPreferencesAsync().setStringList(_hiddenOnThisDayKey,next.toList());}catch(_){}
        }));
  }

  bool get _together=>relationshipMode=='living_together';

  String _greeting(){
    final hour=DateTime.now().hour;
    final part=hour<5?'Good evening':hour<12?'Good morning':hour<17?'Good afternoon':'Good evening';
    final me=FirstName.of(clockMembers.where((m)=>m['is_me']==true)
      .map((m)=>m['name']).firstOrNull);
    // R75: translate the greeting itself; the name stays as typed.
    return '${tt(part)}${OneSpacePhrases.arabic?'، ':', '}$me';
  }

  /// "Your space with your love" (an endearment) or "Your space with Kay".
  String _spaceWith(){
    final partnerName=clockMembers.where((m)=>m['is_me']!=true)
      .map((m)=>FirstName.of(m['name'])).firstOrNull??'your partner';
    final label=partnerLabel?.trim();
    if(label==null||label.isEmpty)return 'Your space with $partnerName';
    if(!partnerLabelIsEndearment)return 'Your space with $label';
    final bare=label.replaceFirst(RegExp(r'^(my|your)\s+',caseSensitive:false),'');
    return 'Your space with your $bare';
  }

  // ---- Hero (spec 3.2) ------------------------------------------------------
  Widget _hero(){
    final theme=Theme.of(context);
    final colors=theme.colorScheme;
    final apart=!_together;
    TalkWindow? window;
    if(relationshipMode=='apart_different_tz'&&schedulesMine.isNotEmpty&&
       schedulesPartner.isNotEmpty){
      window=nextTalkWindow(schedulesMine.first,schedulesPartner.first,DateTime.now().toUtc());
    }
    final missingSchedules=relationshipMode=='apart_different_tz'&&
      (schedulesMine.isEmpty||!schedulesMine.first.hasAny||
       schedulesPartner.isEmpty||!schedulesPartner.first.hasAny);
    final trip=activeTrip;
    final tripEnd=DateTime.tryParse(trip?['end_on']?.toString()??'');
    final backIn=_dayDistance(tripEnd);
    final countdown=milestoneCountdowns.isEmpty?null:milestoneCountdowns.first;
    return Card(
      elevation:0,
      margin:const EdgeInsets.only(bottom:12),
      color:Color.alphaBlend((_together?colors.tertiary:colors.primary)
        .withValues(alpha:.09),colors.surface),
      child:Padding(
        padding:const EdgeInsetsDirectional.fromSTEB(14,6,6,12),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[
            Expanded(child:Text(tt(_together?'Together under one roof':
              relationshipMode=='not_set'?'Tell OneSpace how you live':'Living apart'),
              style:theme.textTheme.titleSmall?.copyWith(color:colors.onSurfaceVariant))),
            IconButton(
              tooltip:tt('How we live'),
              onPressed:_chooseHowWeLive,
              icon:Icon(_together?Icons.home_rounded:Icons.flight_rounded,
                color:colors.primary)),
          ]),
          if(_together)Row(children:[
            Icon(Icons.favorite_rounded,size:30,color:colors.primary),
            const SizedBox(width:12),
            Expanded(child:Text(tt('One home, one shared space.'))),
          ])
          else PartnerClockStrip(members:clockMembers,relationshipMode:relationshipMode),
          if(trip!=null)Padding(
            padding:const EdgeInsetsDirectional.only(top:8,end:8),
            child:Row(children:[
              Icon(Icons.luggage_outlined,size:18,color:colors.primary),
              const SizedBox(width:6),
              Expanded(child:Text(tt([
                'Travelling',
                (trip['destination']?.toString().trim().isNotEmpty??false)
                  ?trip['destination'].toString():trip['title']?.toString()??'Trip',
                if(backIn!=null&&backIn>0)'back in $backIn day${backIn==1?'':'s'}'
                else if(backIn==0)'back today',
              ].join(' · ')))),
            ])),
          if(window!=null)Padding(
            padding:const EdgeInsetsDirectional.only(top:8,end:8),
            child:Row(children:[
              Icon(Icons.phone_in_talk_outlined,size:18,color:colors.primary),
              const SizedBox(width:6),
              Expanded(child:Text(tt(talkWindowLabel(window,DateTime.now().toUtc(),myZone)))),
            ]))
          else if(missingSchedules)Padding(
            padding:const EdgeInsetsDirectional.only(top:8,end:8),
            child:Text(tt('Add your work and sleep hours in Profile to see good times to talk.'),
              style:theme.textTheme.bodySmall)),
          if(apart&&(lastMetOn!=null||nextMeetOn!=null))Padding(
            padding:const EdgeInsetsDirectional.only(top:8,end:8),
            child:_meetingCounters()),
          if(countdown!=null)Padding(
            padding:const EdgeInsetsDirectional.only(top:6,end:8),
            child:InkWell(
              onTap:()=>_openFocusActivity(countdown['activity_id'].toString()),
              child:Row(children:[
                Icon(Icons.hourglass_bottom_outlined,size:18,color:colors.primary),
                const SizedBox(width:6),
                Expanded(child:Text('${countdown['label']} · '+
                  ActivityCountdownRules.summary(countdown['date'].toString(),
                    repeatYearly:countdown['annual']==true,now:DateTime.now()))),
              ]))),
        ]),
      ),
    );
  }

  Widget _meetingCounters(){
    final ago=_dayDistance(lastMetOn);
    final until=_dayDistance(nextMeetOn);
    return Row(children:[
      if(ago!=null)Expanded(child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(tr(context,'lastMetLabel'),
            style:Theme.of(context).textTheme.bodySmall),
          Text(tt(ago==0?'Today':ago>0?'Coming up':
            ago==-1?'Yesterday':'${-ago} days ago'),
            style:Theme.of(context).textTheme.titleSmall),
        ])),
      if(until!=null)Expanded(child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(tr(context,'nextMeetingLabel'),
            style:Theme.of(context).textTheme.bodySmall),
          Text(tt(until<0?'Meeting date passed':
            until==0?tr(context,'meetingToday'):
            '$until days to go'),
            style:Theme.of(context).textTheme.titleSmall),
        ])),
    ]);
  }

  /// B-09/B-10: switch How we live, with Undo and the journey memory offer.
  Future<void> _chooseHowWeLive() async {
    final choice=await showModalBottomSheet<bool>(
      context:context,showDragHandle:true,
      builder:(ctx)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
        ListTile(title:Text(tt('How do you live?'),
          style:TextStyle(fontWeight:FontWeight.w700))),
        ListTile(
          leading:const Icon(Icons.home_rounded),
          title:Text(tt('Together')),
          subtitle:Text(tt('We share one home')),
          trailing:_together?const Icon(Icons.check):null,
          onTap:()=>Navigator.pop(ctx,true)),
        ListTile(
          leading:const Icon(Icons.flight_rounded),
          title:Text(tt('Apart')),
          subtitle:Text(tt('We live in different places for now')),
          trailing:!_together&&relationshipMode!='not_set'?const Icon(Icons.check):null,
          onTap:()=>Navigator.pop(ctx,false)),
        const SizedBox(height:8),
      ])));
    if(choice==null||!mounted)return;
    final wasTogether=_together;
    if(choice==wasTogether&&relationshipMode!='not_set')return;
    final previousMode=relationshipMode;
    try{
      await client.rpc('set_how_we_live',params:{'p_together':choice});
    }catch(_){
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:Text(tt('Could not save. Check your connection and try again.'))));
      }
      return;
    }
    if(!mounted)return;
    await _load();
    if(!mounted)return;
    if(choice&&!wasTogether&&previousMode!='not_set'){
      final save=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title:Text(tt('Moving in together')),
        content:Text(tt('Save our journey apart as a memory? Nothing is deleted; '
          'the meeting counters simply hide while you live together.')),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(tt('Not now'))),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(tt('Save memory'))),
        ]));
      if(save==true&&spaceId!=null){
        final today=CalendarRules.sqlDate(DateTime.now());
        final met=lastMetOn==null?null:CalendarRules.sqlDate(lastMetOn!);
        try{
          await client.from('memories').insert({
            'space_id':spaceId,
            'created_by':client.auth.currentUser!.id,
            'title':'Our journey apart',
            'body':'We lived apart and kept our love close across the distance. '
              'On $today we started living together.'
              '${met==null?'':' The last time we met while apart: $met.'}',
            'memory_date':today,
            'visibility':'shared',
          });
        }catch(_){
          if(mounted){
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:Text(tt('The memory could not be saved; you can add it from Memories.'))));
          }
        }
      }
    }
    if(!mounted)return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration:const Duration(seconds:10),
      content:Text(tt(choice?tt('Saved: we live together'):tt('Saved: we live apart'))),
      action:SnackBarAction(label:tt('Undo'),onPressed:()async{
        try{
          await client.rpc('set_how_we_live',params:{'p_together':!choice});
          if(mounted)await _load();
        }catch(_){}
      }),
    ));
  }

  // ---- Since you were away (spec 3.3) --------------------------------------
  Widget _sinceAwaySection(){
    final theme=Theme.of(context);
    return TodaySectionCard(
      icon:Icons.mark_chat_unread_outlined,
      title:tt('Since you were away'),
      trailing:sinceAwayTotal==0?null:TextButton(
        onPressed:_openNotifications,child:Text(tt('See all'))),
      children:[
        if(sinceAway.isEmpty)TodayEmptyHint(tt("You're all caught up."))
        else if(sinceAwayCollapsed)ListTile(
          dense:true,
          contentPadding:const EdgeInsets.symmetric(horizontal:4),
          title:Text('$sinceAwayTotal update${sinceAwayTotal==1?'':'s'} you have already seen'),
          trailing:const Icon(Icons.expand_more),
          onTap:()=>setState(()=>sinceAwayCollapsed=false))
        else ...[
          for(final item in sinceAway)ListTile(
            dense:true,
            contentPadding:const EdgeInsets.symmetric(horizontal:4),
            leading:Icon(notificationIcon(item)),
            title:Text(tt(item['title']?.toString()??'Update'),
              maxLines:2,overflow:TextOverflow.ellipsis),
            subtitle:Text(tt([
              item['body']?.toString()??'',
              notificationAge(item['created_at']),
            ].where((x)=>x.trim().isNotEmpty).join(' · ')),
              maxLines:2,overflow:TextOverflow.ellipsis),
            onTap:()async{
              await openNotificationTarget(context,item);
              if(mounted)await _load();
            }),
          if(sinceAwayTotal>sinceAway.length)Padding(
            padding:const EdgeInsetsDirectional.only(start:4,top:2),
            child:Text('${tt('and')} ${sinceAwayTotal-sinceAway.length} ${tt('more')}',
              style:theme.textTheme.bodySmall)),
        ],
      ],
    );
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder:(_)=>const NotificationsScreen()));
    if(mounted)await _load();
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder:(_)=>screen));
    if(mounted)await _load();
  }

  // ---- Our space shortcuts (spec 3.7) ---------------------------------------
  Widget _shortcuts(){
    final theme=Theme.of(context);
    final colors=theme.colorScheme;
    final dueReminders=focusItems.where((i)=>i.isReminder).length;
    Widget group(String label,Color color,List<_Shortcut> tiles)=>Column(
      crossAxisAlignment:CrossAxisAlignment.start,children:[
        Padding(padding:const EdgeInsetsDirectional.fromSTEB(2,10,2,6),
          child:Text(tt(label).toUpperCase(),style:theme.textTheme.labelSmall?.copyWith(
            color:color,fontWeight:FontWeight.w800,letterSpacing:.8))),
        GridView.count(
          crossAxisCount:3,
          shrinkWrap:true,
          physics:const NeverScrollableScrollPhysics(),
          crossAxisSpacing:8,mainAxisSpacing:8,
          childAspectRatio:1.05,
          children:[for(final t in tiles)_shortcutTile(t,color)],
        ),
      ]);
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(tt('Our space'),
        style:theme.textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w700)),
      // R55: grouped by what you are doing, not by tab, so no group has one tile.
      group('Plan together',colors.primary,[
        _Shortcut(tt('Calendar'),Icons.calendar_month_outlined,widget.onOpenCalendar),
        _Shortcut(tt('To-do lists'),Icons.checklist_outlined,widget.onOpenPlans),
        _Shortcut(tt('Reminders'),Icons.alarm_outlined,
          ()=>_push(const RemindersScreen()),badge:dueReminders),
        _Shortcut(tt('Activities'),Icons.hub_outlined,widget.onOpenCoordinate),
        _Shortcut(tt('Trips'),Icons.flight_takeoff_outlined,
          ()=>_push(const TripsScreen())),
        _Shortcut(tt('Occasions'),Icons.card_giftcard_outlined,
          ()=>_push(const OccasionsScreen())),
        _Shortcut(tt('Notes'),Icons.sticky_note_2_outlined,widget.onOpenNotes),
        _Shortcut(tt('Contact cards'),Icons.contacts_outlined,
          ()=>_push(const WorldContactsScreen())),
        ..._extraTools(),
      ]),
      group('Stay close',colors.tertiary,[
        _Shortcut(tt('Letters'),Icons.mark_email_unread_outlined,widget.onOpenLetters,
          badge:lettersBadge),
        _Shortcut(tt('A little love'),Icons.volunteer_activism_outlined,
          ()=>_push(const PartnerGesturesScreen())),
        _Shortcut(tt('Daily connection'),Icons.favorite_outline,widget.onOpenCheckins),
        _Shortcut(tt('Shared experiences'),Icons.movie_outlined,
          ()=>_push(const SharedExperiencesScreen())),
        _Shortcut(tt('Memories'),Icons.auto_stories_outlined,widget.onOpenMemories),
        // R78: our places and counters.
        _Shortcut(tt('Our places'),Icons.place_outlined,()=>_push(const PlacesScreen())),
        _Shortcut(tt('Counters'),Icons.hourglass_bottom_rounded,()=>_push(const CountersScreen())),
        _Shortcut(tt('Search our space'),Icons.search,
          ()=>_push(const GlobalSearchScreen())),
      ]),
    ]);
  }

  /// R52: the share-in tray, with a count when something waits.
  List<_Shortcut> _extraTools()=>[
    _Shortcut(tt('Items to sort'),Icons.inbox_outlined,
      ()=>_push(const ItemsToSortScreen()),badge:itemsToSort),
  ];

  Widget _shortcutTile(_Shortcut tile,Color color){
    final colors=Theme.of(context).colorScheme;
    return Card(
      elevation:0,clipBehavior:Clip.antiAlias,margin:EdgeInsets.zero,
      color:Color.alphaBlend(color.withValues(alpha:.10),colors.surface),
      child:InkWell(
        onTap:tile.onTap,
        child:Padding(padding:const EdgeInsets.all(6),
          child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
            Badge(
              isLabelVisible:tile.badge>0,
              label:Text(tt(tile.badge>99?'99+':'${tile.badge}')),
              child:Icon(tile.icon,color:color,size:26)),
            const SizedBox(height:6),
            Text(tt(tile.label),textAlign:TextAlign.center,maxLines:2,
              overflow:TextOverflow.ellipsis,
              style:Theme.of(context).textTheme.labelMedium),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme=Theme.of(context);
    return Scaffold(
      backgroundColor:Colors.transparent,
      floatingActionButton:spaceId==null?null:FloatingActionButton.extended(
        heroTag:'quick-add',
        onPressed:()async{
          await showQuickAdd(context,spaceId:spaceId!);
          if(mounted)await _load();
        },
        icon:const Icon(Icons.add),
        label:Text(tt('Quick add'))),
      body:RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16,16,16,24),
        children: [
          Text(tt(spaceId == null ? tr(context, 'ourSpace') : _greeting()),
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
          if(spaceId!=null && clockMembers.length>1)
            Padding(
              padding:const EdgeInsets.only(top:2,bottom:6),
              child:Text(tt(_spaceWith()),style:theme.textTheme.bodyMedium))
          else const SizedBox(height:10),
          if(spaceId!=null&&(offline||(lastUpdated!=null&&summaryLoading)))
            Padding(
              padding:const EdgeInsets.only(bottom:6),
              child:Row(children:[
                Icon(offline?Icons.cloud_off_outlined:Icons.sync,size:16,
                  color:theme.colorScheme.onSurfaceVariant),
                const SizedBox(width:6),
                Expanded(child:Text(
                  tt(lastUpdated==null?'Showing your saved copy':
                  'Last updated ${PartnerTimeZones.timeLabel(lastUpdated!)}'),
                  style:theme.textTheme.bodySmall)),
                if(offline)TextButton(onPressed:_load,child:Text(tt('Retry'))),
              ])),
          const SeasonalThemePreview(compact:true),
          const SizedBox(height:8),
          if (issue != null) ...[
            Text(tt(issue!), style:TextStyle(color:theme.colorScheme.error)),
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
                  OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(tt('Scan your partner’s QR code')),
                    onPressed: working ? null : () async {
                      final code = await scanInvitation(context);
                      if (code == null || !mounted) return;
                      invitationController.text = code;
                      await _accept();
                    }),
                  const SizedBox(height: 6),
                  FilledButton.tonal(
                    onPressed: working ? null : _accept,
                    child: Text(tr(context, 'joinSpace')),
                  ),
                ],
              ),
            ),
          ] else ...[
            if (memberCount < 2) ...[
              _invitePanel(),
              const SizedBox(height:12),
            ],
            _hero(),
            _sinceAwaySection(),
            TodayAttentionSection(
              items:focusItems,
              loading:focusLoading,
              error:focusError,
              onRetry:()=>unawaited(_load()),
              onOpen:_openAttentionActivity,
              onOpenPlans:widget.onOpenPlans,
              onOpenCheckins:widget.onOpenCheckins,
              onOpenReminder:_openReminder,
              onSnooze:_snoozeFocus,
              leading:[
                if(_loveNudge() case final String text)ListTile(
                  dense:true,
                  contentPadding:const EdgeInsets.symmetric(horizontal:4),
                  leading:const Icon(Icons.volunteer_activism_outlined),
                  title:Text(tt(text)),
                  subtitle:Text(tt('Send a hug, a thought or a good-night')),
                  onTap:()=>_push(const PartnerGesturesScreen()),
                  trailing:TextButton(onPressed:()async{
                    final now=DateTime.now();
                    setState(()=>loveDismissedOn=now);
                    try{await SharedPreferencesAsync().setString(_loveDismissKey,now.toIso8601String());}catch(_){}
                  },child:Text(tt('Not today')))),
                if(itemsToSort>0)ListTile(
                  dense:true,
                  contentPadding:const EdgeInsets.symmetric(horizontal:4),
                  leading:const Icon(Icons.inbox_outlined),
                  title:Text('$itemsToSort item${itemsToSort==1?'':'s'} to sort'),
                  subtitle:Text(tt('Saved from other apps')),
                  trailing:const Icon(Icons.chevron_right),
                  onTap:()=>_push(const ItemsToSortScreen())),
              ],
            ),
            TodayCalendarSection(entries:nearEvents,
              onOpen:widget.onOpenCalendar ?? () {},
              onOpenPlans:widget.onOpenPlans,
              onOpenActivity:_openFocusActivity,
              onOpenExperience:(id)=>_push(SharedExperiencesScreen(initialExperienceId:id)),
              onOpenTrip:(id)=>_push(TripsScreen(initialTripId:id)),
              onOpenOccasion:(id)=>_push(OccasionsScreen(initialPlanId:id)),
              onOpenReminder:_openReminder,
              leading:[if(_onThisDayTile() case final Widget tile)tile]),
            const SizedBox(height:4),
            _shortcuts(),
            const SizedBox(height:72),
          ],
        ],
      ),
    ));
  }

  Widget _invitePanel() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      elevation: 0,
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => inviteCollapsed = !inviteCollapsed),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(Icons.favorite_rounded,
                    color: colors.onPrimaryContainer, size: 24),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(context, 'inviteTitle'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.w700)),
                      Text(_hasActiveInvite
                          ? tr(context, 'invitePendingHint')
                          : tr(context, 'invitePartnerDescription'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onPrimaryContainer)),
                    ],
                  )),
                  Icon(inviteCollapsed
                      ? Icons.expand_more : Icons.expand_less,
                      color: colors.onPrimaryContainer),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: working ? null : _hasActiveInvite
                  ? _resendInvitation : () => _invite(),
              icon: Icon(_hasActiveInvite ? Icons.send_outlined
                  : Icons.person_add_alt_1),
              label: Text(tr(context, _hasActiveInvite
                  ? 'resendInvitation' : 'createInvitation')),
            )),
            if (!inviteCollapsed) ...[
              const SizedBox(height: 12),
              Text('${tr(context, 'members')}: $memberCount / 2',
                style: TextStyle(color: colors.onPrimaryContainer)),
              for (final memberName in memberDisplayNames)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Icon(Icons.person_outline, size: 18,
                      color: colors.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Expanded(child: Text(tt(memberName),
                      style: TextStyle(color: colors.onPrimaryContainer))),
                  ]),
                ),
              if (_hasActiveInvite) ...[
                const SizedBox(height: 8),
                Text('${tr(context, 'invitationExpires')}: '
                    '${pendingInviteExpiry!.toLocal().toString().split('.').first}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onPrimaryContainer)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: working ? null : () => _invite(replacing: true),
                  icon: const Icon(Icons.autorenew),
                  label: Text(tr(context, 'replaceInvitation')),
                ),
                TextButton.icon(
                  onPressed: working ? null : _revokeInvite,
                  icon: const Icon(Icons.link_off),
                  label: Text(tr(context, 'revokeInvitation')),
                ),
              ],
              TextButton.icon(
                onPressed: working ? null : _load,
                icon: const Icon(Icons.refresh),
                label: Text(tr(context, 'refreshStatus')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _panel(String title, String description, IconData icon, Widget action) {
    return Card(
      elevation: 0,
      color:Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 30, color:Theme.of(context).colorScheme.onPrimaryContainer),
            const SizedBox(height: 12),
            Text(tt(title), style:TextStyle(fontSize:21,fontWeight:FontWeight.w700,
             color:Theme.of(context).colorScheme.onPrimaryContainer)),
            const SizedBox(height: 8),
            Text(tt(description),style:TextStyle(color:Theme.of(context).colorScheme.onPrimaryContainer)),
            const SizedBox(height: 14),
            action,
          ],
        ),
      ),
    );
  }
}

class _Shortcut {
  const _Shortcut(this.label,this.icon,this.onTap,{this.badge=0});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final int badge;
}
