import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/current_space_cache.dart';
import '../calendar/calendar_rules.dart';
import 'occasion_rules.dart';

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
 String filter='upcoming';
 List<Map<String,dynamic>> plans=[];
 @override void initState(){super.initState();load();}
 Future<void> load()async{
  try{
   final id=await CurrentSpaceCache.instance.get();
   if(id==null){if(mounted)setState(()=>loading=false);return;}
   final rows=await db.from('occasion_plans').select().eq('space_id',id)
     .order('updated_at',ascending:false).limit(200);
   if(!mounted)return;
   setState((){
    space=id;plans=List<Map<String,dynamic>>.from(rows);
    loading=false;error=null;
   });
   if(!opened&&widget.initialPlanId!=null){
    opened=true;
    final match=plans.where((p)=>p['id']==widget.initialPlanId).firstOrNull;
    if(match!=null)WidgetsBinding.instance.addPostFrameCallback((_){
     if(mounted)open(match);
    });
   }
  }catch(_){
   if(mounted)setState((){loading=false;error='Unable to load occasion plans.';});
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
 @override Widget build(BuildContext context){
  final today=DateTime.now();
  final shown=plans.where((p){
   if((p['archived_at']!=null)!=archived)return false;
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
   appBar:AppBar(title:const Text('Occasions & surprises'),
    actions:[IconButton(tooltip:'Refresh',onPressed:load,icon:const Icon(Icons.refresh))]),
   floatingActionButton:space==null?null:FloatingActionButton.extended(
    onPressed:()=>edit(),icon:const Icon(Icons.add),label:const Text('Plan an occasion')),
   body:RefreshIndicator(onRefresh:load,child:ListView(
    physics:const AlwaysScrollableScrollPhysics(),
    padding:const EdgeInsets.fromLTRB(16,12,16,90),children:[
    Text('Plan the thoughtful moments',style:Theme.of(context).textTheme.titleLarge),
    const SizedBox(height:6),
    const Text('Remember the day, prepare surprises early, and start saving in time. Private plans stay private.'),
    const SizedBox(height:12),
    Wrap(spacing:6,runSpacing:4,children:[
     for(final e in const {'upcoming':'Upcoming','private':'Only me',
      'shared':'Both of us','all':'All'}.entries)
      FilterChip(label:Text(e.value),selected:filter==e.key,
       onSelected:(_)=>setState(()=>filter=e.key)),
     FilterChip(label:const Text('Archived'),selected:archived,
      onSelected:(v)=>setState(()=>archived=v)),
    ]),
    if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
    if(loading)const Center(child:Padding(padding:EdgeInsets.all(24),child:CircularProgressIndicator()))
    else if(space==null)const Text('Connect your shared space first.')
    else if(shown.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(20),
     child:Text('Nothing planned here yet. Start with an upcoming birthday, anniversary or holiday.')))
    else for(final p in shown)Card(elevation:0,child:ListTile(
     leading:CircleAvatar(child:Icon(p['visibility']=='private'?
      Icons.lock_outline:Icons.card_giftcard_outlined)),
     title:Text(p['title'].toString(),style:Theme.of(context).textTheme.titleMedium),
     subtitle:Text([
      occasionKinds[p['kind']]??'Occasion',
      occasionStages[p['status']]??'Planning',
      if(p['visibility']=='private')'Only me',
      OccasionRules.countdown(OccasionRules.nextDate(
       original:DateTime.parse(p['occasion_on'].toString()),
       annual:p['annual']==true,today:today),today),
     ].join(' · ')),
     trailing:const Icon(Icons.chevron_right),onTap:()=>open(p))),
   ])));
 }
}

class OccasionEditor extends StatefulWidget{
 const OccasionEditor({super.key,required this.spaceId,this.existing});
 final String spaceId;
 final Map<String,dynamic>? existing;
 @override State<OccasionEditor> createState()=>_OccasionEditorState();
}
class _OccasionEditorState extends State<OccasionEditor>{
 final db=Supabase.instance.client;
 late final TextEditingController title,notes,prep,saving,budget,currency;
 late String kind,status,visibility;
 late DateTime date;
 bool annual=true,busy=false;
 String? error;
 @override void initState(){
  super.initState();
  final p=widget.existing??{};
  title=TextEditingController(text:(p['title']??'').toString());
  notes=TextEditingController(text:(p['notes']??'').toString());
  prep=TextEditingController(text:(p['prep_lead_days']??30).toString());
  saving=TextEditingController(text:(p['saving_lead_days']??60).toString());
  budget=TextEditingController(text:(p['budget']??'').toString());
  currency=TextEditingController(text:(p['currency']??'USD').toString());
  date=DateTime.tryParse((p['occasion_on']??'').toString())??DateTime.now();
  kind=(p['kind']??'birthday').toString();
  status=(p['status']??'planning').toString();
  visibility=(p['visibility']??'private').toString();
  annual=p['annual']!=false;
 }
 @override void dispose(){
  for(final c in [title,notes,prep,saving,budget,currency]){c.dispose();}
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
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:Text(widget.existing==null?'Plan an occasion':'Edit occasion')),
  body:ListView(padding:const EdgeInsets.fromLTRB(16,16,16,35),children:[
   TextField(controller:title,maxLength:160,decoration:const InputDecoration(
    labelText:'What are we celebrating?',border:OutlineInputBorder())),
   const SizedBox(height:10),
   DropdownButtonFormField<String>(initialValue:kind,
    decoration:const InputDecoration(labelText:'Occasion type',border:OutlineInputBorder()),
    items:[for(final e in occasionKinds.entries)
     DropdownMenuItem(value:e.key,child:Text(e.value))],
    onChanged:(v)=>setState(()=>kind=v??kind)),
   ListTile(leading:const Icon(Icons.event_outlined),
    title:const Text('Occasion date'),subtitle:Text(CalendarRules.sqlDate(date)),onTap:chooseDate),
   SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Repeat every year'),
    value:annual,onChanged:(v)=>setState(()=>annual=v)),
   DropdownButtonFormField<String>(initialValue:status,
    decoration:const InputDecoration(labelText:'Progress',border:OutlineInputBorder()),
    items:[for(final e in occasionStages.entries)
     DropdownMenuItem(value:e.key,child:Text(e.value))],
    onChanged:(v)=>setState(()=>status=v??status)),
   const SizedBox(height:12),
   Row(children:[
    Expanded(child:TextField(controller:prep,keyboardType:TextInputType.number,
     decoration:const InputDecoration(labelText:'Prepare days ahead',border:OutlineInputBorder()))),
    const SizedBox(width:10),
    Expanded(child:TextField(controller:saving,keyboardType:TextInputType.number,
     decoration:const InputDecoration(labelText:'Start saving days ahead',border:OutlineInputBorder()))),
   ]),
   const SizedBox(height:12),
   Row(children:[
    Expanded(flex:2,child:TextField(controller:budget,
     keyboardType:const TextInputType.numberWithOptions(decimal:true),
     decoration:const InputDecoration(labelText:'Budget (optional)',border:OutlineInputBorder()))),
    const SizedBox(width:10),
    Expanded(child:TextField(controller:currency,maxLength:3,
     textCapitalization:TextCapitalization.characters,
     decoration:const InputDecoration(labelText:'Currency',border:OutlineInputBorder()))),
   ]),
   const SizedBox(height:12),
   TextField(controller:notes,maxLength:5000,minLines:3,maxLines:5,
    decoration:const InputDecoration(labelText:'Gift ideas, plans or wishes',
     border:OutlineInputBorder())),
   if(widget.existing==null)SwitchListTile(
    contentPadding:EdgeInsets.zero,value:visibility=='private',
    title:const Text('Only me'),
    subtitle:const Text('Keep surprises private. Turn off to plan together.'),
    onChanged:(v)=>setState(()=>visibility=v?'private':'shared'))
   else ListTile(leading:Icon(visibility=='private'?Icons.lock_outline:Icons.people_outline),
    title:Text(visibility=='private'?'Only me':'Both of us'),
    subtitle:const Text('Privacy is fixed for this plan to protect surprises.')),
   if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
   FilledButton.icon(onPressed:busy?null:save,icon:const Icon(Icons.save_outlined),
    label:Text(busy?'Saving…':'Save occasion')),
  ]));
}

class OccasionStepEditor extends StatefulWidget{
 const OccasionStepEditor({super.key,required this.planId,this.existing});
 final String planId;
 final Map<String,dynamic>? existing;
 @override State<OccasionStepEditor> createState()=>_OccasionStepEditorState();
}
class _OccasionStepEditorState extends State<OccasionStepEditor>{
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
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:Text(widget.existing==null?'Add preparation step':'Edit preparation step')),
  body:ListView(padding:const EdgeInsets.all(16),children:[
   TextField(controller:title,maxLength:200,
    decoration:const InputDecoration(labelText:'What needs to happen?',border:OutlineInputBorder())),
   ListTile(title:const Text('Due on'),subtitle:Text(due==null?'No deadline':CalendarRules.sqlDate(due!)),
    onTap:choose,trailing:IconButton(tooltip:'Clear date',icon:const Icon(Icons.clear),
     onPressed:()=>setState(()=>due=null))),
   Row(children:[
    Expanded(flex:2,child:TextField(controller:cost,
     keyboardType:const TextInputType.numberWithOptions(decimal:true),
     decoration:const InputDecoration(labelText:'Estimated cost',border:OutlineInputBorder()))),
    const SizedBox(width:10),
    Expanded(child:TextField(controller:currency,maxLength:3,
     textCapitalization:TextCapitalization.characters,
     decoration:const InputDecoration(labelText:'Currency',border:OutlineInputBorder()))),
   ]),
   SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Completed'),
    value:done,onChanged:(v)=>setState(()=>done=v)),
   if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
   FilledButton.icon(onPressed:busy?null:save,icon:const Icon(Icons.save_outlined),
    label:Text(busy?'Saving…':'Save step')),
  ]));
}

class OccasionDetail extends StatefulWidget{
 const OccasionDetail({super.key,required this.id});
 final String id;
 @override State<OccasionDetail> createState()=>_OccasionDetailState();
}
class _OccasionDetailState extends State<OccasionDetail>{
 final db=Supabase.instance.client;
 Map<String,dynamic>? plan;
 List<Map<String,dynamic>> steps=[],history=[];
 bool loading=true,busy=false,showRemoved=false,showHistory=false;
 String? error;
 @override void initState(){super.initState();load();}
 Future<void> load()async{
  try{
   final p=await db.from('occasion_plans').select().eq('id',widget.id).single();
   final other=await Future.wait([
    db.from('occasion_plan_steps').select().eq('plan_id',widget.id)
     .order('due_on',ascending:true).limit(200),
    db.from('occasion_plan_revisions').select('record_kind,changed_by,changed_at')
     .eq('plan_id',widget.id).order('changed_at',ascending:false).limit(60),
   ]);
   if(!mounted)return;
   setState((){
    plan=p;steps=List<Map<String,dynamic>>.from(other[0]);
    history=List<Map<String,dynamic>>.from(other[1]);loading=false;error=null;
   });
  }on PostgrestException catch(e){if(mounted)setState((){loading=false;error=e.message;});}
   catch(_){if(mounted)setState((){loading=false;error='Could not open plan.';});}
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
  return Scaffold(appBar:AppBar(title:const Text('Occasion plan'),actions:[
    if(p!=null)IconButton(tooltip:'Edit occasion',onPressed:editPlan,icon:const Icon(Icons.edit_outlined)),
    if(p!=null)IconButton(tooltip:p['archived_at']==null?'Archive':'Restore',
      onPressed:busy?null:setArchived,icon:Icon(p['archived_at']==null?
       Icons.archive_outlined:Icons.restore_outlined)),
   ]),
   body:loading?const Center(child:CircularProgressIndicator()):
    p==null?Center(child:Text(error??'Not available')):RefreshIndicator(
    onRefresh:load,child:ListView(
     physics:const AlwaysScrollableScrollPhysics(),
     padding:const EdgeInsets.fromLTRB(16,12,16,35),children:[
     Text(p['title'].toString(),style:Theme.of(context).textTheme.headlineSmall),
     Text((occasionKinds[p['kind']]??'Occasion')+' · '+
      (p['visibility']=='private'?'Only me':'Both of us')+' · '+
      (occasionStages[p['status']]??'Planning')),
     const SizedBox(height:9),
     ListTile(leading:const Icon(Icons.event_available_outlined),
      title:Text('Occasion: '+p['occasion_on'].toString()),
      subtitle:Text(upcoming==null?'Past one-off event':
       OccasionRules.countdown(upcoming,DateTime.now()))),
     if(upcoming!=null)...[
      ListTile(leading:const Icon(Icons.shopping_bag_outlined),
       title:const Text('Start preparing'),
       subtitle:Text(CalendarRules.sqlDate(OccasionRules.prepStart(
        upcoming,(p['prep_lead_days'] as num).toInt())!))),
      ListTile(leading:const Icon(Icons.savings_outlined),
       title:const Text('Start setting money aside'),
       subtitle:Text(CalendarRules.sqlDate(OccasionRules.prepStart(
        upcoming,(p['saving_lead_days'] as num).toInt())!))),
     ],
     if(p['budget']!=null)ListTile(leading:const Icon(Icons.account_balance_wallet_outlined),
      title:const Text('Budget'),subtitle:Text(p['currency'].toString()+
       ' '+(p['budget'] as num).toStringAsFixed(2))),
     if((p['notes']??'').toString().isNotEmpty)
      Card(elevation:0,child:Padding(padding:const EdgeInsets.all(14),
       child:SelectableText(p['notes'].toString()))),
     const Divider(height:26),
     Row(children:[
      Expanded(child:Text('Preparation ('+current.where((s)=>s['done']==true).length.toString()+
       '/'+current.length.toString()+')',style:Theme.of(context).textTheme.titleLarge)),
      TextButton.icon(onPressed:()=>editStep(),icon:const Icon(Icons.add),label:const Text('Add step')),
     ]),
     SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Show removed steps'),
      value:showRemoved,onChanged:(v)=>setState(()=>showRemoved=v)),
     if(current.isEmpty)const Text('Add shopping, reservations, surprises or budget milestones.'),
     for(final step in steps.where((s)=>showRemoved||s['archived_at']==null))
      Card(elevation:0,child:Column(children:[
       CheckboxListTile(value:step['done']==true,
        controlAffinity:ListTileControlAffinity.leading,
        onChanged:step['archived_at']!=null||busy?null:(_)=>toggleStep(step),
        title:Text(step['title'].toString(),style:TextStyle(
          decoration:step['done']==true?TextDecoration.lineThrough:null)),
        subtitle:Text([
         if(step['due_on']!=null)'Due '+step['due_on'].toString(),
         if(step['estimated_cost']!=null)step['currency'].toString()+' '+
            (step['estimated_cost'] as num).toStringAsFixed(2),
         if(step['archived_at']!=null)'Removed',
        ].join(' · '))),
       Row(mainAxisAlignment:MainAxisAlignment.end,children:[
        TextButton.icon(onPressed:busy?null:()=>editStep(step),
         icon:const Icon(Icons.edit_outlined),label:const Text('Edit')),
        TextButton.icon(onPressed:busy?null:()=>archiveStep(step),
         icon:Icon(step['archived_at']==null?Icons.archive_outlined:Icons.restore_outlined),
         label:Text(step['archived_at']==null?'Remove':'Restore')),
       ]),
      ])),
     if(total.isNotEmpty)...[
      const SizedBox(height:9),
      Text('Estimated spending by currency',style:Theme.of(context).textTheme.titleMedium),
      for(final c in total.keys.toList()..sort())
       Text(c+' '+total[c]!.toStringAsFixed(2)),
     ],
     const Divider(height:30),
     ListTile(leading:const Icon(Icons.history),
      title:const Text('Change history'),
      trailing:Icon(showHistory?Icons.expand_less:Icons.expand_more),
      onTap:()=>setState(()=>showHistory=!showHistory)),
     if(showHistory)...[
      if(history.isEmpty)const Text('No changes recorded yet.'),
      for(final row in history)ListTile(dense:true,
       title:Text(row['record_kind'].toString()+' changed by '+
        (row['changed_by']==db.auth.currentUser?.id?'you':'partner')),
       subtitle:Text(row['changed_at'].toString().replaceFirst('T',' ').split('.').first)),
     ],
     if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
   ]))));
 }
}
