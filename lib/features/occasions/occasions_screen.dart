import '../../core/preferred_currency.dart';
import '../counters/counter_sources.dart';
import '../counters/counter_source_actions.dart';
import '../../core/form_kit.dart';
import '../../core/item_menu.dart';
import '../../core/editor_scaffold.dart';
import '../../core/status_look.dart';
import '../../core/linked_items.dart';
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/current_space_cache.dart';
import '../../core/app_env.dart';
import '../../core/record_collection_search_rules.dart';
import '../../core/record_list_top_actions.dart';
import '../calendar/calendar_rules.dart';
import 'occasion_rules.dart';
import '../mentions/partner_mention_button.dart';
import 'occasion_budget_workspace.dart';
import 'occasion_source_picker.dart';
import 'package:onespace/l10n/phrases.dart';

const occasionKinds=<String,String>{
 'birthday':'Birthday','anniversary':'Anniversary',
 'holiday':'Holiday','celebration':'Celebration','other':'Other'};
/// R68: the status is automatic (set by the database); these are its words.
const occasionStages=<String,String>{
 'planning':'Planning','preparing':'Preparing','ready':'Ready',
 'celebrated':'Past','cancelled':'Cancelled'};

class OccasionsScreen extends StatefulWidget{
 const OccasionsScreen({super.key,this.initialPlanId});
 final String? initialPlanId;
 @override State<OccasionsScreen> createState()=>_OccasionsScreenState();
}
class _OccasionsScreenState extends State<OccasionsScreen>{
 final db=Supabase.instance.client;
 String? space,error;
 bool personalReady=false;
 bool loading=true,archived=false,opened=false;
 String filter='upcoming',query='';
 List<Map<String,dynamic>> plans=[];
 RealtimeChannel? _channel;
 Timer? _refresh;
 String? _watchedSpace;
 int _loadVersion=0;

 @override void initState(){super.initState();load();}
 @override void dispose(){
  _loadVersion++;
  _refresh?.cancel();
  final old=_channel;
  if(old!=null)unawaited(db.removeChannel(old));
  super.dispose();
 }
 void _scheduleRefresh(){
  _refresh?.cancel();
  _refresh=Timer(const Duration(milliseconds:650),(){
   if(mounted)load();
  });
 }
 void _watch(String id){
  if(_watchedSpace==id)return;
  final old=_channel;
  if(old!=null)unawaited(db.removeChannel(old));
  _watchedSpace=id;
  _channel=db.channel('occasion-plans-'+id)
   .onPostgresChanges(
     event:PostgresChangeEvent.all,schema:'public',table:'occasion_plans',
     filter:PostgresChangeFilter(
       type:PostgresChangeFilterType.eq,column:'space_id',value:id),
     callback:(_)=>_scheduleRefresh())
   .subscribe();
 }
 Future<void> load()async{
  final request=++_loadVersion;
  final user=db.auth.currentUser?.id;
  if(user==null){
   if(mounted)setState((){
    loading=false;space=null;plans=[];error=null;
   });
   return;
  }
  try{
   var id=await CurrentSpaceCache.instance.get();
   var ownScope=false;
   if(!OneSpaceEnv.isProduction){
    final scopes=await db.rpc('my_storage_scopes');
    if(scopes is! Map||scopes['private_space_id']?.toString()!=user){
      throw StateError('Account-owned Occasions scope unavailable');
    }
    id=scopes['shared_space_id']?.toString();ownScope=true;
   }
   if(!mounted||request!=_loadVersion||db.auth.currentUser?.id!=user)return;
   if(id==null&&!ownScope){
    setState((){loading=false;space=null;personalReady=false;plans=[];error=null;});
    final prior=_channel;
    if(prior!=null)unawaited(db.removeChannel(prior));
    _channel=null;_watchedSpace=null;
    return;
   }
   final scopeQuery=OneSpaceEnv.isProduction
     ?db.from('occasion_plans').select().eq('space_id',id!)
     :db.from('occasion_plans').select();
   final rows=await scopeQuery.order('updated_at',ascending:false).limit(200);
   if(!mounted||request!=_loadVersion||db.auth.currentUser?.id!=user)return;
   setState((){
    space=id;personalReady=ownScope;
    plans=List<Map<String,dynamic>>.from(rows);
    loading=false;error=null;
   });
   if(id!=null)_watch(id);
   else {
    final prior=_channel;
    if(prior!=null)unawaited(db.removeChannel(prior));
    _channel=null;_watchedSpace=null;
   }
   if(!opened&&widget.initialPlanId!=null){
    opened=true;
    final match=plans.where((p)=>p['id']==widget.initialPlanId).firstOrNull;
    WidgetsBinding.instance.addPostFrameCallback((_){
     if(!mounted)return;
     if(match!=null){open(match);}else{
      Navigator.of(context).push<void>(MaterialPageRoute(
       builder:(_)=>OccasionDetail(id:widget.initialPlanId!)));
     }
    });
   }
  }catch(_){
   if(mounted&&request==_loadVersion&&db.auth.currentUser?.id==user)setState((){
    loading=false;error='Unable to load occasion plans.';
   });
  }
 }
 Future<void> edit([Map<String,dynamic>? plan])async{
  if(space==null&&!personalReady)return;
  final saved=await Navigator.of(context).push<bool>(MaterialPageRoute(
   builder:(_)=>OccasionEditor(spaceId:space??'',existing:plan)));
  if(saved==true&&mounted)await load();
 }
 Future<void> open(Map<String,dynamic> p)async{
  await Navigator.of(context).push<void>(MaterialPageRoute(
   builder:(_)=>OccasionDetail(id:p['id'].toString())));
  if(mounted)await load();
 }
 /// R55: this screen's filter groups (drawn by the shared panel).
 List<FilterGroupSpec> _filterGroups()=>[FilterGroupSpec(id:'show',label:tt('Show'),options:const {'upcoming':'Upcoming','private':'Only me','shared':'Both of us','all':'All'},selected:filter,defaultValue:'upcoming')];

 @override Widget build(BuildContext context){
  final today=DateTime.now();
  final shown=plans.where((p){
   if(!RecordCollectionSearchRules.inHistory(p,archived))return false;
   if(!RecordCollectionSearchRules.matches(p,query,
    fields:const ['title','honoree_name','notes','kind']))return false;
   if(filter=='all'||archived)return true;
   if(filter=='private')return p['visibility']=='private';
   if(filter=='shared')return p['visibility']=='shared';
   return p['status']!='cancelled'&&p['status']!='celebrated'&&
    OccasionRules.nextDate(original:DateTime.parse(p['occasion_on'].toString()),
      annual:p['annual']==true,today:today)!=null;
  }).toList();
  shown.sort((a,b){
   DateTime next(Map<String,dynamic> p)=>OccasionRules.nextDate(
    original:DateTime.parse(p['occasion_on'].toString()),
    annual:p['annual']==true,today:today)??DateTime(2100);
   return next(a).compareTo(next(b));
  });
  return Scaffold(
   appBar:AppBar(title:Text(tt('Occasions')),actions:[
    RecordListTopActions(
     historyKinds:const ['occasion'],historyTitle:tt('Occasions'),
     showHistory:archived,
     onToggleHistory:()=>setState(()=>archived=!archived),
     groups:_filterGroups(),
      onApply:(v)=>setState((){filter=v['show']!;}),
     ),
   ],bottom:filterShowingBar(_filterGroups(),removed:archived,onClear:()=>setState((){archived=false;filter='upcoming';}))),
   floatingActionButton:space==null&&!personalReady?null:
    FloatingActionButton.extended(heroTag:'fab-occasions',
    onPressed:()=>edit(),icon:const Icon(Icons.add),label:Text(tt('Add occasion'))),
   body:RefreshIndicator(onRefresh:load,child:ListView(
    physics:const AlwaysScrollableScrollPhysics(),
    padding:const EdgeInsetsDirectional.fromSTEB(16,12,16,90),children:[
    Text(tt('Plan the thoughtful moments'),style:Theme.of(context).textTheme.titleLarge),
    const SizedBox(height:6),
    Text(tt('Remember the day, prepare surprises early, and start saving in time. Private plans stay private.')),
    const SizedBox(height:12),
    TextField(
     onChanged:(value)=>setState(()=>query=value),
     decoration:InputDecoration(
      prefixIcon:Icon(Icons.search),
      labelText:tt('Search occasions'),
      hintText:tt('Title, person, occasion type or notes'),
      border:OutlineInputBorder())),
    const SizedBox(height:10),
    if(archived)Padding(padding:const EdgeInsets.only(bottom:8),
     child:Text(tt('Removed occasions · Open one to restore it.'),
      style:Theme.of(context).textTheme.bodySmall)),
    if(error!=null)Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error)),
    if(loading)const Center(child:Padding(padding:EdgeInsets.all(24),child:CircularProgressIndicator()))
    else if(space==null&&!personalReady)Text(tt('Connect your shared space first.'))
    else if(shown.isEmpty)Card(child:Padding(padding:EdgeInsets.all(20),
     child:Text(tt('Nothing planned here yet. Start with an upcoming birthday, anniversary or holiday.'))))
    else for(final p in shown)Card(elevation:0,child:ListTile(
     leading:CircleAvatar(child:StatusLook.mark(p['status']=='ready'?null:p['status']?.toString())??Icon(p['visibility']=='private'?
      Icons.lock_outline:Icons.card_giftcard_outlined)),
     title:Text(tt(p['title'].toString()),style:StatusLook.title(context,p['status']=='ready'?null:p['status']?.toString(),
      Theme.of(context).textTheme.titleMedium)),
     subtitle:Text(tt([
      if((p['honoree_name']??'').toString().isNotEmpty)p['honoree_name'].toString(),
      occasionKinds[p['kind']]??'Occasion',
      occasionStages[p['status']]??'Planning',
      if(p['visibility']=='private')'Only me',
      OccasionRules.countdown(OccasionRules.nextDate(
       original:DateTime.parse(p['occasion_on'].toString()),
       annual:p['annual']==true,today:today),today),
     ].join(' · '))),
     trailing:ItemMenu(kind:'occasion',recordId:p['id'].toString(),title:p['title']?.toString(),
      onOpen:()=>open(p),openLabel:tt('Open'),table:'occasion_plans',
      moreActions:[
       if((OneSpaceEnv.isProduction||p['private_space_id']==null)&&
           space!=null&&p['archived_at']==null)
          ItemMenuAction('Add to counters',Icons.hourglass_bottom_outlined,
        ()=>CounterSourceActions.open(context,space!,CounterSource.occasion(p))),
      ],
      removed:p['archived_at']!=null,onChanged:load),
     onTap:()=>open(p))),
   ])));
 }
}

const prepChoices=<int,String>{7:'1 week',14:'2 weeks',30:'1 month'};

/// The "Start preparing" reminder, in either language.
const prepReminderFilter='title.like.Start preparing*,title.like.ابدأ التحضير*';

/// R68 (forms review): the occasion's first step. Pick a special date or a
/// holiday (or type your own), say who it is for, when to start preparing
/// (a reminder is set for that day), the budget and first ideas. A new
/// occasion says Next: it is saved and its page opens.
class OccasionEditor extends StatefulWidget{
 const OccasionEditor({super.key,required this.spaceId,this.existing,this.initialDate,this.initialKind});
 final String spaceId;
 final Map<String,dynamic>? existing;
 final DateTime? initialDate;
 final String? initialKind;
 @override State<OccasionEditor> createState()=>_OccasionEditorState();
}
class _OccasionEditorState extends State<OccasionEditor> with FormChangeTracker<OccasionEditor>{
 @override String get signature=>[title.text,notes.text,budget.text,currency.text,honoree.text,kind,
  visibility,date,prepDays,forWhom,sourceKind,sourceRef].join('|');

 final db=Supabase.instance.client;
 late final TextEditingController title,notes,budget,currency,honoree;
 late String kind,visibility;
 DateTime? date;
 int prepDays=14;
 String forWhom='partner';
 String? sourceKind,sourceRef,sourceLabel,myName;
 bool busy=false;
 SpacePeople? people;
 String? error;
 @override void initState(){
  super.initState();
  final p=widget.existing??{};
  title=TextEditingController(text:(p['title']??'').toString());
  honoree=TextEditingController(text:(p['honoree_name']??'').toString());
  notes=TextEditingController(text:(p['notes']??'').toString());
  budget=TextEditingController(text:(p['budget']??'').toString());
  currency=TextEditingController(text:(p['currency']??PreferredCurrency.code).toString());
  date=DateTime.tryParse((p['occasion_on']??'').toString())??widget.initialDate;
  kind=(p['kind']??widget.initialKind??'birthday').toString();
  visibility=(p['visibility']??'private').toString();
  prepDays=(p['prep_lead_days'] as num?)?.toInt()??14;
  sourceKind=p['source_kind']?.toString();sourceRef=p['source_ref']?.toString();
  if(sourceKind!=null)sourceLabel=(p['title']??'').toString();
  forWhom=widget.existing==null?'partner':'other';
  SpacePeople.load().then((v)async{
   String? mine;
   try{
    final me=db.auth.currentUser?.id;
    if(me!=null){
     final row=await db.from('profiles').select('display_name').eq('id',me).maybeSingle();
     mine=(row?['display_name']??'').toString().trim().split(RegExp(r'\s+')).first;
    }
   }catch(_){}
   if(!mounted)return;
   setState((){
    people=v;myName=(mine??'').isEmpty?null:mine;
    final h=honoree.text.trim();
    if(widget.existing!=null){
     if(h.isEmpty||h=='Both of us'){forWhom='us';}
     else if(h==(v?.partnerName??'')){forWhom='partner';}
     else if(h==(myName??'')){forWhom='me';}
     else{forWhom='other';}
    }
   });
  });
 }
 @override void dispose(){
  for(final c in [title,notes,budget,currency,honoree]){c.dispose();}
  super.dispose();
 }
 Future<void> pickSource()async{
  if(!OneSpaceEnv.isProduction&&widget.spaceId.isEmpty){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content:Text(tt('Enter your personal occasion date manually. '
     'Linking special dates will be available after the private calendar integration.'))));
   return;
  }
  final s=await pickOccasionSource(context,widget.spaceId);
  if(s==null||!mounted)return;
  setState((){
   sourceKind=s.kind;sourceRef=s.ref;sourceLabel=s.title;
   title.text=s.title;date=s.date;kind=s.occasionKind;
   if(s.occasionKind=='holiday'||s.occasionKind=='anniversary'){forWhom='us';}
   else if(s.occasionKind=='birthday'&&people!=null){
    forWhom=s.title.startsWith(people!.partnerName)?'partner':'me';
   }
  });
 }
 String get honoreeValue=>switch(forWhom){
  'me'=>myName??'Me',
  'partner'=>people?.partnerName??'Partner',
  'us'=>'Both of us',
  _=>honoree.text.trim(),
 };
 /// The reminder that starts the preparation (created or moved).
 Future<void> syncPrepReminder(String planId,DateTime on,String name)async{
  final start=DateTime(on.year,on.month,on.day-prepDays,9);
  if(!start.isAfter(DateTime.now()))return;
  final label=tt('Start preparing: ')+name;
  final short=label.length>160?label.substring(0,160):label;
  try{
   final existing=await db.from('reminders').select('id').eq('source_kind','occasion')
    .eq('source_id',planId).or(prepReminderFilter).isFilter('archived_at',null).limit(1);
   if(existing.isNotEmpty){
    await db.from('reminders').update({'title':short,'due_at':start.toUtc().toIso8601String()})
     .eq('id',existing.first['id']);
   }else{
    await db.from('reminders').insert({
     if(!OneSpaceEnv.isProduction&&visibility=='private')
       'private_space_id':db.auth.currentUser!.id
     else 'space_id':widget.spaceId,
     'created_by':db.auth.currentUser!.id,
     'title':short,'due_at':start.toUtc().toIso8601String(),
     'visibility':visibility,'audience':visibility=='private'?'me':'both',
     'source_kind':'occasion','source_id':planId,
    });
   }
  }catch(_){/* The occasion is saved; the reminder can be set from Reminders. */}
 }
 Future<void> save()async{
  if(busy)return;
  final money=budget.text.trim().isEmpty?null:double.tryParse(budget.text.trim().replaceAll(',',''));
  final code=currency.text.trim().toUpperCase();
  if(title.text.trim().isEmpty){setState(()=>error='Add an occasion name.');return;}
  final on=date;
  if(on==null){setState(()=>error='Choose the date.');return;}
  if(budget.text.trim().isNotEmpty&&(money==null||money<0||money>9999999999)){
   setState(()=>error='Enter a valid budget.');return;
  }
  if(!RegExp(r'^[A-Z]{3}$').hasMatch(code)){
   setState(()=>error='Use a three-letter currency code.');return;
  }
  setState((){busy=true;error=null;});
  try{
   // R69: no Kind chips; the kind follows the picked date, or the words.
   if(sourceKind==null)kind=OccasionSourceRules.kindFor(title.text.trim());
   final values=<String,dynamic>{
    'title':title.text.trim(),'kind':kind,'honoree_name':honoreeValue,
    'occasion_on':CalendarRules.sqlDate(on),'prep_lead_days':prepDays,
    'budget':money,'currency':code,'notes':notes.text.trim(),
    'source_kind':sourceKind,'source_ref':sourceRef,
   };
   if(widget.existing==null){
    final personal=!OneSpaceEnv.isProduction&&visibility=='private';
    if(!personal&&widget.spaceId.isEmpty){
     throw StateError('Connect with a partner before sharing an occasion');
    }
    final row=await db.from('occasion_plans').insert({
     ...values,'annual':false,
     if(personal) 'private_space_id':db.auth.currentUser!.id
     else 'space_id':widget.spaceId,
     'created_by':db.auth.currentUser!.id,
     'visibility':visibility,'status':'planning',
    }).select('id').single();
    final id=row['id'].toString();
    await syncPrepReminder(id,on,title.text.trim());
    if(!mounted)return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
     builder:(_)=>OccasionDetail(id:id)),result:true);
    return;
   }
   final id=widget.existing!['id'].toString();
   await db.from('occasion_plans').update(values).eq('id',id);
   final next=OccasionRules.nextDate(original:on,annual:widget.existing!['annual']==true,today:DateTime.now());
   if(next!=null)await syncPrepReminder(id,next,title.text.trim());
   if(mounted)Navigator.pop(context,true);
  }on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Unable to save occasion.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context){
  final editing=widget.existing!=null;
  final theme=Theme.of(context);
  final p=people;
  return EditorScaffold(title:editing?tt('Edit occasion'):tt('New occasion'),
   isNew:!editing,isChanged:()=>changed,isComplete:()=>title.text.trim().isNotEmpty&&date!=null,
   listenTo:[title,notes,budget,currency,honoree],saving:busy,onSave:save,
   saveLabel:editing?'Save':'Next',
   meta:MetaStrip(value:MetaValues(shared:visibility=='shared'),showBelongs:false,showDate:false,
    enabled:!editing,onChanged:(v)=>setState(()=>visibility=
     (!OneSpaceEnv.isProduction&&widget.spaceId.isEmpty)
       ?'private':(v.shared?'shared':'private'))),
   body:ListView(padding:const EdgeInsets.all(18),children:[
   Card(elevation:0,color:theme.colorScheme.secondaryContainer.withValues(alpha:.5),
    child:ListTile(
     leading:Icon(sourceKind==null?Icons.event_available_outlined:Icons.link,color:theme.colorScheme.secondary),
     title:Text(tt(sourceKind==null?'Pick a special date or holiday':sourceLabel??'Linked')),
     subtitle:Text(tt(sourceKind==null?'Or type your own below.'
      :sourceKind=='holiday'?'Linked to a holiday':'Linked to a special date')),
     trailing:sourceKind==null?const Icon(Icons.chevron_right):IconButton(tooltip:tt('Unlink'),
      icon:const Icon(Icons.close),onPressed:()=>setState((){sourceKind=null;sourceRef=null;sourceLabel=null;})),
     onTap:pickSource)),
   const SizedBox(height:12),
   TextField(controller:title,maxLength:160,textCapitalization:TextCapitalization.sentences,
    decoration:InputDecoration(labelText:tt('What are we celebrating? *'),
     hintText:tt('Kay’s birthday, our anniversary…'),border:const OutlineInputBorder())),
   Text(tt('For whom'),style:theme.textTheme.labelLarge),
   const SizedBox(height:6),
   Wrap(spacing:8,runSpacing:6,children:[
    if(p?.partnerId!=null)ChoiceChip(label:Text(tt(p!.partnerName)),selected:forWhom=='partner',
     onSelected:(_)=>setState(()=>forWhom='partner')),
    ChoiceChip(label:Text(tt('Me')),selected:forWhom=='me',onSelected:(_)=>setState(()=>forWhom='me')),
    ChoiceChip(label:Text(tt('Both of us')),selected:forWhom=='us',onSelected:(_)=>setState(()=>forWhom='us')),
    ChoiceChip(label:Text(tt('Someone else')),selected:forWhom=='other',onSelected:(_)=>setState(()=>forWhom='other')),
   ]),
   if(forWhom=='other')Padding(padding:const EdgeInsets.only(top:10),child:TextField(
    controller:honoree,maxLength:120,textCapitalization:TextCapitalization.words,
    decoration:InputDecoration(labelText:tt('Name'),prefixIcon:const Icon(Icons.person_outline),
     border:const OutlineInputBorder()))),
   const SizedBox(height:12),
   DateField(label:tt('Date'),required:true,value:date,first:DateTime(2000),last:DateTime(2100),
    onChanged:(v){if(v!=null)setState(()=>date=v);}),
   ChoiceRow<int>(label:tt('Start preparing'),options:prepChoices,
    selected:prepChoices.containsKey(prepDays)?prepDays:null,
    icons:const {7:Icons.looks_one_outlined,14:Icons.looks_two_outlined,30:Icons.calendar_month_outlined},
    onSelected:(v){if(v!=null)setState(()=>prepDays=v);}),
   Text(tt('A reminder is set for that day.'),style:theme.textTheme.bodySmall),
   FormSection(tt('Budget')),
   Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Expanded(flex:3,child:TextField(controller:budget,
     keyboardType:const TextInputType.numberWithOptions(decimal:true),
     decoration:InputDecoration(labelText:tt('Budget'),border:const OutlineInputBorder()))),
    const SizedBox(width:10),
    Expanded(flex:2,child:TextField(controller:currency,maxLength:3,
     textCapitalization:TextCapitalization.characters,
     decoration:InputDecoration(labelText:tt('Currency'),border:const OutlineInputBorder()))),
   ]),
   TextField(controller:notes,maxLength:5000,minLines:3,maxLines:6,
    decoration:InputDecoration(labelText:tt('Gift ideas, plans or wishes'),
     alignLabelWithHint:true,border:const OutlineInputBorder())),
   if(visibility=='shared')Align(alignment:AlignmentDirectional.centerStart,
    child:PartnerMentionButton(spaceId:widget.spaceId,controller:notes,enabled:true)),
   Text(tt(editing?'Who can see it stays as it was created, to protect surprises.'
    :'Tip: keep surprises Only me.'),style:theme.textTheme.bodySmall),
   if(error!=null)Padding(padding:const EdgeInsets.only(top:10),
    child:Text(tt(error!),style:TextStyle(color:theme.colorScheme.error))),
  ]));
 }
}

class OccasionDetail extends StatefulWidget{
 const OccasionDetail({super.key,required this.id});
 final String id;
 @override State<OccasionDetail> createState()=>_OccasionDetailState();
}
class _OccasionDetailState extends State<OccasionDetail>{
 final _links=GlobalKey<LinkedItemsStripState>();
 final db=Supabase.instance.client;
 Map<String,dynamic>? plan;
 bool loading=true,busy=false,prepReminder=false;
 String? error;
 RealtimeChannel? _channel;
 Timer? _refresh;
 int _loadVersion=0;
 @override void initState(){
  super.initState();
  _channel=db.channel('occasion-detail-'+widget.id)
   .onPostgresChanges(event:PostgresChangeEvent.all,schema:'public',
    table:'occasion_plans',filter:PostgresChangeFilter(
     type:PostgresChangeFilterType.eq,column:'id',value:widget.id),
    callback:(_)=>_scheduleRefresh())
   .subscribe();
  load();
 }
 @override void dispose(){
  _loadVersion++;
  _refresh?.cancel();
  final old=_channel;
  if(old!=null)unawaited(db.removeChannel(old));
  super.dispose();
 }
 void _scheduleRefresh(){
  _refresh?.cancel();
  _refresh=Timer(const Duration(milliseconds:650),(){
   if(mounted)load();
  });
 }
 Future<void> load()async{
  final request=++_loadVersion;
  final user=db.auth.currentUser?.id;
  if(user==null)return;
  try{
   final p=await db.from('occasion_plans').select().eq('id',widget.id).single();
   var hasReminder=false;
   try{
    final r=await db.from('reminders').select('id').eq('source_kind','occasion')
     .eq('source_id',widget.id).or(prepReminderFilter).isFilter('archived_at',null).limit(1);
    hasReminder=r.isNotEmpty;
   }catch(_){}
   if(!mounted||request!=_loadVersion||db.auth.currentUser?.id!=user)return;
   setState((){plan=p;prepReminder=hasReminder;loading=false;error=null;});
  }on PostgrestException catch(e){
   if(mounted&&request==_loadVersion&&db.auth.currentUser?.id==user)
    setState((){loading=false;error=e.message;});
  }catch(_){
   if(mounted&&request==_loadVersion&&db.auth.currentUser?.id==user)
    setState((){loading=false;error='Could not open plan.';});
  }
 }
 Future<void> change(Future<void> Function() task)async{
  if(busy)return;
  setState((){busy=true;error=null;});
  try{await task();await load();}
  on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Could not save change.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> editPlan()async{
  final p=plan;if(p==null)return;
  final done=await Navigator.of(context).push<bool>(MaterialPageRoute(
    builder:(_)=>OccasionEditor(spaceId:p['space_id']?.toString()??'',existing:p)));
  if(done==true&&mounted)await load();
 }
 Future<void> setCancelled(bool cancel)async{
  await change(()async{
   // Reopening hands the status back to the automatic rules.
   await db.from('occasion_plans').update({'status':cancel?'cancelled':'planning'}).eq('id',widget.id);
  });
 }
 Future<void> setArchived()async{
  final p=plan;if(p==null)return;
  if(p['archived_at']==null){
   final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
    title:Text(tt('Remove this occasion?')),
    content:Text(tt('It moves to Removed. You can restore it from the filter anytime.')),
    actions:[
     TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(tt('Cancel'))),
     FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(tt('Remove'))),
    ]));
   if(ok!=true)return;
  }
  await change(()async{
   await db.from('occasion_plans').update({
    'archived_at':p['archived_at']==null?DateTime.now().toUtc().toIso8601String():null,
   }).eq('id',widget.id);
  });
 }

 /// The date, the countdown and when preparation starts, in one card.
 Widget dateCard(Map<String,dynamic> p,DateTime? upcoming){
  final theme=Theme.of(context),colors=theme.colorScheme;
  final loc=MaterialLocalizations.of(context);
  final on=DateTime.parse(p['occasion_on'].toString());
  final days=OccasionRules.daysUntil(upcoming,DateTime.now());
  final prepStart=OccasionRules.prepStart(upcoming,(p['prep_lead_days'] as num?)?.toInt()??14);
  return Container(padding:const EdgeInsets.all(16),
   decoration:BoxDecoration(borderRadius:BorderRadius.circular(20),
    color:colors.tertiaryContainer.withValues(alpha:.6),
    border:Border.all(color:colors.tertiary.withValues(alpha:.3))),
   child:Row(children:[
    Container(width:86,padding:const EdgeInsets.symmetric(vertical:10),
     decoration:BoxDecoration(color:colors.surface,borderRadius:BorderRadius.circular(16)),
     child:Column(children:[
      Text(days==null?'—':days.toString(),style:theme.textTheme.headlineMedium?.copyWith(
       fontWeight:FontWeight.w800,color:colors.tertiary)),
      Text(tt(days==1?'day':'days'),style:theme.textTheme.labelMedium),
     ])),
    const SizedBox(width:14),
    Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     Text(loc.formatFullDate(upcoming??on),style:theme.textTheme.titleMedium),
     Text(tt(upcoming==null?'This occasion has passed':OccasionRules.countdown(upcoming,DateTime.now())),
      style:theme.textTheme.bodySmall),
     if(prepStart!=null)...[
      const SizedBox(height:8),
      Row(children:[
       Icon(prepReminder?Icons.notifications_active_outlined:Icons.flag_outlined,size:18,color:colors.tertiary),
       const SizedBox(width:6),
       Expanded(child:Text(tt('Start preparing ')+loc.formatMediumDate(prepStart)+
        (prepReminder?tt(' · reminder set'):''),style:theme.textTheme.bodyMedium)),
      ]),
     ],
    ])),
   ]));
 }

 @override Widget build(BuildContext context){
  final p=plan;
  final upcoming=p==null?null:OccasionRules.nextDate(
   original:DateTime.parse(p['occasion_on'].toString()),
   annual:p['annual']==true,today:DateTime.now());
  final status=(p?['status']??'planning').toString();
  return Scaffold(appBar:AppBar(title:Text(tt('Occasion')),actions:[
    if(p!=null)ItemMenu(kind:'occasion',recordId:widget.id,title:p['title']?.toString(),
     statusActions:[
      if(p['archived_at']==null&&status!='cancelled'&&status!='celebrated')
       ItemMenuAction(tt('Cancel occasion'),MenuIcons.cancel,()=>setCancelled(true)),
      if(p['archived_at']==null&&status=='cancelled')
       ItemMenuAction(tt('Reopen'),MenuIcons.reopen,()=>setCancelled(false)),
     ],
     onOpen:editPlan,
     moreActions:[
      if((OneSpaceEnv.isProduction||p['private_space_id']==null)&&
         p['space_id']!=null&&p['archived_at']==null)
       ItemMenuAction('Add to counters',Icons.hourglass_bottom_outlined,
       ()=>CounterSourceActions.open(context,p['space_id'].toString(),CounterSource.occasion(p))),
      if(p['space_id']!=null)ItemMenuAction(tt('Create from this'),MenuIcons.createFrom,
       ()=>createFromThis(context,kind:LinkKind.occasion,id:widget.id,
        spaceId:p['space_id'].toString(),title:p['title'].toString(),
        date:DateTime.tryParse(p['occasion_on']?.toString()??''),
        shared:p['visibility']!='private',onLinked:()=>_links.currentState?.reload())),
     ],
     removed:p['archived_at']!=null,onRemove:busy?null:setArchived),
   ]),
   body:loading?const Center(child:CircularProgressIndicator()):
    p==null?Center(child:Text(tt(error??'Not available'))):RefreshIndicator(
    onRefresh:load,child:ListView(
     physics:const AlwaysScrollableScrollPhysics(),
     padding:const EdgeInsetsDirectional.fromSTEB(16,12,16,35),children:[
     Text(tt(p['title'].toString()),style:Theme.of(context).textTheme.headlineSmall),
     if(OneSpaceEnv.isProduction||p['private_space_id']==null)
      LinkedItemsStrip(key:_links,kind:LinkKind.occasion,id:widget.id),
     Text(tt([
      occasionKinds[p['kind']]??'Occasion',
      if((p['honoree_name']??'').toString().isNotEmpty)p['honoree_name'].toString(),
      p['visibility']=='private'?'Only me':'Both of us',
      occasionStages[status]??'Planning',
     ].map(tt).join(' · ')),style:Theme.of(context).textTheme.bodyMedium),
     if((p['notes']??'').toString().isNotEmpty)Card(elevation:0,margin:const EdgeInsets.only(top:10),
      child:Padding(padding:const EdgeInsets.all(14),child:Column(
       crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
         Icon(Icons.lightbulb_outline,size:18,color:Theme.of(context).colorScheme.primary),
         const SizedBox(width:6),
         Text(tt('First ideas'),style:Theme.of(context).textTheme.titleSmall),
        ]),
        const SizedBox(height:6),
        SelectableText(p['notes'].toString()),
       ]))),
     const SizedBox(height:12),
     dateCard(p,upcoming),
     const SizedBox(height:14),
     OccasionBudgetWorkspace(plan:p,onEditPlan:editPlan),
     if(error!=null)Padding(padding:const EdgeInsets.only(top:10),
      child:Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error))),
   ])));
 }
}
