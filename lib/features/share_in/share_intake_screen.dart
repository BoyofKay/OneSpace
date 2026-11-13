import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../coordinate/activity_detail_screen.dart';
import '../connect/shared_experiences_screen.dart';
import 'share_intake_rules.dart';

enum SaveDestination{newActivity,existingActivity,sharedExperience}

/// Deliberate intake: an Android Share action does not publish anything until
/// the user confirms destination, visibility and saved content.
class ShareIntakeScreen extends StatefulWidget{
 const ShareIntakeScreen({super.key,this.shared});
 final IncomingShare? shared;
 @override State<ShareIntakeScreen> createState()=>_ShareIntakeScreenState();
}
class _ShareIntakeScreenState extends State<ShareIntakeScreen>{
 final db=Supabase.instance.client;
 late final TextEditingController title,url,notes,price,currency,specs;
 String? spaceId,error,selectedActivity;
 bool loading=true,saving=false,onlyMe=true,asComparisonOption=false;
 SaveDestination destination=SaveDestination.newActivity;
 String category='other';
 List<Map<String,dynamic>> activities=[];

 @override void initState(){
  super.initState();
  final content=widget.shared;
  title=TextEditingController(text:content?.title??'');
  url=TextEditingController(text:content?.link??'');
  notes=TextEditingController(text:content?.note??'');
  price=TextEditingController();currency=TextEditingController(text:'USD');
  specs=TextEditingController();
  load();
 }
 @override void dispose(){
  for(final c in [title,url,notes,price,currency,specs]){c.dispose();}
  super.dispose();
 }
 Future<void> load()async{
  try{
   final id=await CurrentSpaceCache.instance.get();
   if(id==null){
    if(mounted)setState((){loading=false;error='Connect a shared space first.';});
    return;
   }
   if(mounted)setState(()=>spaceId=id);
   final rows=await db.from('activities').select('id,title,visibility,archived_at')
    .eq('space_id',id).isFilter('archived_at',null)
    .order('updated_at',ascending:false).limit(100);
   if(!mounted)return;
   setState((){
    spaceId=id;activities=List<Map<String,dynamic>>.from(rows);loading=false;
    selectedActivity=activities.isEmpty?null:activities.first['id'].toString();
   });
  }catch(_){
   if(mounted)setState((){
    loading=false;error='Could not load Activities. You can still create a new one.';
   });
  }
 }
 Future<void> save()async{
  if(saving||spaceId==null)return;
  final name=title.text.trim(),link=url.text.trim(),body=notes.text.trim();
  if(name.isEmpty){setState(()=>error='Add a title.');return;}
  if(link.isNotEmpty&&!ShareIntakeRules.isWebLink(link)){
   setState(()=>error='Only http or https links can be saved.');return;
  }
  if(link.isEmpty&&body.isEmpty){
   setState(()=>error='Add a link or note first.');return;
  }
  if(asComparisonOption&&destination!=SaveDestination.sharedExperience&&link.isNotEmpty){
   final amount=price.text.trim().isEmpty?null:double.tryParse(price.text.trim());
   if(price.text.trim().isNotEmpty&&(amount==null||amount<0||amount>9999999999)){
    setState(()=>error='Enter a valid nonnegative price or leave it blank.');return;
   }
   if(!RegExp(r'^[A-Z]{3}$').hasMatch(currency.text.trim().toUpperCase())){
    setState(()=>error='Use a three-letter currency such as USD or SAR.');return;
   }
  }
  if(destination==SaveDestination.existingActivity&&selectedActivity==null){
   setState(()=>error='Select an Activity to attach the link to.');return;
  }
  setState((){saving=true;error=null;});
  String? activityId,experienceId;
  bool linkComponentFailed=false;
  try{
   if(destination==SaveDestination.sharedExperience){
    final created=await db.from('shared_experiences').insert({
     'space_id':spaceId,
     'category':category,'title':name,'description':body,
     'source_url':link,
    }).select('id').single();
    experienceId=created['id'].toString();
   }else{
    if(destination==SaveDestination.newActivity){
     final created=await db.from('activities').insert({
      'space_id':spaceId,'title':name,
      // Leave the original link in the body as a recovery copy if a
      // component write fails after creating the parent.
      'body':body+(link.isEmpty?'':(body.isEmpty?'':'\n\n')+link),
      'visibility':onlyMe?'private':'shared',
     }).select('id').single();
     activityId=created['id'].toString();
    }else{
     activityId=selectedActivity!;
    }
    if(link.isNotEmpty){
     try{
      await db.from('activity_components').insert({
       'activity_id':activityId,'kind':asComparisonOption?'option':'link','label':name,
       'payload':asComparisonOption?{
        'value':link,'url':link,'note':body,'price':price.text.trim(),
        'currency':currency.text.trim().toUpperCase(),
        'specs':specs.text.trim(),'state':'considering',
       }:{'value':link,'note':body},
      });
     }catch(_){
      if(destination==SaveDestination.existingActivity)rethrow;
      linkComponentFailed=true;
     }
    }else if(destination==SaveDestination.existingActivity&&body.isNotEmpty){
     await db.from('activity_components').insert({
      'activity_id':activityId,'kind':'note','label':name,
      'payload':{'value':body},
     });
    }
   }
   if(!mounted)return;
   if(linkComponentFailed)ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content:Text('Activity saved. Link kept in its description; retry adding it as a component.')));
   final target=experienceId==null?
      ActivityScreen(id:activityId!):
      SharedExperiencesScreen(initialExperienceId:experienceId);
   Navigator.of(context).pushReplacement<void,void>(
     MaterialPageRoute<void>(builder:(_)=>target));
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){
   if(mounted)setState(()=>error='Could not save. Nothing was silently shared; please try again.');
  }finally{
   if(mounted)setState(()=>saving=false);
  }
 }

 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:const Text('Save to OneSpace')),
  body:ListView(padding:const EdgeInsets.fromLTRB(16,16,16,40),children:[
   Text('Make this part of our life',
     style:Theme.of(context).textTheme.titleLarge),
   const SizedBox(height:4),
   const Text('Choose where to keep this link or idea. Nothing is sent to your partner until you save.'),
   const SizedBox(height:18),
   TextField(controller:title,maxLength:120,
    decoration:const InputDecoration(labelText:'Title',border:OutlineInputBorder())),
   const SizedBox(height:8),
   TextField(controller:url,maxLength:1800,keyboardType:TextInputType.url,
    onChanged:(_)=>setState((){}),
    decoration:const InputDecoration(labelText:'Web link (optional)',border:OutlineInputBorder())),
   const SizedBox(height:8),
   TextField(controller:notes,maxLength:5000,minLines:3,maxLines:6,
    decoration:const InputDecoration(labelText:'Thoughts, details or questions',
     border:OutlineInputBorder())),
   const SizedBox(height:12),
   Text('Save as',style:Theme.of(context).textTheme.titleMedium),
   RadioListTile<SaveDestination>(
    value:SaveDestination.newActivity,
    groupValue:destination,title:const Text('New Activity'),
    subtitle:const Text('Explore, compare, discuss and decide together.'),
    onChanged:(v)=>setState(()=>destination=v??destination)),
   RadioListTile<SaveDestination>(
    value:SaveDestination.existingActivity,
    groupValue:destination,title:const Text('Attach to an existing Activity'),
    subtitle:const Text('Add this link or note to an ongoing discussion.'),
    onChanged:activities.isEmpty?null:(v)=>setState(()=>destination=v??destination)),
   RadioListTile<SaveDestination>(
    value:SaveDestination.sharedExperience,
    groupValue:destination,title:const Text('Shared Experience'),
    subtitle:const Text('Recommend music, a film, a game, or something to enjoy together.'),
    onChanged:(v)=>setState(()=>destination=v??destination)),
   if(destination!=SaveDestination.sharedExperience&&url.text.trim().isNotEmpty)...[
    SwitchListTile(contentPadding:EdgeInsets.zero,
     value:asComparisonOption,onChanged:(v)=>setState(()=>asComparisonOption=v),
     title:const Text('Compare this option'),
     subtitle:const Text('Keep price, specifications and opinions alongside competing options.')),
    if(asComparisonOption)...[
     Row(children:[
      Expanded(flex:2,child:TextField(controller:price,
       keyboardType:const TextInputType.numberWithOptions(decimal:true),
       decoration:const InputDecoration(labelText:'Price (optional)',border:OutlineInputBorder()))),
      const SizedBox(width:10),
      Expanded(child:TextField(controller:currency,maxLength:3,
       textCapitalization:TextCapitalization.characters,
       decoration:const InputDecoration(labelText:'Currency',border:OutlineInputBorder()))),
     ]),
     const SizedBox(height:8),
     TextField(controller:specs,maxLength:2500,minLines:2,maxLines:4,
      decoration:const InputDecoration(labelText:'Specifications or pros/cons',border:OutlineInputBorder())),
    ],
   ],
   if(destination==SaveDestination.newActivity)
    SwitchListTile(contentPadding:EdgeInsets.zero,
     value:onlyMe,onChanged:(v)=>setState(()=>onlyMe=v),
     title:const Text('Only me'),
     subtitle:Text(onlyMe?'This Activity remains private.':'Both partners can see and edit this Activity.')),
   if(destination==SaveDestination.existingActivity)...[
    if(loading)const LinearProgressIndicator(),
    if(activities.isEmpty)const Text('There are no existing Activities. Create a new one instead.')
    else DropdownButtonFormField<String>(
     initialValue:selectedActivity,
     decoration:const InputDecoration(labelText:'Choose Activity',border:OutlineInputBorder()),
     isExpanded:true,
     items:[for(final a in activities)DropdownMenuItem(
      value:a['id'].toString(),
      child:Text(a['title'].toString()+
       (a['visibility']=='private'?' · Only me':' · Both of us'),
       overflow:TextOverflow.ellipsis))],
     onChanged:(v)=>setState(()=>selectedActivity=v)),
    const Text('This follows the selected Activity’s existing privacy setting.'),
   ],
   if(destination==SaveDestination.sharedExperience)...[
    DropdownButtonFormField<String>(initialValue:category,
     decoration:const InputDecoration(labelText:'Experience type',border:OutlineInputBorder()),
     items:[for(final e in experienceTypes.entries)
      DropdownMenuItem(value:e.key,child:Text(e.value))],
     onChanged:(v)=>setState(()=>category=v??category)),
    const Padding(padding:EdgeInsets.only(top:8),
     child:Text('Shared Experiences are visible to both partners.')),
   ],
   if(error!=null)Padding(padding:const EdgeInsets.all(6),
    child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
   const SizedBox(height:14),
   FilledButton.icon(onPressed:saving||spaceId==null?null:save,
    icon:const Icon(Icons.save_outlined),
    label:Text(saving?'Saving…':'Save to OneSpace')),
  ]));
}
