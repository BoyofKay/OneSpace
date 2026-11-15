import '../../core/record_list_top_actions.dart';
import '../../core/editor_scaffold.dart';
import '../../core/collection_history_screen.dart';
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../../l10n/onespace_strings.dart';
import '../sharing/private_share_button.dart';
import '../sharing/share_grant_watcher.dart';
import '../connection/connection_rules.dart';
import 'checkin_request_rules.dart';
import 'checkin_acknowledgement_rules.dart';

/// Each person may make one personal check-in per local calendar date. The
/// partner can view shared entries, but only the author can edit their entry.
class CheckinsScreen extends StatefulWidget {
  const CheckinsScreen({super.key,this.initialRequestId});
  final String? initialRequestId;
  @override
  State<CheckinsScreen> createState()=>_CheckinsScreenState();
}

class _CheckinsScreenState extends State<CheckinsScreen> with SingleTickerProviderStateMixin {
  // R55: two tabs, each with its own floating button.
  late final TabController _tabs=TabController(length:2,vsync:this)
    ..addListener((){if(mounted)setState((){});});
  String? _partnerName;
  final _client=Supabase.instance.client;
  String? _space;
  Stream<List<Map<String,dynamic>>>? _stream;
  Stream<List<Map<String,dynamic>>>? _requests;
  String? _error;
  bool _loading=true;
  StreamSubscription<List<Map<String,dynamic>>>? _grants,_ackSubscription;
  List<Map<String,dynamic>> _ackRows=[];
  String? _ackWatchedSpace;
  bool _ackBusy=false;
  String _filter='all',_requestFilter='all';
  String _journalSearch='',_conversationSearch='';
  bool _openedInitialRequest=false;
  Timer? _requestClock;

  @override
  void initState(){
    super.initState();
    _load();
    // Recalculate expiry while the screen stays open, without polling the
    // backend or resending an existing request.
    _requestClock=Timer.periodic(const Duration(minutes:1),(_){
      if(mounted)setState((){});
    });
  }

  @override
  void dispose() {
    _requestClock?.cancel();
    _tabs.dispose();
    _grants?.cancel();
    _ackSubscription?.cancel();
    super.dispose();
  }

  void _watchAcks(String spaceId){
    if(_ackWatchedSpace==spaceId)return;
    _ackSubscription?.cancel();
    _ackWatchedSpace=spaceId;
    // One RLS-scoped realtime stream for the whole history, not one
    // subscription per expanded card. No extra notification transport.
    _ackSubscription=_client.from('partner_checkin_acknowledgements')
      .stream(primaryKey:['request_id'])
      .order('updated_at',ascending:false).limit(500)
      .listen((rows){
        if(mounted&&_space==spaceId){
          setState(()=>_ackRows=List<Map<String,dynamic>>.from(rows));
        }
      },onError:(Object error,StackTrace stack){
        // Reply history remains readable even if this optional stream fails.
      });
  }

  void _watchGrants(String id) {
    _grants?.cancel();
    _grants = watchObjectShares(
      client:_client,spaceId:id,objectType:'checkin',
      onChanged:() {
        if (!mounted || _space != id) return;
        setState(() {
          _stream = _client.from('daily_checkins')
            .stream(primaryKey:['id']).eq('space_id',id)
            .order('checkin_date',ascending:false);
          _requests=_client.from('partner_checkin_requests')
            .stream(primaryKey:['id']).eq('space_id',id)
            .order('requested_at',ascending:false);
        });
      },
    );
  }


  Future<void> _openInitialRequest() async{
    final requestId=widget.initialRequestId;
    if(_openedInitialRequest||requestId==null||_space==null)return;
    _openedInitialRequest=true;
    try{
      final rows=await _client.from('partner_checkin_requests')
        .select('id,space_id,sender_id,recipient_id,note,requested_at,responded_at,expires_at')
        .eq('id',requestId).eq('space_id',_space!).limit(1);
      if(!mounted||rows.isEmpty)return;
      final row=rows.first;
      if(CheckinRequestRules.canRespond(
        row,_client.auth.currentUser?.id,DateTime.now())){
        await _respond(row);
      }
    }catch(_){
      // The check-in log remains available if the request has been removed
      // or cannot be opened; do not trap the user in an error dialog.
    }
  }

  Future<void> _load() async {
    if(mounted)setState(() { _loading=_space==null;_error=null;});
    try{
      final id=await CurrentSpaceCache.instance.get();
      if(!mounted)return;
      setState(() {
        _space=id;
        _stream=id==null?null:_client.from('daily_checkins')
          .stream(primaryKey:['id']).eq('space_id',id)
          .order('checkin_date',ascending:false);
        _loading=false;
        _requests=id==null?null:_client.from('partner_checkin_requests')
          .stream(primaryKey:['id']).eq('space_id',id)
          .order('requested_at',ascending:false);
      });
      if(id!=null){
        unawaited(_loadPartnerName(id));
        _watchGrants(id);
        _watchAcks(id);
        unawaited(_openInitialRequest());
      }else{
        _ackSubscription?.cancel();
        _ackSubscription=null;_ackWatchedSpace=null;
        if(mounted)setState(()=>_ackRows=[]);
      }
    }catch(_){
      if(mounted)setState((){_error=tr(context,'loadFailed');_loading=false;});
    }
  }

  Future<void> _edit([Map<String,dynamic>? record]) async {
    final id=_space;
    if(id==null)return;
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder:(_)=>CheckinEditor(spaceId:id,existing:record)));
  }

    String _dateTime(Object? raw){
    final date=DateTime.tryParse(raw?.toString()??'')?.toLocal();
    if(date==null)return 'Date unavailable';
    return MaterialLocalizations.of(context).formatMediumDate(date)+' · '+
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(date));
  }

  Future<void> _loadPartnerName(String space) async {
    try{
      final me=_client.auth.currentUser?.id;
      final rows=await _client.from('space_members').select('user_id').eq('space_id',space);
      final peer=rows.where((r)=>r['user_id']!=me).firstOrNull?['user_id'];
      if(peer==null)return;
      final p=await _client.from('profiles').select('display_name').eq('id',peer).maybeSingle();
      final mine=me==null?null:await _client.from('profiles')
        .select('partner_label').eq('id',me).maybeSingle();
      final label=mine?['partner_label']?.toString().trim()??'';
      final first=(p?['display_name']?.toString().trim()??'').split(RegExp(r'\s+')).first;
      if(mounted)setState(()=>_partnerName=label.isNotEmpty?label:first.isNotEmpty?first:null);
    }catch(_){}
  }

  static const _moodWords=['Very low','Low','Okay','Good','Great'];
  static const _moodIcons=[
    Icons.sentiment_very_dissatisfied,
    Icons.sentiment_dissatisfied,
    Icons.sentiment_neutral,
    Icons.sentiment_satisfied,
    Icons.sentiment_very_satisfied,
  ];
  Color _moodColor(int mood){
    final c=Theme.of(context).colorScheme;
    return mood<=2?c.error:mood==3?c.tertiary:c.primary;
  }

  Future<void> _askPartner() async{
    final space=_space,me=_client.auth.currentUser?.id;
    if(space==null||me==null)return;
    try{
      final people=await _client.from('space_members').select('user_id')
        .eq('space_id',space);
      final peer=people.where((p)=>p['user_id']!=me).firstOrNull;
      if(peer==null||!mounted){
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:Text('Connect your partner before sending a check-in.')));
        return;
      }
      // R55: a page with Cancel/Send at the bottom, not a pop-up.
      final note=await Navigator.of(context).push<String>(MaterialPageRoute(
        builder:(_)=>CheckinRequestPage(partnerName:_partnerName)));
      {
        if(note==null||!mounted)return;
        await _client.from('partner_checkin_requests').insert({
          'space_id':space,'sender_id':me,
          'recipient_id':peer['user_id'],'note':note.trim(),
        });
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content:Text('Your check-in was sent.')));
      }
    }on PostgrestException catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Check-in could not be sent: '+e.message)));
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('Could not send check-in. Please retry.')));
    }
  }

  Future<void> _acknowledge(
    Map<String,dynamic> request,String kind,
  ) async{
    final me=_client.auth.currentUser?.id;
    if(_ackBusy||
      !CheckinAcknowledgementRules.canAcknowledge(request,me)||
      !CheckinAcknowledgementRules.labels.containsKey(kind))return;
    final requestId=request['id'].toString();
    final existing=CheckinAcknowledgementRules.forRequest(
      _ackRows,request['id']);
    if(existing?['kind']==kind)return;
    setState(()=>_ackBusy=true);
    try{
      if(existing!=null){
        await _client.from('partner_checkin_acknowledgements')
          .update({'kind':kind}).eq('request_id',requestId);
      }else{
        try{
          await _client.from('partner_checkin_acknowledgements')
            .insert({'request_id':requestId,'kind':kind});
        }on PostgrestException catch(e){
          if(e.code!='23505')rethrow;
          await _client.from('partner_checkin_acknowledgements')
            .update({'kind':kind}).eq('request_id',requestId);
        }
      }
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('Could not save your acknowledgment. Try again.')));
    }finally{
      if(mounted)setState(()=>_ackBusy=false);
    }
  }

  Future<void> _respond(Map<String,dynamic> request) async{
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder:(_)=>PartnerCheckinReplyScreen(request:request)));
  }

  Widget _detail(String label,String value)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:7),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(label,style:Theme.of(context).textTheme.labelMedium),
      const SizedBox(height:5),
      SelectableText(value,style:Theme.of(context).textTheme.bodyMedium),
    ]),
  );

  Widget _requestHistory(){
    final me=_client.auth.currentUser?.id;
    return StreamBuilder<List<Map<String,dynamic>>>(
      stream:_requests,builder:(ctx,snapshot){
        if(snapshot.hasError)return const Text(
          'Could not load partner check-ins. Pull down to retry.');
        if(!snapshot.hasData)return const Center(
          child:CircularProgressIndicator());
        final rows=snapshot.data!;
        if(rows.isEmpty)return const Card(elevation:0,child:Padding(
          padding:EdgeInsets.all(14),
          child:Text('No conversations yet. Check on each other anytime.')));
        final now=DateTime.now();
        final needs=CheckinRequestRules.count(rows,'to_answer',me,now);
        final waiting=CheckinRequestRules.count(rows,'waiting',me,now);
        final history=CheckinRequestRules.count(rows,'history',me,now);
        final term=_conversationSearch.trim().toLowerCase();
        final visible=CheckinRequestRules.filter(
          rows,_requestFilter,me,now).where((row)=>
           term.isEmpty||[
            row['note'],row['response_message'],row['response_topic'],
            row['requested_at'],row['response_mood'],
           ].map((x)=>x?.toString().toLowerCase()??'')
            .join(' ').contains(term)).take(60);
        return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Padding(padding:const EdgeInsets.symmetric(vertical:8),
            child:Text('A gentle way to connect. You choose when to reply.',
              style:Theme.of(context).textTheme.bodySmall)),
          Text('To answer: $needs · Sent: $waiting · History: $history',
           style:Theme.of(context).textTheme.bodySmall),
          const SizedBox(height:8),
          TextField(
           onChanged:(value)=>setState(()=>_conversationSearch=value),
           decoration:const InputDecoration(
            prefixIcon:Icon(Icons.search),
            labelText:'Search check-in conversations',
            hintText:'Messages, topics and responses')),
          const SizedBox(height:7),
          if(visible.isEmpty)const Padding(
           padding:EdgeInsets.symmetric(vertical:16),
           child:Text('Nothing in this part of your check-in history.'))
          else for(final item in visible)Card(
            key:ValueKey('request-${item['id']}'),
            elevation:0,clipBehavior:Clip.antiAlias,
            child:ExpansionTile(
              initiallyExpanded:CheckinRequestRules.canRespond(item,me,now),
              leading:Icon(item['responded_at']!=null?
               Icons.mark_chat_read_outlined:
               CheckinRequestRules.status(item,now)==CheckinRequestRules.expired?
                Icons.history_toggle_off_outlined:
               item['sender_id']==me?
                Icons.send_outlined:Icons.mark_email_unread_outlined),
              title:Text(item['sender_id']==me?
                'You checked on ${_partnerName??'your partner'}':
                '${_partnerName??'Your partner'} checked on you',
                style:Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight:FontWeight.w700)),
              subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                if(CheckinRequestRules.canRespond(item,me,now))Container(
                  margin:const EdgeInsets.only(top:4,bottom:2),
                  padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),
                  decoration:BoxDecoration(color:Theme.of(context).colorScheme.primaryContainer,
                    borderRadius:BorderRadius.circular(20)),
                  child:Text('Waiting for your answer',style:Theme.of(context).textTheme.labelSmall?.copyWith(
                    color:Theme.of(context).colorScheme.onPrimaryContainer,fontWeight:FontWeight.w700))),
                if((item['note']?.toString()??'').isNotEmpty)Text('“${item['note']}”',
                  maxLines:2,overflow:TextOverflow.ellipsis,
                  style:Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle:FontStyle.italic)),
                if(item['response_mood']!=null)Text('Felt ${_moodWords[(item['response_mood'] as num).toInt().clamp(1,5).toInt()-1].toLowerCase()}',
                  style:Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color:_moodColor((item['response_mood'] as num).toInt()),fontWeight:FontWeight.w600)),
                Text(_dateTime(item['requested_at'])+' · '+CheckinRequestRules.label(item,now)+
                  (CheckinRequestRules.status(item,now)==CheckinRequestRules.pending?
                   ' · '+CheckinRequestRules.expiryHint(item,now):''),
                  style:Theme.of(context).textTheme.labelSmall),
              ]),
              trailing:PopupMenuButton<String>(tooltip:'More',
                onSelected:(_)=>openChangeLog(context,kind:'checkin_request',recordId:item['id'].toString()),
                itemBuilder:(_)=>const [PopupMenuItem(value:'log',child:Text('Change log'))]),
              childrenPadding:const EdgeInsets.fromLTRB(15,0,15,14),
              children:[
                if(item['response_mood']!=null)ListTile(
                  contentPadding:EdgeInsets.zero,
                  leading:const Icon(Icons.favorite_outline),
                  title:Text('How they felt · '+item['response_mood'].toString()+'/5'),
                  subtitle:Text('Answered '+_dateTime(item['responded_at'])),
                ),
                if((item['response_message']?.toString()??'').isNotEmpty)
                  _detail('What’s on their mind',
                    item['response_message'].toString()),
                if((item['response_topic']?.toString()??'').isNotEmpty)
                  _detail('Something to talk about',
                    item['response_topic'].toString()),
                if(item['responded_at']!=null&&
                  CheckinAcknowledgementRules.canAcknowledge(item,me))...[
                  const SizedBox(height:8),
                  Text('Acknowledge their response (optional)',
                   style:Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height:6),
                  Wrap(spacing:7,runSpacing:5,children:[
                   for(final entry in CheckinAcknowledgementRules.labels.entries)
                    ChoiceChip(label:Text(entry.value),
                     selected:CheckinAcknowledgementRules.forRequest(
                       _ackRows,item['id'])?['kind']==entry.key,
                     onSelected:_ackBusy?null:(_)=>_acknowledge(item,entry.key)),
                  ]),
                ],
                if(item['responded_at']!=null&&item['recipient_id']==me&&
                  CheckinAcknowledgementRules.forRequest(
                   _ackRows,item['id'])!=null)
                 Padding(padding:const EdgeInsets.only(top:8),
                  child:Row(children:[
                   const Icon(Icons.favorite_outline,size:19),
                   const SizedBox(width:8),
                   Expanded(child:Text('Your partner: '+
                    (CheckinAcknowledgementRules.label(
                      CheckinAcknowledgementRules.forRequest(
                       _ackRows,item['id'])?['kind'])??'Acknowledged'))),
                  ])),
                if(CheckinRequestRules.canRespond(item,me,now))
                  Align(alignment:AlignmentDirectional.centerEnd,
                    child:FilledButton.icon(
                      onPressed:()=>_respond(item),
                      icon:const Icon(Icons.reply_outlined),
                      label:const Text('Respond to your love'))),
                if(CheckinRequestRules.status(item,now)==
                  CheckinRequestRules.expired)
                  const Padding(padding:EdgeInsets.only(top:8),
                   child:Text('This invitation has expired. Your history is '
                    'preserved, and either partner can start a new check-in.')),
              ],
            ),
          ),
        ]);
      },
    );
  }

  @override
  List<FilterGroupSpec> _filterGroups()=>[
    if(_tabs.index==0)FilterGroupSpec(id:'talks',label:'Check-ins',
      options:const {'all':'All','to_answer':'To answer','waiting':'Sent','history':'Past'},
      selected:_requestFilter,defaultValue:'all')
    else FilterGroupSpec(id:'who',label:'Who can see',
      options:const {'all':'All','shared':'Shared','private':'Only me'},
      selected:_filter,defaultValue:'all'),
  ];

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(tr(context,'checkinTitle')),actions:[
      RecordListTopActions(
        historyKinds:_tabs.index==0?const ['checkin_request']:const ['checkin'],
        historyTitle:_tabs.index==0?'Daily check-in':'Feelings journal',
        showHistory:false,onToggleHistory:(){},allowRemoved:false,
        groups:_filterGroups(),
        onApply:(v)=>setState((){
          if(v.containsKey('talks'))_requestFilter=v['talks']!;
          if(v.containsKey('who'))_filter=v['who']!;
        })),
    ],bottom:TabBar(controller:_tabs,tabs:const [
      Tab(text:'Daily check-in'),
      Tab(text:'Feelings journal'),
    ])),
    floatingActionButton:_space==null?null:_tabs.index==0
      ?AddFab(label:'Check on ${_partnerName??'your partner'}',onPressed:_askPartner,heroTag:'fab-checkin')
      :AddFab(label:'Record my feeling',onPressed:()=>_edit(),heroTag:'fab-feeling'),
    body:_loading
      ?const Center(child:CircularProgressIndicator())
      :_space==null?Center(child:Text(tr(context,'noSpace')))
      :TabBarView(controller:_tabs,children:[
        RefreshIndicator(onRefresh:_load,child:ListView(
          padding:const EdgeInsets.fromLTRB(16,12,16,96),children:[
          if(_error!=null)Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
          if(FilterGroupSpec.showing(_filterGroups()).isNotEmpty)FilterShowingLine(
            labels:FilterGroupSpec.showing(_filterGroups()),
            onClear:()=>setState(()=>_requestFilter='all')),
          _requestHistory(),
        ])),
        RefreshIndicator(onRefresh:_load,child:ListView(
          padding:const EdgeInsets.fromLTRB(16,12,16,96),children:[
          if(FilterGroupSpec.showing(_filterGroups()).isNotEmpty)FilterShowingLine(
            labels:FilterGroupSpec.showing(_filterGroups()),
            onClear:()=>setState(()=>_filter='all')),
          TextField(
            onChanged:(value)=>setState(()=>_journalSearch=value),
            decoration:const InputDecoration(
              prefixIcon:Icon(Icons.search),
              labelText:'Search feelings journal',
              border:OutlineInputBorder())),
          const SizedBox(height:10),
          _journal(),
        ])),
      ]),
  );

  /// R55: journal cards lead with who and how they felt, in words and colour.
  Widget _journal()=>StreamBuilder<List<Map<String,dynamic>>>(
    stream:_stream,builder:(context,snapshot){
    if(snapshot.hasError) { return Text(tr(context,'loadFailed')); }
    if(!snapshot.hasData) {
      return const Center(child:CircularProgressIndicator());
    }
    final term=_journalSearch.trim().toLowerCase();
    final entries=snapshot.data!.where((x)=>
      (_filter=='all'||x['visibility']==_filter)&&
      (term.isEmpty||[
       x['checkin_date'],x['message'],x['gratitude'],
      ].map((v)=>v?.toString().toLowerCase()??'')
       .join(' ').contains(term))).toList();
    if(entries.isEmpty) {
      return Padding(
        padding:const EdgeInsets.all(36),
        child:Text(tr(context,'noCheckins'),textAlign:TextAlign.center));
    }
    final me=_client.auth.currentUser?.id ?? '';
    final theme=Theme.of(context);
    return Column(children:entries.map((entry){
      final own=(entry['created_by'] as String? ?? '')==me;
      final private=entry['visibility']=='private';
      final mood=(entry['mood'] as num).toInt().clamp(1,5).toInt();
      final color=_moodColor(mood);
      final date=DateTime.tryParse(entry['checkin_date']?.toString()??'');
      final message=entry['message']?.toString()??'';
      return Card(elevation:0,clipBehavior:Clip.antiAlias,
        color:Color.alphaBlend(color.withValues(alpha:.07),theme.colorScheme.surface),
        margin:const EdgeInsets.only(bottom:10),
        child:ExpansionTile(
          leading:Icon(_moodIcons[mood-1],color:color,size:34),
          title:Text('${own?'You':_partnerName??'Your partner'} · ${_moodWords[mood-1]}',
            style:theme.textTheme.titleSmall?.copyWith(fontWeight:FontWeight.w700)),
          subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            if(message.isNotEmpty)Text(message,maxLines:2,overflow:TextOverflow.ellipsis,
              style:theme.textTheme.bodyMedium),
            Text([
              date==null?entry['checkin_date']?.toString()??'':
                MaterialLocalizations.of(context).formatMediumDate(date),
              if(private)'Only me',
            ].join(' · '),style:theme.textTheme.labelSmall),
          ]),
          trailing:own?PopupMenuButton<String>(
            tooltip:'More',
            onSelected:(v){
              if(v=='edit')_edit(entry);
              if(v=='log')openChangeLog(context,kind:'checkin',recordId:entry['id'].toString(),
                recordTitle:entry['checkin_date']?.toString());
            },
            itemBuilder:(_)=>const [
              PopupMenuItem(value:'edit',child:Text('Edit')),
              PopupMenuItem(value:'log',child:Text('Change log')),
            ]):null,
          childrenPadding:const EdgeInsets.fromLTRB(16,0,16,14),
          expandedCrossAxisAlignment:CrossAxisAlignment.stretch,
          children:[
            if(message.isNotEmpty)_detail('What’s on my mind',message),
            if((entry['gratitude']?.toString()??'').isNotEmpty)
              _detail('Something I’m grateful for',entry['gratitude'].toString()),
            if(own&&private)Align(
              alignment:AlignmentDirectional.centerEnd,
              child:PrivateShareButton(
                objectType:'checkin',objectId:entry['id'] as String)),
          ],
        ));
    }).toList());
  });
}

/// R55: "Check on your partner" as a page with Cancel/Send at the bottom.
class CheckinRequestPage extends StatefulWidget {
  const CheckinRequestPage({super.key,this.partnerName});
  final String? partnerName;
  @override State<CheckinRequestPage> createState()=>_CheckinRequestPageState();
}

class _CheckinRequestPageState extends State<CheckinRequestPage> {
  final note=TextEditingController();
  @override void dispose(){note.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>EditorScaffold(
    title:'Check on ${widget.partnerName??'your partner'}',
    isNew:true,isChanged:()=>note.text.trim().isNotEmpty,isComplete:()=>true,
    listenTo:[note],saveLabel:'Send',
    onSave:()=>Navigator.pop(context,note.text),
    body:ListView(padding:const EdgeInsets.all(18),children:[
      Text('A gentle invitation to share how they feel. They choose whether and when to answer. '
        'It stays open for seven days, then quietly moves to Past without reminders.',
        style:Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height:16),
      TextField(controller:note,maxLength:500,minLines:3,maxLines:6,
        decoration:const InputDecoration(
          labelText:'Personal message (optional)',
          hintText:'How are you doing, my love?',
          border:OutlineInputBorder())),
    ]));
}

class CheckinEditor extends StatefulWidget {
  const CheckinEditor({super.key,required this.spaceId,this.existing});
  final String spaceId;
  final Map<String,dynamic>? existing;
  @override
  State<CheckinEditor> createState()=>_CheckinEditorState();
}
class _CheckinEditorState extends State<CheckinEditor> {
  final _client=Supabase.instance.client;
  late final TextEditingController _message,_gratitude;
  late DateTime _date;
  late int _mood;
  late String _visibility;
  bool _saving=false;
  String? _error;

  bool get _canEdit=>widget.existing==null ||
      widget.existing!['created_by']==_client.auth.currentUser?.id;
  @override
  void initState(){
    super.initState();
    _message=TextEditingController(text:widget.existing?['message'] as String? ?? '');
    _gratitude=TextEditingController(text:widget.existing?['gratitude'] as String? ?? '');
    _date=DateTime.tryParse(widget.existing?['checkin_date'] as String? ?? '')??DateTime.now();
    _mood=(widget.existing?['mood'] as num?)?.toInt()??3;
    _visibility=widget.existing?['visibility'] as String? ?? 'shared';
  }
  @override
  void dispose(){_message.dispose();_gratitude.dispose();super.dispose();}

  Future<void> _save() async {
    if(!_canEdit || _saving)return;
    if(!ConnectionRules.validCheckin(
      day:_date,now:DateTime.now(),mood:_mood,
      message:_message.text,gratitude:_gratitude.text)){
      setState(()=>_error=tr(context,'checkinValidation'));return;
    }
    setState((){_saving=true;_error=null;});
    final date='${_date.year}-${_date.month.toString().padLeft(2,'0')}-'
      '${_date.day.toString().padLeft(2,'0')}';
    try{
      final fields=<String,dynamic>{
        'mood':_mood,'message':_message.text.trim(),
        'gratitude':_gratitude.text.trim(),
      };
      if(widget.existing==null) {
        // Check uniqueness explicitly for a friendly message.
        final previous=await _client.from('daily_checkins').select('id')
          .eq('created_by',_client.auth.currentUser!.id)
          .eq('checkin_date',date).limit(1);
        if(previous.isNotEmpty){
          if(mounted)setState(()=>_error=tr(context,'checkinAlreadyExists'));
          return;
        }
        await _client.from('daily_checkins').insert({
          ...fields,'space_id':widget.spaceId,
          'created_by':_client.auth.currentUser!.id,
          'checkin_date':date,'visibility':_visibility,
        });
      }else{
        final rows=await _client.from('daily_checkins')
          .update(fields).eq('id',widget.existing!['id'] as String)
          .select('id');
        if(rows.isEmpty) throw StateError('No editable checkin');
      }
      if(mounted)Navigator.of(context).pop();
    }on PostgrestException catch(e){
      if(mounted)setState(()=>_error=e.message);
    }catch(_){
      if(mounted)setState(()=>_error=tr(context,'saveFailed'));
    }finally{
      if(mounted)setState(()=>_saving=false);
    }
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(tr(context,'dailyCheckin'))),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
      if(!_canEdit)Text(tr(context,'viewOnly')),
      OutlinedButton.icon(
        onPressed:!_canEdit || _saving || widget.existing!=null
          ? null : ()async{
          final now=DateTime.now();
          final selected=await showDatePicker(context:context,
            initialDate:_date,firstDate:DateTime(2020),lastDate:now);
          if(mounted && selected!=null)setState(()=>_date=selected);
        },
        icon:const Icon(Icons.event),
        label:Text('${_date.year}-${_date.month}-${_date.day}')),
      const SizedBox(height:18),
      Text(tr(context,'howAreYouFeeling'),
        style:Theme.of(context).textTheme.titleMedium),
      const SizedBox(height:8),
      Wrap(spacing:6,children:List.generate(5,(i){
        return ChoiceChip(
          key:Key('mood-${i+1}'),
          label:Text('${i+1}'),
          selected:_mood==i+1,
          onSelected:!_canEdit || _saving?null:
            (_)=>setState(()=>_mood=i+1));
      })),
      const SizedBox(height:14),
      TextField(controller:_message,readOnly:!_canEdit,
        maxLength:2000,minLines:2,maxLines:5,
        decoration:InputDecoration(
          labelText:'What’s on your mind?',
          border:const OutlineInputBorder())),
      const SizedBox(height:12),
      TextField(controller:_gratitude,readOnly:!_canEdit,maxLength:500,
        minLines:1,maxLines:3,
        decoration:InputDecoration(
          labelText:'Something I’m grateful for',
          border:const OutlineInputBorder())),
      const SizedBox(height:12),
      Text(tr(context,'visibility')),
      Wrap(spacing:8,children:['shared','private'].map((v)=>ChoiceChip(
        selected:_visibility==v,label:Text(tr(context,v)),
        onSelected:widget.existing!=null || _saving?null:
          (_)=>setState(()=>_visibility=v))).toList()),
      Text(tr(context,'privacyFixed'),
        style:Theme.of(context).textTheme.bodySmall),
      const SizedBox(height:16),
      if(_error!=null)Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      if(_canEdit)FilledButton(
        onPressed:_saving?null:_save,child:Text(tr(context,'save'))),
    ])),
  );
}

class PartnerCheckinReplyScreen extends StatefulWidget {
 const PartnerCheckinReplyScreen({super.key,required this.request});
 final Map<String,dynamic> request;
 @override State<PartnerCheckinReplyScreen> createState()=>
   _PartnerCheckinReplyScreenState();
}
class _PartnerCheckinReplyScreenState extends State<PartnerCheckinReplyScreen> {
 final mind=TextEditingController();
 final topic=TextEditingController();
 int mood=3;
 bool saving=false;
 String? error;
 @override void dispose(){mind.dispose();topic.dispose();super.dispose();}
 Future<void> _save() async{
   if(saving)return;
   setState((){
     saving=true;error=null;
   });
   try{
     final db=Supabase.instance.client;
     if(!CheckinRequestRules.canRespond(widget.request,
        db.auth.currentUser?.id,DateTime.now())){
       throw StateError('This invitation has already been answered or expired.');
     }
     final rows=await db.from('partner_checkin_requests')
       .update({
         'response_mood':mood,
         'response_message':mind.text.trim(),
         'response_topic':topic.text.trim(),
       })
       .eq('id',widget.request['id'].toString())
       .eq('recipient_id',db.auth.currentUser!.id)
       .isFilter('responded_at',null).select('id');
     if(rows.isEmpty)throw StateError('This request was already answered.');
     if(mounted)Navigator.pop(context);
   }on PostgrestException catch(e){
     if(mounted)setState(()=>error=e.message);
   }catch(e){
     if(mounted)setState(()=>error=e.toString());
   }finally{
     if(mounted)setState(()=>saving=false);
   }
 }
 @override Widget build(BuildContext context)=>Scaffold(
   appBar:AppBar(title:const Text('Respond to your love')),
   body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
     const Text('Your partner wants to know how you are doing.',
       style:TextStyle(fontSize:17,fontWeight:FontWeight.w600)),
     if((widget.request['note']?.toString()??'').isNotEmpty)
       Card(child:Padding(padding:const EdgeInsets.all(14),
         child:Text(widget.request['note'].toString()))),
     const SizedBox(height:16),
     Text('How do you feel? ($mood/5)',
       style:Theme.of(context).textTheme.titleMedium),
     const SizedBox(height:7),
     Wrap(spacing:8,children:[
       for(var i=1;i<=5;i++)ChoiceChip(
         label:Text(i.toString()),selected:mood==i,
         onSelected:saving?null:(_)=>setState(()=>mood=i)),
     ]),
     const SizedBox(height:15),
     TextField(controller:mind,maxLength:2000,minLines:2,maxLines:5,
       decoration:const InputDecoration(labelText:'What’s on your mind?',
         border:OutlineInputBorder())),
     const SizedBox(height:15),
     TextField(controller:topic,maxLength:1000,minLines:2,maxLines:4,
       decoration:const InputDecoration(
         labelText:'Something you need to talk about?',
         border:OutlineInputBorder())),
     const Text('Your response is shared only with your partner. '
       'You can choose when to answer while this invitation is open. '
       'Nothing is sent until you press Send.'),
     if(error!=null)Text(error!,
       style:TextStyle(color:Theme.of(context).colorScheme.error)),
     const SizedBox(height:12),
     FilledButton.icon(
       onPressed:saving?null:_save,
       icon:const Icon(Icons.send_outlined),
       label:Text(saving?'Sending…':'Send my response')),
   ])),
 );
}
