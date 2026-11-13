import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../../l10n/onespace_strings.dart';
import '../sharing/private_share_button.dart';
import '../sharing/share_grant_watcher.dart';
import '../connection/connection_rules.dart';

/// Each person may make one personal check-in per local calendar date. The
/// partner can view shared entries, but only the author can edit their entry.
class CheckinsScreen extends StatefulWidget {
  const CheckinsScreen({super.key,this.initialRequestId});
  final String? initialRequestId;
  @override
  State<CheckinsScreen> createState()=>_CheckinsScreenState();
}

class _CheckinsScreenState extends State<CheckinsScreen> {
  final _client=Supabase.instance.client;
  String? _space;
  Stream<List<Map<String,dynamic>>>? _stream;
  Stream<List<Map<String,dynamic>>>? _requests;
  String? _error;
  bool _loading=true;
  StreamSubscription<List<Map<String,dynamic>>>? _grants;
  String _filter='all';
  bool _openedInitialRequest=false;

  @override
  void initState(){super.initState();_load();}

  @override
  void dispose() { _grants?.cancel(); super.dispose(); }

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
        .select('id,space_id,sender_id,recipient_id,note,requested_at,responded_at')
        .eq('id',requestId).eq('space_id',_space!).limit(1);
      if(!mounted||rows.isEmpty)return;
      final row=rows.first;
      if(row['recipient_id']==_client.auth.currentUser?.id &&
        row['responded_at']==null){
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
      if (id != null){
        _watchGrants(id);
        unawaited(_openInitialRequest());
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
      final note=TextEditingController();
      try{
        final accepted=await showDialog<bool>(
          context:context,builder:(ctx)=>AlertDialog(
            title:const Text('Check on your love'),
            content:Column(mainAxisSize:MainAxisSize.min,
              crossAxisAlignment:CrossAxisAlignment.start,children:[
              const Text('A gentle invitation for your partner to share '
                'how they feel. They choose when to respond.'),
              const SizedBox(height:12),
              TextField(controller:note,maxLength:500,maxLines:3,
                decoration:const InputDecoration(
                  labelText:'Personal message (optional)',
                  hintText:'How are you doing, my love?',
                  border:OutlineInputBorder())),
            ]),
            actions:[
              TextButton(onPressed:()=>Navigator.pop(ctx,false),
                child:const Text('Cancel')),
              FilledButton(onPressed:()=>Navigator.pop(ctx,true),
                child:const Text('Send check-in')),
            ],
          ),
        );
        if(accepted!=true||!mounted)return;
        await _client.from('partner_checkin_requests').insert({
          'space_id':space,'sender_id':me,
          'recipient_id':peer['user_id'],'note':note.text.trim(),
        });
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content:Text('Your check-in was sent.')));
      }finally{note.dispose();}
    }on PostgrestException catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Check-in could not be sent: '+e.message)));
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('Could not send check-in. Please retry.')));
    }
  }

  Future<void> _respond(Map<String,dynamic> request) async{
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder:(_)=>PartnerCheckinReplyScreen(request:request)));
  }

  Widget _requestHistory(){
    final me=_client.auth.currentUser?.id;
    return StreamBuilder<List<Map<String,dynamic>>>(
      stream:_requests,builder:(ctx,snapshot){
        if(snapshot.hasError)return const Text('Could not load partner check-ins.');
        if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
        final rows=snapshot.data!;
        if(rows.isEmpty)return const Card(elevation:0,child:Padding(
          padding:EdgeInsets.all(14),
          child:Text('No requests yet. You can check on each other anytime.')));
        return Column(children:[
          for(final item in rows.take(60))Card(elevation:0,child:ListTile(
            leading:Icon(item['sender_id']==me?
              Icons.send_outlined:Icons.mark_email_unread_outlined),
            title:Text(item['sender_id']==me?'You checked on your partner':
              'Your partner checked on you'),
            subtitle:Text([
              _dateTime(item['requested_at']),
              if((item['note']?.toString()??'').isNotEmpty)
                item['note'].toString(),
              if(item['responded_at']!=null)
                'Answered: '+_dateTime(item['responded_at']),
              if(item['response_mood']!=null)
                'Mood '+item['response_mood'].toString()+'/5',
              if((item['response_message']?.toString()??'').isNotEmpty)
                'On their mind: '+item['response_message'].toString(),
              if((item['response_topic']?.toString()??'').isNotEmpty)
                'To talk about: '+item['response_topic'].toString(),
              if(item['responded_at']==null)'Awaiting a reply',
            ].join('\n'),maxLines:7,overflow:TextOverflow.ellipsis),
            isThreeLine:true,
            trailing:item['recipient_id']==me&&item['responded_at']==null?
              FilledButton(onPressed:()=>_respond(item),
                child:const Text('Respond')):null,
            onTap:item['recipient_id']==me&&item['responded_at']==null?
              ()=>_respond(item):null,
          )),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(tr(context,'checkinTitle'))),
    body:RefreshIndicator(onRefresh:_load,child:ListView(
      padding:const EdgeInsets.all(20),children:[
      Text(tr(context,'checkinSubtitle')),
      const SizedBox(height:12),
      if(_error!=null)Text(_error!,style:const TextStyle(color:Colors.red)),
      if(_loading)
        const Padding(padding:EdgeInsets.all(30),
          child:Center(child:CircularProgressIndicator()))
      else if(_space==null)Text(tr(context,'noSpace'))
      else ...[
        Card(elevation:0,child:Padding(padding:const EdgeInsets.all(12),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('How is your heart today?',
              style:Theme.of(context).textTheme.titleMedium),
            const SizedBox(height:8),
            Wrap(spacing:8,runSpacing:8,children:[
              FilledButton.icon(
                onPressed:()=>_edit(),
                icon:const Icon(Icons.favorite_outline),
                label:const Text('Record my feelings')),
              FilledButton.tonalIcon(
                onPressed:_askPartner,
                icon:const Icon(Icons.mark_chat_unread_outlined),
                label:const Text('Check on my partner')),
            ]),
          ]))),
        const SizedBox(height:13),
        Text('Check-in conversations',
          style:Theme.of(context).textTheme.titleMedium),
        _requestHistory(),
        const SizedBox(height:20),
        Text('Our feelings journal',
          style:Theme.of(context).textTheme.titleMedium),
        const SizedBox(height:12),
        Wrap(spacing:8,children:['all','shared','private'].map((v)=>ChoiceChip(
          label:Text(tr(context,v)),selected:_filter==v,
          onSelected:(_)=>setState(()=>_filter=v))).toList()),
        StreamBuilder<List<Map<String,dynamic>>>(
          stream:_stream,builder:(context,snapshot){
          if(snapshot.hasError) { return Text(tr(context,'loadFailed')); }
          if(!snapshot.hasData) {
            return const Center(child:CircularProgressIndicator());
          }
          final entries=snapshot.data!.where((x)=>
            _filter=='all'||x['visibility']==_filter).toList();
          if(entries.isEmpty) {
            return Padding(
              padding:const EdgeInsets.all(36),
              child:Text(tr(context,'noCheckins'),textAlign:TextAlign.center));
          }
          final me=_client.auth.currentUser?.id ?? '';
          return Column(children:entries.map((entry){
            final owner=entry['created_by'] as String? ?? '';
            final own=owner==me;
            final private=entry['visibility']=='private';
            final mood=(entry['mood'] as num).toInt();
            const moodIcons=[
              Icons.sentiment_very_dissatisfied_outlined,
              Icons.sentiment_dissatisfied_outlined,
              Icons.sentiment_neutral_outlined,
              Icons.sentiment_satisfied_outlined,
              Icons.sentiment_very_satisfied_outlined,
            ];
            return Card(elevation:0,child:Column(children:[
              ListTile(
                leading:Icon(moodIcons[mood.clamp(1,5).toInt()-1]),
                title:Text(entry['checkin_date'] as String? ?? ''),
                subtitle:Text([
                  tr(context,entry['visibility'] as String? ?? 'shared'),
                  if(own)tr(context,'me') else tr(context,'partner'),
                  if((entry['message'] as String? ?? '').isNotEmpty)
                    entry['message'] as String,
                  if((entry['gratitude'] as String? ?? '').isNotEmpty)
                    '${tr(context,'gratitude')}: ${entry['gratitude']}',
                ].join(' • '),maxLines:4,overflow:TextOverflow.ellipsis),
                trailing:own?const Icon(Icons.edit_outlined):
                  const Icon(Icons.visibility_outlined),
                onTap:()=>_edit(entry)),
              if(own && private) Align(
                alignment:AlignmentDirectional.centerEnd,
                child:PrivateShareButton(
                  objectType:'checkin',objectId:entry['id'] as String)),
            ]));
          }).toList());
        }),
      ],
    ])),
  );
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
      if(_error!=null)Text(_error!,style:const TextStyle(color:Colors.red)),
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
       'You can answer whenever you feel comfortable.'),
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
