import '../../core/editor_scaffold.dart';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/current_space_cache.dart';
import 'gesture_experience.dart';
import 'gesture_pool_rules.dart';
import 'love_prompt_rules.dart';

/// Intentionally sent gestures. Messages are explicitly identified as presets;
/// there is no automated impersonation or push-notification claim here.
class PartnerGesturesScreen extends StatefulWidget {
 const PartnerGesturesScreen({super.key,this.manageOnly=false});
 final bool manageOnly;
 @override State<PartnerGesturesScreen> createState()=>_PartnerGesturesScreenState();
}
class _GestureOption {
 const _GestureOption(this.id,this.title,this.icon,this.messages);
 final String id,title;
 final IconData icon;
 final List<String> messages;
}
const _options=[
 _GestureOption('hug','Send a hug',Icons.volunteer_activism_outlined,[
   'Sending you a big, warm hug.',
   'A hug is on its way to you, my love.',
   'Wrapping you in a little extra love today.',
 ]),
 _GestureOption('miss_you','I miss you',Icons.heart_broken_outlined,[
   'I miss you more than words can say.',
   'Wish you were here with me right now.',
   'Across the distance, I am missing you.',
 ]),
 _GestureOption('thinking','Thinking of you',Icons.favorite_outline,[
   'Just wanted you to know I am thinking about you.',
   'You crossed my mind, and I smiled.',
   'No matter the distance, you are in my thoughts.',
 ]),
 _GestureOption('smile','You made me smile',Icons.sentiment_satisfied_alt_outlined,[
   'Thinking about you just made me smile.',
   'You are the brightest part of my day.',
   'A little smile, just because of you.',
 ]),
 _GestureOption('morning','Good morning',Icons.wb_sunny_outlined,[
   'Good morning, my love. I hope your day is kind to you.',
   'Wishing you a gentle and beautiful morning.',
   'A morning kiss and a whole lot of love for you.',
   // The ten original automatic-ritual messages, editable in this pool.
   "Good morning, my love. Wishing you a gentle day.",
   "A warm morning thought for someone very special.",
   "May today bring you a hundred little smiles.",
   "Good morning! Love is cheering you on from afar.",
   "I hope your morning starts with something beautiful.",
   "The day begins with you in my heart.",
   "Sending you sunshine and a little extra courage.",
   "Morning hugs, delivered across the distance.",
   "I hope today brings you peace and happy surprises.",
   "Another day, another reminder that you are loved.",
 ]),
 _GestureOption('goodnight','Sweet dreams',Icons.nightlight_round,[
   'Sweet dreams. I am holding you in my heart.',
   'Goodnight, my love. Rest well.',
   'The day is ending, but my love for you never does.',
   // The ten original automatic-ritual messages, editable in this pool.
   "Sweet dreams. You are loved more than words.",
   "Before sleep, a little reminder you are in my heart.",
   "May tonight bring you rest and beautiful dreams.",
   "Goodnight, my love. Rest your busy mind.",
   "Sending peaceful thoughts as bedtime approaches.",
   "A goodnight hug from miles away.",
   "I hope you fall asleep with a smile.",
   "Rest easy. Tomorrow holds another little beginning.",
   "Wishing you a calm and comforting night.",
   "Goodnight. Thinking of you with so much affection.",
 ]),
 _GestureOption('proud','Proud of you',Icons.auto_awesome_outlined,[
   'I am so proud of you.',
   'I see everything you do, and I appreciate you.',
   'You are amazing. I hope you know that.',
 ]),
 _GestureOption('support','You have got this',Icons.fitness_center_outlined,[
   'I am here for you, even from far away.',
   'You do not have to carry today alone.',
   'You have got this. I believe in you.',
   // The ten original automatic-ritual messages, editable in this pool.
   "Work is behind you. Sending a well-earned hug.",
   "I hope you can enjoy some rest now.",
   "You did enough today. Be gentle with yourself.",
   "I hope the rest of your evening feels peaceful.",
   "Your effort never goes unnoticed. Proud of you.",
   "May your evening be softer than your workday.",
   "Take a moment for yourself. You deserve it.",
   "Thinking of you as your workday winds down.",
   "Here is a little encouragement for the evening.",
   "Sending care and comfort after a busy day.",
 ]),
 _GestureOption('thanks','Thank you',Icons.handshake_outlined,[
   'Thank you for being there for me.',
   'I notice all the little things you do. Thank you, love.',
   'Thank you for making my life warmer.',
 ]),
 _GestureOption('lucky','Lucky to have you',Icons.stars_outlined,[
   'I feel so lucky to have you in my life.',
   'Of all the people in the world, I get to love you.',
   'Being yours is one of my favorite things.',
 ]),
 _GestureOption('miss_together','I miss us together',Icons.people_alt_outlined,[
   'I miss the simple moments when we are side by side.',
   'I miss our laughter and the ordinary magic of us together.',
   'I cannot wait for our next moment together.',
 ]),
 _GestureOption('miss_home','I miss our home',Icons.home_outlined,[
   'I miss the feeling of being home with you.',
   'Home is wherever we get to be together.',
   'Missing our little routines and our place.',
 ]),
 _GestureOption('miss_kids','I miss our kids',Icons.child_care_outlined,[
   'I am missing our kids and all their little moments.',
   'Sending extra love to the little ones today.',
   'I wish I could share this moment with our family.',
 ]),
 _GestureOption('miss_pets','I miss our furry ones',Icons.pets_outlined,[
   'Please give our furry ones an extra cuddle from me.',
   'I miss their little paws and all the chaos they bring.',
   'Thinking of our furry family today.',
 ]),

];

class _PartnerGesturesScreenState extends State<PartnerGesturesScreen> {
 final db=Supabase.instance.client;
 String? spaceId,recipientId,recipientName,sendToLabel;
 String? busyKind,error;
 String? lastSent,lastSentAt;
 bool loading=true;
 List<Map<String,dynamic>> custom=[];
 List<Map<String,dynamic>> overrides=[];

 @override void initState(){super.initState();_load();}
 Future<void> _load() async {
   try{
     final space=await CurrentSpaceCache.instance.get();
     final me=db.auth.currentUser?.id;
     if(space==null||me==null){
       if(mounted){setState(()=>loading=false);}
       return;
     }
     final members=await db.from('space_members').select('user_id')
       .eq('space_id',space);
     final partner=members.where((m)=>m['user_id']!=me).firstOrNull;
     if(!mounted){return;}
     final other=partner?['user_id']?.toString();
     final names=CurrentSpaceCache.instance.memberNamesFor(space);
     final templates=await db.from('gesture_templates').select('id,title,message,kind')
       .eq('space_id',space).eq('creator_id',me).order('created_at',ascending:false);
     final updated=await db.from('gesture_message_overrides')
       .select('kind,message_index,message,disabled')
       .eq('space_id',space).eq('owner_id',me);
     String? latest;
     try{
       final recent=await db.from('partner_gestures').select('created_at')
        .eq('space_id',space).eq('sender_id',me)
        .order('created_at',ascending:false).limit(1);
       if(recent.isNotEmpty)latest=recent.first['created_at']?.toString();
     }catch(_){
       // Sending gestures remains available even if history is offline.
     }
     String? label;
     try{
       final mine=await db.from('profiles').select('partner_label,partner_labels')
        .eq('id',me).maybeSingle();
       final pet=(mine?['partner_labels'] as List?)?.map((x)=>x.toString().trim())
        .where((x)=>x.isNotEmpty).toList()??const <String>[];
       final plain=mine?['partner_label']?.toString().trim()??'';
       // "your love" for an endearment, the name itself for a plain label.
       label=pet.isNotEmpty?'your '+pet.first.replaceFirst(RegExp(r'^(my|your)\s+',caseSensitive:false),'')
        :plain.isNotEmpty?plain:null;
     }catch(_){}
     if(!mounted)return;
     setState((){
       sendToLabel=label;
       lastSentAt=latest;
       spaceId=space;recipientId=other;
       recipientName=other==null?null:(names?[other]??'your partner');
       custom=templates;
       overrides=updated;
       loading=false;
     });
   }catch(_){
     if(mounted){setState((){
       error='Could not load your shared space.';
       loading=false;
     });}
   }
 }
 Color _tint(String kind){
   switch(kind){
     case 'hug':return const Color(0xFFE77992);
     case 'thinking':return const Color(0xFF9977D7);
     case 'smile':return const Color(0xFFE5A440);
     case 'morning':return const Color(0xFFD99242);
     case 'goodnight':return const Color(0xFF7382C7);
     case 'proud':return const Color(0xFF409F8B);
     case 'thanks':return const Color(0xFF218E80);
     case 'lucky':return const Color(0xFF9977D7);
     case 'miss_you':return const Color(0xFFE56D8A);
     case 'miss_together':return const Color(0xFFDC658A);
     case 'miss_home':return const Color(0xFFDC9960);
     case 'miss_kids':return const Color(0xFF729CC8);
     case 'miss_pets':return const Color(0xFFBC804D);
     default:return const Color(0xFF518FB7);
   }
 }
 List<String> pool(_GestureOption option)=>
   GesturePoolRules.activeMessages(
     kind:option.id,builtIn:option.messages,
     overrides:overrides,custom:custom,
   );
 Future<void> editPreset(_GestureOption option,int index) async{
   final old=overrides.where((o)=>o['kind']==option.id&&
      o['message_index']==index).firstOrNull;
   final message=TextEditingController(
     text:old?['message']?.toString()??option.messages[index]);
   var disabled=old?['disabled']==true;
   try{
     final accepted=await showDialog<bool>(context:context,builder:(ctx)=>
       StatefulBuilder(builder:(ctx,update)=>AlertDialog(
         title:Text('Edit '+option.title),
         content:Column(mainAxisSize:MainAxisSize.min,children:[
           TextField(controller:message,maxLength:240,maxLines:4,
             decoration:const InputDecoration(labelText:'Message')),
           SwitchListTile(title:const Text('Hide from random pool'),
             value:disabled,onChanged:(v)=>update(()=>disabled=v)),
         ]),
         actions:[
           TextButton(onPressed:()=>Navigator.pop(ctx,false),
             child:const Text('Cancel')),
           FilledButton(onPressed:()=>Navigator.pop(ctx,true),
             child:const Text('Save')),
         ],
       )));
     if(accepted!=true||spaceId==null)return;
     final me=db.auth.currentUser!.id;
     await db.from('gesture_message_overrides').upsert({
       'space_id':spaceId,'owner_id':me,'kind':option.id,
       'message_index':index,'message':message.text.trim(),
       'disabled':disabled,
     },onConflict:'owner_id,kind,message_index');
     await _load();
   }catch(_){
     if(mounted)ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content:Text('Unable to update gesture message.')));
   }finally{message.dispose();}
 }
 Widget gestureLibrary(){
   return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
     FilledButton.tonalIcon(onPressed:()=>_createCustom(),
       icon:const Icon(Icons.add_reaction_outlined),
       label:const Text('Create my own gesture')),
     const SizedBox(height:12),
     Text('Gesture types · tap to expand',
       style:Theme.of(context).textTheme.titleMedium),
     const SizedBox(height:7),
     for(final option in _options)
       Card(elevation:0,clipBehavior:Clip.antiAlias,
         child:ExpansionTile(
           leading:CircleAvatar(
             backgroundColor:_tint(option.id).withValues(alpha:.16),
             child:GestureKindSymbol(kind:option.id,color:_tint(option.id))),
           title:Text(option.title),
           subtitle:Text(pool(option).length.toString()+' active messages'),
           childrenPadding:const EdgeInsets.fromLTRB(12,2,12,12),
           children:[
             for(var index=0;index<option.messages.length;index++)
               ListTile(
                 dense:true,
                 title:Text(overrides.where((o)=>o['kind']==option.id&&
                   o['message_index']==index).firstOrNull?['message']
                     ?.toString()??option.messages[index]),
                 subtitle:Text(overrides.any((o)=>o['kind']==option.id&&
                   o['message_index']==index&&o['disabled']==true)?
                     'Hidden from pool':'Built-in · editable'),
                 trailing:IconButton(
                   tooltip:'Edit this message',
                   icon:const Icon(Icons.edit_outlined),
                   onPressed:()=>editPreset(option,index)),
               ),
             for(final item in custom.where((row)=>row['kind']==option.id))
               ListTile(
                 dense:true,
                 title:Text(item['message']?.toString()??''),
                 subtitle:const Text('My message'),
                 trailing:Row(mainAxisSize:MainAxisSize.min,children:[
                   IconButton(tooltip:'Edit',icon:const Icon(Icons.edit_outlined),
                     onPressed:()=>_createCustom(item)),
                   IconButton(tooltip:'Remove',icon:const Icon(Icons.delete_outline),
                     onPressed:()=>_deleteCustom(item['id'].toString())),
                 ]),
               ),
           ],
         )),
   ]);
 }

 Future<void> _createCustom([Map<String,dynamic>? original]) async {
   try{
     // R55: a page with Cancel/Save at the bottom, not a pop-up.
     final data=await Navigator.of(context).push<Map<String,String?>>(
       MaterialPageRoute(builder:(_)=>GestureEditorPage(
         original:original,options:{for(final o in _options)o.id:o.title})));
     if(data==null||spaceId==null||recipientId==null)return;
     if(original==null){
       await db.from('gesture_templates').insert({
         'space_id':spaceId,'recipient_id':recipientId,
         'title':data['title'],'message':data['message'],
         'kind':data['kind'],'scheduled_moment':null,
       });
     }else{
       await db.from('gesture_templates').update({
         'title':data['title'],'message':data['message'],
         'kind':data['kind'],'scheduled_moment':null,
       }).eq('id',original['id'].toString())
         .eq('creator_id',db.auth.currentUser!.id);
     }
     await _load();
   }catch(_){
     if(mounted)ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content:Text('Could not save this gesture.')));
   }
 }
 Future<void> _deleteCustom(String id) async {
   final yes=await showDialog<bool>(context:context,builder:(ctx)=>
     AlertDialog(title:const Text('Remove personal gesture?'),
       content:const Text('Sent messages remain in gesture history. '
         'This only removes your reusable template.'),
       actions:[
         TextButton(onPressed:()=>Navigator.pop(ctx,false),
           child:const Text('Keep')),
         FilledButton(onPressed:()=>Navigator.pop(ctx,true),
           child:const Text('Remove')),
       ]));
   if(yes!=true)return;
   try{
     await db.from('gesture_templates').delete().eq('id',id);
     await _load();
   }catch(_){
     if(mounted)ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content:Text('Could not delete gesture.')));
   }
 }

 Future<void> _send(_GestureOption option) async {
   if(busyKind!=null||spaceId==null||recipientId==null){return;}
   final messages=pool(option);
   if(messages.isEmpty){
     if(mounted)ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content:Text('No active messages in this gesture type.')));
     return;
   }
   final random=Random();
   var i=random.nextInt(messages.length);
   if(messages.length>1&&messages[i]==lastSent){
     i=(i+1)%messages.length;
   }
   final message=messages[i];
   setState((){busyKind=option.id;error=null;});
   try{
     await db.from('partner_gestures').insert({
       'space_id':spaceId,'recipient_id':recipientId,
       'kind':option.id,'message':message,
     });
     if(mounted){
       setState((){
        lastSent=message;
        lastSentAt=DateTime.now().toUtc().toIso8601String();
       });
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content:Text('Sent to '+(recipientName??'your partner'))),
       );
     }
   }on PostgrestException catch(e){
     if(mounted){setState(()=>error=e.message);}
   }catch(_){
     if(mounted){setState(()=>error='Could not send this gesture. Please retry.');}
   }finally{
     if(mounted){setState(()=>busyKind=null);}
   }
 }
 @override Widget build(BuildContext context) {
   return Scaffold(
     appBar:AppBar(title:Text(widget.manageOnly?'Love gesture settings':'A little love'),actions:[
       if(!widget.manageOnly)IconButton(tooltip:'Sent and received history',icon:const Icon(Icons.history),
         onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(
           builder:(_)=>const GestureHistoryScreen()))),
     ]),
     body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),
       children:[
         Text(widget.manageOnly?'My gesture library':
           'Small gestures, felt across any distance.',
           style:Theme.of(context).textTheme.titleMedium),
         const SizedBox(height:6),
         Text(widget.manageOnly?'Each gesture type has one randomized message pool. Edit or hide built-in messages and add your own.':
           'Tap a gesture to send it. Manage your gesture library in Settings.'),
         const SizedBox(height:16),
         if(!widget.manageOnly)...[
          FilledButton.tonalIcon(
           onPressed:_createCustom,
           icon:const Icon(Icons.add_reaction_outlined),
           label:const Text('Create my own gesture')),
          if(LovePromptRules.lastSentSummary(lastSentAt,DateTime.now())!=null)
           Padding(padding:const EdgeInsets.only(top:6),
            child:Text(LovePromptRules.lastSentSummary(
             lastSentAt,DateTime.now())!,
             style:Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height:12),
         ],
         if(loading)const Center(child:CircularProgressIndicator()),
         if(!loading&&recipientId==null)
           const Text('Connect your partner to send a gesture.'),
         if(error!=null)Text(error!,
           style:TextStyle(color:Theme.of(context).colorScheme.error)),
         if(recipientId!=null)...[
           if(!widget.manageOnly)Text('Send to '+(sendToLabel??recipientName??'your partner'),
             style:Theme.of(context).textTheme.titleSmall),
           if(!widget.manageOnly)const SizedBox(height:12),
           if(!widget.manageOnly)LayoutBuilder(builder:(ctx,size)=>GridView.builder(
             shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),
             itemCount:_options.length,
             gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(
               crossAxisCount:size.maxWidth>640?3:2,
               childAspectRatio:1.28,crossAxisSpacing:9,mainAxisSpacing:9),
             itemBuilder:(ctx,index){
               final option=_options[index],color=_tint(option.id);
               return Card(
                 elevation:0,clipBehavior:Clip.antiAlias,
                 color:Color.alphaBlend(color.withValues(alpha:.15),
                   Theme.of(context).colorScheme.surface),
                 child:InkWell(
                   onTap:busyKind==null?()=>_send(option):null,
                   child:Padding(padding:const EdgeInsets.all(10),
                     child:Column(mainAxisAlignment:MainAxisAlignment.center,
                       children:[
                         CircleAvatar(radius:24,
                           backgroundColor:color.withValues(alpha:.18),
                           child:GestureKindSymbol(
                             kind:option.id,color:color,size:25)),
                         const SizedBox(height:9),
                         Text(option.title,textAlign:TextAlign.center,
                           maxLines:2,overflow:TextOverflow.ellipsis,
                           style:Theme.of(context).textTheme.titleSmall),

                       ]),
                   ),
                 ),
               );
             },
           )),

           if(widget.manageOnly)gestureLibrary(),

         ],
       ],
     )),
   );
 }
}


/// R55: create or edit my own gesture on its own page.
class GestureEditorPage extends StatefulWidget{
 const GestureEditorPage({super.key,this.original,required this.options});
 final Map<String,dynamic>? original;
 final Map<String,String> options;
 @override State<GestureEditorPage> createState()=>_GestureEditorPageState();
}

class _GestureEditorPageState extends State<GestureEditorPage> with FormChangeTracker<GestureEditorPage>{
 late final TextEditingController name=TextEditingController(text:widget.original?['title']?.toString()??'');
 late final TextEditingController body=TextEditingController(text:widget.original?['message']?.toString()??'');
 late String kind=widget.original?['kind']?.toString()??widget.options.keys.first;
 @override String get signature=>[name.text,body.text,kind].join('|');
 @override void dispose(){name.dispose();body.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>EditorScaffold(
  title:widget.original==null?'Add new gesture':'Edit gesture',
  isNew:widget.original==null,isChanged:()=>changed,
  isComplete:()=>name.text.trim().isNotEmpty&&body.text.trim().isNotEmpty,
  listenTo:[name,body],
  onSave:()=>Navigator.pop(context,<String,String?>{
   'title':name.text.trim(),'message':body.text.trim(),'kind':kind}),
  body:ListView(padding:const EdgeInsets.all(18),children:[
   TextField(controller:name,maxLength:60,
    decoration:const InputDecoration(labelText:'Gesture name *',border:OutlineInputBorder())),
   const SizedBox(height:8),
   TextField(controller:body,maxLength:240,minLines:3,maxLines:6,
    decoration:const InputDecoration(labelText:'Your message *',border:OutlineInputBorder())),
   const SizedBox(height:8),
   DropdownButtonFormField<String>(
    initialValue:widget.options.containsKey(kind)?kind:widget.options.keys.first,
    decoration:const InputDecoration(labelText:'Theme',border:OutlineInputBorder()),
    items:[for(final o in widget.options.entries)DropdownMenuItem(value:o.key,child:Text(o.value))],
    onChanged:(v)=>setState(()=>kind=v??kind)),
  ]));
}
