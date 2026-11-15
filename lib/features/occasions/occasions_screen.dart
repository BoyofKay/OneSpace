import '../../core/form_kit.dart';
import '../../core/item_menu.dart';
import '../../core/editor_scaffold.dart';
import '../../core/status_look.dart';
import '../../core/linked_items.dart';
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/current_space_cache.dart';
import '../../core/record_collection_search_rules.dart';
import '../../core/record_list_top_actions.dart';
import '../calendar/calendar_rules.dart';
import 'occasion_rules.dart';
import '../mentions/partner_mention_button.dart';
import 'occasion_budget_workspace.dart';
import 'occasion_preparation_reminders.dart';
import '../notes/related_notes_panel.dart';
import '../../core/responsive_field_pair.dart';
import 'package:onespace/l10n/phrases.dart';

const occasionKinds=<String,String>{
 'birthday':'Birthday','anniversary':'Anniversary',
 'holiday':'Holiday','celebration':'Celebration','other':'Other'};
const occasionStages=<String,String>{
 'planning':'Planning','preparing':'Preparing','ready':'Ready',
 'celebrated':'Celebrated','cancelled':'Cancelled'};

class OccasionsScreen extends StatefulWidget{
 const OccasionsScreen({super.key,this.initialPlanId});
 final String? initialPlanId;
 @override State<OccasionsScreen> createState()=>_OccasionsScreenState();
}
class _OccasionsScreenState extends State<OccasionsScreen>{
 final db=Supabase.instance.client;
 String? space,error;
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
   final id=await CurrentSpaceCache.instance.get();
   if(!mounted||request!=_loadVersion||db.auth.currentUser?.id!=user)return;
   if(id==null){
    setState((){loading=false;space=null;plans=[];error=null;});
    final prior=_channel;
    if(prior!=null)unawaited(db.removeChannel(prior));
    _channel=null;_watchedSpace=null;
    return;
   }
   final rows=await db.from('occasion_plans').select().eq('space_id',id)
     .order('updated_at',ascending:false).limit(200);
   if(!mounted||request!=_loadVersion||db.auth.currentUser?.id!=user)return;
   setState((){
    space=id;plans=List<Map<String,dynamic>>.from(rows);
    loading=false;error=null;
   });
   _watch(id);
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
  if(space==null)return;
  final saved=await Navigator.of(context).push<bool>(MaterialPageRoute(
   builder:(_)=>OccasionEditor(spaceId:space!,existing:plan)));
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
   floatingActionButton:space==null?null:FloatingActionButton.extended(heroTag:'fab-occasions',
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
    else if(space==null)Text(tt('Connect your shared space first.'))
    else if(shown.isEmpty)Card(child:Padding(padding:EdgeInsets.all(20),
     child:Text(tt('Nothing planned here yet. Start with an upcoming birthday, anniversary or holiday.'))))
    else for(final p in shown)Card(elevation:0,child:ListTile(
     leading:CircleAvatar(child:StatusLook.mark(p['status']?.toString())??Icon(p['visibility']=='private'?
      Icons.lock_outline:Icons.card_giftcard_outlined)),
     title:Text(tt(p['title'].toString()),style:StatusLook.title(context,p['status']?.toString(),
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
      removed:p['archived_at']!=null,onChanged:load),
     onTap:()=>open(p))),
   ])));
 }
}

class OccasionEditor extends StatefulWidget{
 const OccasionEditor({super.key,required this.spaceId,this.existing,this.initialDate,this.initialKind});
 final String spaceId;
 final Map<String,dynamic>? existing;
 final DateTime? initialDate;
 final String? initialKind;
 @override State<OccasionEditor> createState()=>_OccasionEditorState();
}
class _OccasionEditorState extends State<OccasionEditor> with FormChangeTracker<OccasionEditor>{
 /// R55: current form values; Save turns on only when they change.
 @override String get signature=>[title.text,notes.text,prep.text,saving.text,budget.text,currency.text,honoree.text,kind,status,visibility,date,annual].join('|');

 final db=Supabase.instance.client;
 late final TextEditingController title,notes,prep,saving,budget,currency,honoree;
 late String kind,status,visibility;
 late DateTime date;
 bool annual=true,busy=false;
 String? error;
 @override void initState(){
  super.initState();
  final p=widget.existing??{};
  title=TextEditingController(text:(p['title']??'').toString());
  honoree=TextEditingController(text:(p['honoree_name']??'').toString());
  notes=TextEditingController(text:(p['notes']??'').toString());
  prep=TextEditingController(text:(p['prep_lead_days']??30).toString());
  saving=TextEditingController(text:(p['saving_lead_days']??60).toString());
  budget=TextEditingController(text:(p['budget']??'').toString());
  currency=TextEditingController(text:(p['currency']??'USD').toString());
  date=DateTime.tryParse((p['occasion_on']??'').toString())??widget.initialDate??DateTime.now();
  kind=(p['kind']??widget.initialKind??'birthday').toString();
  status=(p['status']??'planning').toString();
  visibility=(p['visibility']??'private').toString();
  annual=p['annual']!=false;
 }
 @override void dispose(){
  for(final c in [title,notes,prep,saving,budget,currency,honoree]){c.dispose();}
  super.dispose();
 }
 Future<void> chooseDate()async{
  final d=await showDatePicker(context:context,
   initialDate:date,firstDate:DateTime(1900),lastDate:DateTime(2100));
  if(d!=null&&mounted)setState(()=>date=d);
 }
 Future<void> save()async{
  if(busy)return;
  final preparation=int.tryParse(prep.text.trim());
  final funds=int.tryParse(saving.text.trim());
  final money=budget.text.trim().isEmpty?null:double.tryParse(budget.text.trim());
  final code=currency.text.trim().toUpperCase();
  if(title.text.trim().isEmpty){setState(()=>error='Add an occasion name.');return;}
  if(preparation==null||preparation<0||preparation>365||
     funds==null||funds<0||funds>365){
   setState(()=>error='Lead times must be between 0 and 365 days.');return;
  }
  if(budget.text.trim().isNotEmpty&&(money==null||money<0||money>9999999999)){
   setState(()=>error='Enter a valid nonnegative budget.');return;
  }
  if(!RegExp(r'^[A-Z]{3}$').hasMatch(code)){
   setState(()=>error='Use a three-letter currency code.');return;
  }
  setState((){busy=true;error=null;});
  try{
   final values=<String,dynamic>{
    'title':title.text.trim(),'kind':kind,'status':status,
    'honoree_name':honoree.text.trim(),
    'occasion_on':CalendarRules.sqlDate(date),'annual':annual,
    'prep_lead_days':preparation,'saving_lead_days':funds,
    'budget':money,'currency':code,'notes':notes.text.trim(),
   };
   if(widget.existing==null){
    await db.from('occasion_plans').insert({
     ...values,'space_id':widget.spaceId,'visibility':visibility});
   }else{
    await db.from('occasion_plans').update(values).eq('id',widget.existing!['id']);
   }
   if(mounted)Navigator.pop(context,true);
  }on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Unable to save occasion.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context){
  final editing=widget.existing!=null;
  final stages={for(final e in occasionStages.entries)
   if(!['celebrated','cancelled'].contains(e.key)||e.key==status)e.key:e.value};
  return EditorScaffold(title:editing?tt('Edit occasion'):tt('Add occasion'),
   isNew:!editing,isChanged:()=>changed,isComplete:()=>title.text.trim().isNotEmpty,
   listenTo:[title,notes,prep,saving,budget,currency,honoree],saving:busy,onSave:save,
   meta:MetaStrip(value:MetaValues(shared:visibility=='shared'),showBelongs:false,showDate:false,
    enabled:!editing,onChanged:(v)=>setState(()=>visibility=v.shared?'shared':'private')),
   body:ListView(padding:const EdgeInsets.all(18),children:[
   ChoiceRow<String>(label:tt('Type'),options:occasionKinds,selected:kind,
    icons:const {'birthday':Icons.cake_outlined,'anniversary':Icons.favorite_border,
     'holiday':Icons.celebration_outlined,'celebration':Icons.emoji_events_outlined,'other':Icons.star_outline},
    onSelected:(v){if(v!=null)setState(()=>kind=v);}),
   TextField(controller:title,maxLength:160,autofocus:!editing,textCapitalization:TextCapitalization.sentences,
    decoration:InputDecoration(labelText:tt('What are we celebrating? *'),
     hintText:tt('Kay’s birthday, our anniversary…'),border:OutlineInputBorder())),
   const SizedBox(height:10),
   TextField(controller:honoree,maxLength:120,textCapitalization:TextCapitalization.words,
    decoration:InputDecoration(labelText:tt('For whom'),
     prefixIcon:Icon(Icons.person_outline),border:OutlineInputBorder())),
   FormSection(tt('When')),
   DateField(label:tt('Date'),required:true,value:date,first:DateTime(1900),last:DateTime(2100),
    onChanged:(v){if(v!=null)setState(()=>date=v);}),
   Align(alignment:AlignmentDirectional.centerStart,child:OptionChip(label:tt('Every year'),icon:Icons.event_repeat,
    value:annual,onChanged:(v)=>setState(()=>annual=v))),
   const SizedBox(height:14),
   ChoiceRow<String>(label:tt('Progress'),options:stages,selected:status,
    onSelected:(v){if(v!=null)setState(()=>status=v);}),
   FormSection(tt('Getting ready')),
   ResponsiveFieldPair(firstFlex:1,
    first:TextField(controller:prep,keyboardType:TextInputType.number,
     decoration:InputDecoration(labelText:tt('Start preparing (days before)'),border:OutlineInputBorder())),
    second:TextField(controller:saving,keyboardType:TextInputType.number,
     decoration:InputDecoration(labelText:tt('Start saving (days before)'),border:OutlineInputBorder())),
   ),
   const SizedBox(height:12),
   ResponsiveFieldPair(
    first:TextField(controller:budget,
     keyboardType:const TextInputType.numberWithOptions(decimal:true),
     decoration:InputDecoration(labelText:tt('Budget'),border:OutlineInputBorder())),
    second:TextField(controller:currency,maxLength:3,
     textCapitalization:TextCapitalization.characters,
     decoration:InputDecoration(labelText:tt('Currency'),border:OutlineInputBorder())),
   ),
   const SizedBox(height:12),
   TextField(controller:notes,maxLength:5000,minLines:3,maxLines:6,
    decoration:InputDecoration(labelText:tt('Gift ideas, plans or wishes'),
     alignLabelWithHint:true,border:OutlineInputBorder())),
   if(visibility=='shared')Align(alignment:AlignmentDirectional.centerStart,
    child:PartnerMentionButton(spaceId:widget.spaceId,controller:notes,enabled:true)),
   Text(tt(editing?'Who can see it stays as it was created, to protect surprises.'
    :'Tip: keep surprises Only me.'),style:Theme.of(context).textTheme.bodySmall),
   if(error!=null)Padding(padding:const EdgeInsets.only(top:10),
    child:Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error))),
  ]));
 }
}

class OccasionStepEditor extends StatefulWidget{
 const OccasionStepEditor({super.key,required this.planId,this.existing});
 final String planId;
 final Map<String,dynamic>? existing;
 @override State<OccasionStepEditor> createState()=>_OccasionStepEditorState();
}
class _OccasionStepEditorState extends State<OccasionStepEditor> with FormChangeTracker<OccasionStepEditor>{
 /// R55: current form values; Save turns on only when they change.
 @override String get signature=>[title.text,cost.text,currency.text,due,done].join('|');

 final db=Supabase.instance.client;
 late final TextEditingController title,cost,currency;
 DateTime? due;
 bool busy=false,done=false;
 String? error;
 @override void initState(){super.initState();
  final p=widget.existing??{};
  title=TextEditingController(text:(p['title']??'').toString());
  cost=TextEditingController(text:(p['estimated_cost']??'').toString());
  currency=TextEditingController(text:(p['currency']??'USD').toString());
  due=DateTime.tryParse((p['due_on']??'').toString());done=p['done']==true;
 }
 @override void dispose(){title.dispose();cost.dispose();currency.dispose();super.dispose();}
 Future<void> choose()async{
  final d=await showDatePicker(context:context,initialDate:due??DateTime.now(),
    firstDate:DateTime(2000),lastDate:DateTime(2100));
  if(d!=null&&mounted)setState(()=>due=d);
 }
 Future<void> save()async{
  if(busy)return;
  final amount=cost.text.trim().isEmpty?null:double.tryParse(cost.text.trim());
  final code=currency.text.trim().toUpperCase();
  if(title.text.trim().isEmpty){setState(()=>error='Add a step title.');return;}
  if(cost.text.trim().isNotEmpty&&(amount==null||amount<0||amount>9999999999)){
   setState(()=>error='Enter a valid estimate or leave it blank.');return;
  }
  if(!RegExp(r'^[A-Z]{3}$').hasMatch(code)){
   setState(()=>error='Use a three-letter currency.');return;
  }
  setState((){busy=true;error=null;});
  try{
   final values=<String,dynamic>{
    'title':title.text.trim(),'due_on':due==null?null:CalendarRules.sqlDate(due!),
    'estimated_cost':amount,'currency':code,'done':done};
   if(widget.existing==null){
    await db.from('occasion_plan_steps').insert({...values,'plan_id':widget.planId});
   }else{
    await db.from('occasion_plan_steps').update(values).eq('id',widget.existing!['id']);
   }
   if(mounted)Navigator.pop(context,true);
  }on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
   catch(_){if(mounted)setState(()=>error='Could not save step.');}
   finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context)=>EditorScaffold(title:widget.existing==null?tt('Add preparation step'):tt('Edit preparation step'),
   isNew:widget.existing==null,isChanged:()=>changed,isComplete:()=>title.text.trim().isNotEmpty,
   listenTo:[title,cost,currency],saving:busy,onSave:save,
   meta:MetaStrip(value:MetaValues(date:due),showVisibility:false,showBelongs:false,dateLabel:tt('Due date'),
    onChanged:(v)=>setState(()=>due=v.date)),
   body:ListView(padding:const EdgeInsets.all(18),children:[
   TextField(controller:title,maxLength:200,autofocus:widget.existing==null,
    textCapitalization:TextCapitalization.sentences,
    decoration:InputDecoration(labelText:tt('What needs to happen? *'),
     hintText:tt('Book the restaurant, order the cake…'),border:OutlineInputBorder())),
   const SizedBox(height:6),
   ResponsiveFieldPair(
    first:TextField(controller:cost,
     keyboardType:const TextInputType.numberWithOptions(decimal:true),
     decoration:InputDecoration(labelText:tt('Estimated cost'),border:OutlineInputBorder())),
    second:TextField(controller:currency,maxLength:3,
     textCapitalization:TextCapitalization.characters,
     decoration:InputDecoration(labelText:tt('Currency'),border:OutlineInputBorder())),
   ),
   const SizedBox(height:6),
   Align(alignment:AlignmentDirectional.centerStart,child:OptionChip(label:tt('Done'),icon:Icons.task_alt,value:done,
    onChanged:(v)=>setState(()=>done=v))),
   if(error!=null)Padding(padding:const EdgeInsets.only(top:10),
    child:Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error))),
  ]));
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
 List<Map<String,dynamic>> steps=[],history=[];
 bool loading=true,busy=false,showRemoved=false,showHistory=false;
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
   .onPostgresChanges(event:PostgresChangeEvent.all,schema:'public',
    table:'occasion_plan_steps',filter:PostgresChangeFilter(
     type:PostgresChangeFilterType.eq,column:'plan_id',value:widget.id),
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
   var failures=0;
   Future<dynamic> safe(dynamic task)async{
    try{return await task;}catch(_){failures++;return null;}
   }
   final other=await Future.wait([
    safe(db.from('occasion_plan_steps').select().eq('plan_id',widget.id)
     .order('due_on',ascending:true).limit(200)),
    safe(db.from('occasion_plan_revisions').select('record_kind,changed_by,changed_at')
     .eq('plan_id',widget.id).order('changed_at',ascending:false).limit(60)),
   ]);
   if(!mounted||request!=_loadVersion||db.auth.currentUser?.id!=user)return;
   setState((){
    plan=p;
    if(other[0]!=null)steps=List<Map<String,dynamic>>.from(other[0]);
    if(other[1]!=null)history=List<Map<String,dynamic>>.from(other[1]);
    loading=false;
    error=failures==0?null:
      'Some occasion details could not refresh. Existing information is kept; pull down to retry.';
   });
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
    builder:(_)=>OccasionEditor(spaceId:p['space_id'].toString(),existing:p)));
  if(done==true&&mounted)await load();
 }
 Future<void> editStep([Map<String,dynamic>? row])async{
  final done=await Navigator.of(context).push<bool>(MaterialPageRoute(
    builder:(_)=>OccasionStepEditor(planId:widget.id,existing:row)));
  if(done==true&&mounted)await load();
 }
 Future<void> setStage(String stage)async{
  await change(()async{
   await db.from('occasion_plans').update({'status':stage}).eq('id',widget.id);
  });
 }
 Future<void> setArchived()async{
  final p=plan;if(p==null)return;
  await change(()async{
   await db.from('occasion_plans').update({
    'archived_at':p['archived_at']==null?DateTime.now().toUtc().toIso8601String():null,
   }).eq('id',widget.id);
  });
 }
 Future<void> toggleStep(Map<String,dynamic> row)async{
  await change(()async{
   await db.from('occasion_plan_steps').update({'done':row['done']!=true})
    .eq('id',row['id']);
  });
 }
 Future<void> archiveStep(Map<String,dynamic> row)async{
  await change(()async{
   await db.from('occasion_plan_steps').update({
    'archived_at':row['archived_at']==null?DateTime.now().toUtc().toIso8601String():null,
   }).eq('id',row['id']);
  });
 }
 @override Widget build(BuildContext context){
  final p=plan;
  final current=steps.where((s)=>s['archived_at']==null).toList();
  final upcoming=p==null?null:OccasionRules.nextDate(
   original:DateTime.parse(p['occasion_on'].toString()),
   annual:p['annual']==true,today:DateTime.now());
  final total=OccasionRules.estimatedByCurrency(current);
  return Scaffold(appBar:AppBar(title:Text(tt('Occasion plan')),actions:[
    if(p!=null)ItemMenu(kind:'occasion',recordId:widget.id,title:p['title']?.toString(),
     statusActions:[
      if(p['archived_at']==null&&p['status']!='celebrated')
       ItemMenuAction(tt('Mark celebrated'),Icons.celebration_outlined,()=>setStage('celebrated')),
      if(p['archived_at']==null&&(p['status']=='celebrated'||p['status']=='cancelled'))
       ItemMenuAction(tt('Reopen'),Icons.undo,()=>setStage('planning')),
     ],
     onOpen:editPlan,
     moreActions:[
      if(p['space_id']!=null)ItemMenuAction(tt('Create from this'),Icons.add_link,
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
     LinkedItemsStrip(key:_links,kind:LinkKind.occasion,id:widget.id),
     Text(tt((occasionKinds[p['kind']]??'Occasion')+' · '+
      ((p['honoree_name']??'').toString().isNotEmpty?p['honoree_name'].toString()+' · ':'')+
      (p['visibility']=='private'?'Only me':'Both of us')+' · '+
      (occasionStages[p['status']]??'Planning'))),
     const SizedBox(height:9),
     ListTile(leading:const Icon(Icons.event_available_outlined),
      title:Text(tt('Occasion: ')+p['occasion_on'].toString()),
      subtitle:Text(tt(upcoming==null?'Past one-off event':
       OccasionRules.countdown(upcoming,DateTime.now())))),
     if(upcoming!=null)...[
      ListTile(leading:const Icon(Icons.shopping_bag_outlined),
       title:Text(tt('Start preparing')),
       subtitle:Text(tt(CalendarRules.sqlDate(OccasionRules.prepStart(
        upcoming,(p['prep_lead_days'] as num).toInt())!)))),
      ListTile(leading:const Icon(Icons.savings_outlined),
       title:Text(tt('Start setting money aside')),
       subtitle:Text(tt(CalendarRules.sqlDate(OccasionRules.prepStart(
        upcoming,(p['saving_lead_days'] as num).toInt())!)))),
     ],
     const SizedBox(height:14),
     OccasionPreparationReminders(plan:p),
     const SizedBox(height:14),
     RelatedNotesPanel(sourceKind:'occasion',sourceId:widget.id),
     const SizedBox(height:14),
     OccasionBudgetWorkspace(plan:p,onEditPlan:editPlan),
     const SizedBox(height:14),
     if((p['notes']??'').toString().isNotEmpty)
      Card(elevation:0,child:Padding(padding:const EdgeInsets.all(14),
       child:SelectableText(p['notes'].toString()))),
     const Divider(height:26),
     Wrap(spacing:10,runSpacing:6,
      alignment:WrapAlignment.spaceBetween,crossAxisAlignment:WrapCrossAlignment.center,
      children:[
       Text(tt('Preparation (')+current.where((s)=>s['done']==true).length.toString()+
        '/'+current.length.toString()+')',style:Theme.of(context).textTheme.titleLarge),
       TextButton.icon(onPressed:()=>editStep(),icon:const Icon(Icons.add),
        label:Text(tt('Add step'))),
      ]),
     Align(alignment:AlignmentDirectional.centerStart,child:OptionChip(label:tt('Show removed'),icon:Icons.delete_outline,
      value:showRemoved,onChanged:(v)=>setState(()=>showRemoved=v))),
     if(current.isEmpty)Text(tt('Add shopping, reservations, surprises or budget milestones.')),
     for(final step in steps.where((s)=>showRemoved||s['archived_at']==null))
      Card(elevation:0,child:Column(children:[
       CheckboxListTile(value:step['done']==true,
        controlAffinity:ListTileControlAffinity.leading,
        onChanged:step['archived_at']!=null||busy?null:(_)=>toggleStep(step),
        title:Text(tt(step['title'].toString()),style:TextStyle(
          decoration:step['done']==true?TextDecoration.lineThrough:null)),
        subtitle:Text(tt([
         if(step['due_on']!=null)'Due '+step['due_on'].toString(),
         if(step['estimated_cost']!=null)step['currency'].toString()+' '+
            (step['estimated_cost'] as num).toStringAsFixed(2),
         if(step['archived_at']!=null)'Removed',
        ].join(' · ')))),
       Row(mainAxisAlignment:MainAxisAlignment.end,children:[
        TextButton.icon(onPressed:busy?null:()=>editStep(step),
         icon:const Icon(Icons.edit_outlined),label:Text(tt('Edit'))),
        TextButton.icon(onPressed:busy?null:()=>archiveStep(step),
         icon:Icon(step['archived_at']==null?Icons.archive_outlined:Icons.restore_outlined),
         label:Text(tt(step['archived_at']==null?tt('Remove'):tt('Restore')))),
       ]),
      ])),
     if(total.isNotEmpty)...[
      const SizedBox(height:9),
      Text(tt('Estimated spending by currency'),style:Theme.of(context).textTheme.titleMedium),
      for(final c in total.keys.toList()..sort())
       Text(tt(c+' '+total[c]!.toStringAsFixed(2))),
     ],
     const Divider(height:30),
     ListTile(leading:const Icon(Icons.history),
      title:Text(tt('Change history')),
      trailing:Icon(showHistory?Icons.expand_less:Icons.expand_more),
      onTap:()=>setState(()=>showHistory=!showHistory)),
     if(showHistory)...[
      if(history.isEmpty)Text(tt('No changes recorded yet.')),
      for(final row in history)ListTile(dense:true,
       title:Text(tt(row['record_kind'].toString()+' changed by '+
        (row['changed_by']==db.auth.currentUser?.id?'you':'partner'))),
       subtitle:Text(tt(row['changed_at'].toString().replaceFirst('T',' ').split('.').first))),
     ],
     if(error!=null)Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error)),
   ])));
 }
}
