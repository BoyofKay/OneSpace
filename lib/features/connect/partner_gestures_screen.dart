import '../../core/form_kit.dart';
import '../../core/editor_scaffold.dart';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/current_space_cache.dart';
import '../../core/app_env.dart';
import 'gesture_experience.dart';
import 'gesture_pool_rules.dart';
import 'love_prompt_rules.dart';
import 'package:onespace/l10n/phrases.dart';

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
 // R75: in a logical order — everyday love, the day's rhythm, care and support,
 // plans and moments, then missing each other (only when you live apart).
 _GestureOption('love_you','I love you',Icons.favorite,[
   "I love you. Simply, completely, always.",
   "Just a reminder: I love you more today than yesterday.",
   "I love you — in every language and every time zone.",
   "You are my favorite person. I love you.",
 ]),
 _GestureOption('hug','Send a hug',Icons.volunteer_activism_outlined,[
   'Sending you a big, warm hug.',
   'A hug is on its way to you, my love.',
   'Wrapping you in a little extra love today.',
   // R64: more messages (appended, so edited/hidden ones keep their place).
   "Here is a hug that lasts all day.",
   "Hold on — a long, tight hug is coming your way.",
 ]),
 _GestureOption('kiss','Send a kiss',Icons.emoji_emotions_outlined,[
   "Sending you a kiss.",
   "A little kiss, delivered right to your heart.",
   "Close your eyes — that was a kiss from me.",
   "Kisses across the miles, just for you.",
 ]),
 _GestureOption('thinking','Thinking of you',Icons.favorite_outline,[
   'Just wanted you to know I am thinking about you.',
   'You crossed my mind, and I smiled.',
   'No matter the distance, you are in my thoughts.',
   // R64: more messages (appended, so edited/hidden ones keep their place).
   "You are on my mind, as always.",
   "A quiet moment, and of course I thought of you.",
 ]),
 _GestureOption('smile','You made me smile',Icons.sentiment_satisfied_alt_outlined,[
   'Thinking about you just made me smile.',
   'You are the brightest part of my day.',
   'A little smile, just because of you.',
   // R64: more messages (appended, so edited/hidden ones keep their place).
   "Remembering your laugh made my whole day.",
   "You have a way of making everything lighter.",
 ]),
 _GestureOption('lucky','Lucky to have you',Icons.stars_outlined,[
   'I feel so lucky to have you in my life.',
   'Of all the people in the world, I get to love you.',
   'Being yours is one of my favorite things.',
   // R64: more messages (appended, so edited/hidden ones keep their place).
   "Out of everyone, I got you. Lucky me.",
   "Loving you is the best thing that ever happened to me.",
 ]),
 // The day's rhythm.
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
   // R64: more messages (appended, so edited/hidden ones keep their place).
   "Good morning! Do not forget your breakfast.",
   "Rise and shine, my love. Today is yours.",
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
   // R64: more messages (appended, so edited/hidden ones keep their place).
   "Goodnight. I will meet you in our dreams.",
   "Sleep well. I am right here in your heart.",
 ]),
 // Care and support.
 _GestureOption('thanks','Thank you',Icons.handshake_outlined,[
   'Thank you for being there for me.',
   'I notice all the little things you do. Thank you, love.',
   'Thank you for making my life warmer.',
   // R64: more messages (appended, so edited/hidden ones keep their place).
   "Thank you for loving me the way you do.",
   "Thank you for every little thing, every day.",
 ]),
 _GestureOption('proud','Proud of you',Icons.auto_awesome_outlined,[
   'I am so proud of you.',
   'I see everything you do, and I appreciate you.',
   'You are amazing. I hope you know that.',
   // R64: more messages (appended, so edited/hidden ones keep their place).
   "Look how far you have come. I am proud of you.",
   "You inspire me every single day.",
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
   // R64: more messages (appended, so edited/hidden ones keep their place).
   "Whatever today brings, we face it together.",
   "Breathe. You are stronger than you think.",
 ]),
 _GestureOption('get_well','Feel better soon',Icons.local_florist_outlined,[
   "Feel better soon. Rest, drink water, and let me spoil you.",
   "Sending healing hugs and a warm blanket of love.",
   "I wish I could take care of you right now. Get well soon.",
   "Take it easy today. Your only job is to rest.",
 ]),
 _GestureOption('sorry','I am sorry',Icons.healing_outlined,[
   "I am sorry. You matter more to me than being right.",
   "I did not handle that well. I am sorry, my love.",
   "Can we start again? I am sorry.",
   "I hear you, and I am sorry I hurt you.",
 ]),
 // Plans and moments.
 _GestureOption('celebrate','Congratulations!',Icons.celebration_outlined,[
   "Congratulations! I knew you could do it.",
   "So proud of this moment — let us celebrate!",
   "You did it! Cheering for you so loudly.",
   "Today is your day. Congratulations, my love.",
 ]),
 _GestureOption('date_night','Cannot wait for our date',Icons.wine_bar_outlined,[
   "I cannot wait for our date.",
   "Counting the hours until our date night.",
   "Save your best smile for tonight — it is a date.",
   "Our date is the best part of my week.",
 ]),
 _GestureOption('call_me','Call me when you can',Icons.call_outlined,[
   "Call me when you can — I miss your voice.",
   "No rush. Whenever you are free, I would love to talk.",
   "I have something to tell you. Call me when you can?",
   "Your voice would make my day. Call me later?",
 ]),
 _GestureOption('safe_travels','Safe travels',Icons.flight_takeoff,[
   "Safe travels, my love. Text me when you land.",
   "Every mile brings you closer. Travel safe.",
   "Wishing you smooth skies and an easy journey.",
   "Have a safe trip. My heart is traveling with you.",
 ]),
 // Missing each other.
 _GestureOption('miss_you','I miss you',Icons.heart_broken_outlined,[
   'I miss you more than words can say.',
   'Wish you were here with me right now.',
   'Across the distance, I am missing you.',
   // R64: more messages (appended, so edited/hidden ones keep their place).
   "Everything reminds me of you today.",
   "Counting down until I can see you again.",
 ]),
 _GestureOption('miss_together','I miss us together',Icons.people_alt_outlined,[
   'I miss the simple moments when we are side by side.',
   'I miss our laughter and the ordinary magic of us together.',
   'I cannot wait for our next moment together.',
   // R64: more messages (appended, so edited/hidden ones keep their place).
   "Our next hug is going to be a long one.",
   "I miss sharing ordinary days with you.",
 ]),
 _GestureOption('miss_home','I miss our home',Icons.home_outlined,[
   'I miss the feeling of being home with you.',
   'Home is wherever we get to be together.',
   'Missing our little routines and our place.',
   // R64: more messages (appended, so edited/hidden ones keep their place).
   "I miss our coffee mornings at home.",
   "Our place is not the same without both of us.",
 ]),
 _GestureOption('miss_kids','I miss our kids',Icons.child_care_outlined,[
   'I am missing our kids and all their little moments.',
   'Sending extra love to the little ones today.',
   'I wish I could share this moment with our family.',
   // R64: more messages (appended, so edited/hidden ones keep their place).
   "Give the little ones a big hug from me.",
   "Tell the kids I love them to the moon and back.",
 ]),
 _GestureOption('miss_pets','I miss our furry ones',Icons.pets_outlined,[
   'Please give our furry ones an extra cuddle from me.',
   'I miss their little paws and all the chaos they bring.',
   'Thinking of our furry family today.',
   // R64: more messages (appended, so edited/hidden ones keep their place).
   "Tell our furry ones I will be home soon.",
   "A scratch behind the ears from me, please.",
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
 /// R75: living together — no "from miles away" messages, no missing-home types.
 bool together=false;

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
     final mode=await db.from('spaces').select('relationship_mode').eq('id',space).maybeSingle();
     final livingTogether=mode?['relationship_mode']=='living_together';
     final partner=members.where((m)=>m['user_id']!=me).firstOrNull;
     if(!mounted){return;}
     final other=partner?['user_id']?.toString();
     final names=CurrentSpaceCache.instance.memberNamesFor(space);
     final templates=await db.from('gesture_templates').select('id,title,message,kind')
       .eq('space_id',space).eq('creator_id',me).order('created_at',ascending:false);
     final presetQuery=OneSpaceEnv.usesLegacyBackend
       ?db.from('gesture_message_overrides')
         .select('kind,message_index,message,disabled').eq('space_id',space)
       :db.from('gesture_message_overrides')
         .select('kind,message_index,message,disabled');
     final updated=await presetQuery.eq('owner_id',me);
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
       together=livingTogether;
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
     case 'love_you':return const Color(0xFFE0566F);
     case 'kiss':return const Color(0xFFE86FA0);
     case 'sorry':return const Color(0xFF8E8FB8);
     case 'celebrate':return const Color(0xFFE0A33A);
     case 'get_well':return const Color(0xFF5FA88A);
     case 'safe_travels':return const Color(0xFF4F8FC0);
     case 'call_me':return const Color(0xFF3C9C9A);
     case 'date_night':return const Color(0xFFB0577A);

     default:return const Color(0xFF518FB7);
   }
 }
 List<String> pool(_GestureOption option)=>
   GesturePoolRules.activeMessages(
     kind:option.id,builtIn:option.messages,
     overrides:overrides,custom:custom,together:together,
   );
 List<_GestureOption> get sendable=>together
   ?_options.where((o)=>!GesturePoolRules.apartOnly.contains(o.id)).toList():_options;
 Future<void> editPreset(_GestureOption option,int index) async{
   final old=overrides.where((o)=>o['kind']==option.id&&
      o['message_index']==index).firstOrNull;
   final message=TextEditingController(
     text:old?['message']?.toString()??option.messages[index]);
   var disabled=old?['disabled']==true;
   try{
     final accepted=await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(fullscreenDialog:true,builder:(ctx)=>
       StatefulBuilder(builder:(ctx,update)=>EditorPage(
         title:Text(tt('Edit ')+option.title),
         content:Column(mainAxisSize:MainAxisSize.min,children:[
           TextField(controller:message,maxLength:240,minLines:3,maxLines:6,
             decoration:InputDecoration(labelText:tt('Message'),alignLabelWithHint:true,
              border:OutlineInputBorder())),
           const SizedBox(height:6),
           Align(alignment:AlignmentDirectional.centerStart,child:OptionChip(label:tt('Don’t pick this one at random'),
             icon:Icons.visibility_off_outlined,value:disabled,onChanged:(v)=>update(()=>disabled=v))),
         ]),
         actions:[
           TextButton(onPressed:()=>Navigator.pop(ctx,false),
             child:Text(tt('Cancel'))),
           FilledButton(onPressed:()=>Navigator.pop(ctx,true),
             child:Text(tt('Save'))),
         ],
       ))));
     if(accepted!=true||spaceId==null)return;
     final me=db.auth.currentUser!.id;
     await db.from('gesture_message_overrides').upsert({
       if(!OneSpaceEnv.usesLegacyBackend) 'private_space_id':me
       else 'space_id':spaceId,
       'owner_id':me,'kind':option.id,
       'message_index':index,'message':message.text.trim(),
       'disabled':disabled,
     },onConflict:'owner_id,kind,message_index');
     await _load();
   }catch(_){
     if(mounted)ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content:Text(tt('Unable to update gesture message.'))));
   }finally{message.dispose();}
 }
 Widget gestureLibrary(){
   return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
     FilledButton.tonalIcon(onPressed:()=>_createCustom(),
       icon:const Icon(Icons.add_reaction_outlined),
       label:Text(tt('Create my own gesture'))),
     const SizedBox(height:12),
     Text(tt('Gesture types · tap to expand'),
       style:Theme.of(context).textTheme.titleMedium),
     const SizedBox(height:7),
     for(final option in _options)
       Card(elevation:0,clipBehavior:Clip.antiAlias,
         child:ExpansionTile(
           leading:CircleAvatar(
             backgroundColor:_tint(option.id).withValues(alpha:.16),
             child:GestureKindSymbol(kind:option.id,color:_tint(option.id))),
           title:Text(tt(option.title)),
           subtitle:Text(tt(pool(option).length.toString()+' active messages')),
           childrenPadding:const EdgeInsetsDirectional.fromSTEB(12,2,12,12),
           children:[
             for(var index=0;index<option.messages.length;index++)
               ListTile(
                 dense:true,
                 title:Text(tt(overrides.where((o)=>o['kind']==option.id&&
                   o['message_index']==index).firstOrNull?['message']
                     ?.toString()??option.messages[index])),
                 subtitle:Text(tt(overrides.any((o)=>o['kind']==option.id&&
                   o['message_index']==index&&o['disabled']==true)?
                     'Hidden from pool':'Built-in · editable')),
                 trailing:IconButton(
                   tooltip:tt('Edit this message'),
                   icon:const Icon(Icons.edit_outlined),
                   onPressed:()=>editPreset(option,index)),
               ),
             for(final item in custom.where((row)=>row['kind']==option.id))
               ListTile(
                 dense:true,
                 title:Text(tt(item['message']?.toString()??'')),
                 subtitle:Text(tt('My message')),
                 trailing:Row(mainAxisSize:MainAxisSize.min,children:[
                   IconButton(tooltip:tt('Edit'),icon:const Icon(Icons.edit_outlined),
                     onPressed:()=>_createCustom(item)),
                   IconButton(tooltip:tt('Remove'),icon:const Icon(Icons.delete_outline),
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
       SnackBar(content:Text(tt('Could not save this gesture.'))));
   }
 }
 Future<void> _deleteCustom(String id) async {
   final yes=await showDialog<bool>(context:context,builder:(ctx)=>
     AlertDialog(title:Text(tt('Remove personal gesture?')),
       content:Text(tt('Sent messages remain in gesture history. '
         'This only removes your reusable template.')),
       actions:[
         TextButton(onPressed:()=>Navigator.pop(ctx,false),
           child:Text(tt('Keep'))),
         FilledButton(onPressed:()=>Navigator.pop(ctx,true),
           child:Text(tt('Remove'))),
       ]));
   if(yes!=true)return;
   try{
     await db.from('gesture_templates').delete().eq('id',id);
     await _load();
   }catch(_){
     if(mounted)ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content:Text(tt('Could not delete gesture.'))));
   }
 }

 Future<void> _send(_GestureOption option) async {
   if(busyKind!=null||spaceId==null||recipientId==null){return;}
   final messages=pool(option);
   if(messages.isEmpty){
     if(mounted)ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content:Text(tt('No active messages in this gesture type.'))));
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
         SnackBar(content:Text(tt('Sent to ')+(recipientName??'your partner'))),
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
     appBar:AppBar(title:Text(tt(widget.manageOnly?tt('Love gesture settings'):tt('A little love'))),actions:[
       if(!widget.manageOnly)IconButton(tooltip:tt('Sent and received history'),icon:const Icon(Icons.history),
         onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(
           builder:(_)=>const GestureHistoryScreen()))),
     ]),
     body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),
       children:[
         Text(tt(widget.manageOnly?'My gesture library':
           'Small gestures, felt across any distance.'),
           style:Theme.of(context).textTheme.titleMedium),
         const SizedBox(height:6),
         Text(tt(widget.manageOnly?'Each gesture type has one randomized message pool. Edit or hide built-in messages and add your own.':
           'Tap a gesture to send it. Manage your gesture library in Settings.')),
         const SizedBox(height:16),
         if(!widget.manageOnly)...[
          FilledButton.tonalIcon(
           onPressed:_createCustom,
           icon:const Icon(Icons.add_reaction_outlined),
           label:Text(tt('Create my own gesture'))),
          if(LovePromptRules.lastSentSummary(lastSentAt,DateTime.now())!=null)
           Padding(padding:const EdgeInsets.only(top:6),
            child:Text(tt(LovePromptRules.lastSentSummary(
             lastSentAt,DateTime.now())!),
             style:Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height:12),
         ],
         if(loading)const Center(child:CircularProgressIndicator()),
         if(!loading&&recipientId==null)
           Text(tt('Connect your partner to send a gesture.')),
         if(error!=null)Text(tt(error!),
           style:TextStyle(color:Theme.of(context).colorScheme.error)),
         if(recipientId!=null)...[
           if(!widget.manageOnly)Text(tt('Send to ')+(sendToLabel??recipientName??'your partner'),
             style:Theme.of(context).textTheme.titleSmall),
           if(!widget.manageOnly)const SizedBox(height:12),
           if(!widget.manageOnly)LayoutBuilder(builder:(ctx,size)=>GridView.builder(
             shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),
             itemCount:sendable.length,
             gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(
               crossAxisCount:size.maxWidth>640?3:2,
               childAspectRatio:1.28,crossAxisSpacing:9,mainAxisSpacing:9),
             itemBuilder:(ctx,index){
               final option=sendable[index],color=_tint(option.id);
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
                         Text(tt(option.title),textAlign:TextAlign.center,
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
  title:widget.original==null?tt('Add new gesture'):tt('Edit gesture'),
  isNew:widget.original==null,isChanged:()=>changed,
  isComplete:()=>name.text.trim().isNotEmpty&&body.text.trim().isNotEmpty,
  listenTo:[name,body],
  onSave:()=>Navigator.pop(context,<String,String?>{
   'title':name.text.trim(),'message':body.text.trim(),'kind':kind}),
  body:ListView(padding:const EdgeInsets.all(18),children:[
   TextField(controller:name,maxLength:60,autofocus:widget.original==null,
    textCapitalization:TextCapitalization.sentences,
    decoration:InputDecoration(labelText:tt('Gesture name *'),hintText:tt('Morning coffee wish'),
     border:OutlineInputBorder())),
   const SizedBox(height:8),
   TextField(controller:body,maxLength:240,minLines:3,maxLines:6,
    textCapitalization:TextCapitalization.sentences,
    decoration:InputDecoration(labelText:tt('Your message *'),alignLabelWithHint:true,
     hintText:tt('What your partner will read'),border:OutlineInputBorder())),
   const SizedBox(height:8),
   widget.options.length<=6
    ?ChoiceRow<String>(label:tt('Theme'),options:widget.options,
      selected:widget.options.containsKey(kind)?kind:widget.options.keys.first,
      onSelected:(v){if(v!=null)setState(()=>kind=v);})
    :ChoicePickerField<String>(label:tt('Theme'),icon:Icons.palette_outlined,options:widget.options,
      selected:widget.options.containsKey(kind)?kind:widget.options.keys.first,
      onSelected:(v){if(v!=null)setState(()=>kind=v);}),
  ]));
}

/// R61: a message for [kind] (used when a gesture is sent by voice).
String? gestureMessageFor(String kind) {
  final o = _options.where((x) => x.id == kind).firstOrNull;
  if (o == null || o.messages.isEmpty) return null;
  return o.messages[Random().nextInt(o.messages.length)];
}

/// R61: the gesture's title ("Send a hug").
String? gestureTitleFor(String kind) => _options.where((x) => x.id == kind).firstOrNull?.title;
