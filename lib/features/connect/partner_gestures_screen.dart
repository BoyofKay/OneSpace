import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/current_space_cache.dart';
import 'scheduled_gestures_panel.dart';
import 'gesture_experience.dart';

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
 ]),
 _GestureOption('goodnight','Sweet dreams',Icons.nightlight_round,[
   'Sweet dreams. I am holding you in my heart.',
   'Goodnight, my love. Rest well.',
   'The day is ending, but my love for you never does.',
 ]),
 _GestureOption('proud','Proud of you',Icons.auto_awesome_outlined,[
   'I am so proud of you.',
   'I see everything you do, and I appreciate you.',
   'You are amazing. I hope you know that.',
 ]),
 _GestureOption('support','You have got this',Icons.favorite_border,[
   'I am here for you, even from far away.',
   'You do not have to carry today alone.',
   'You have got this. I believe in you.',
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
 _GestureOption('miss_together','I miss us together',Icons.favorite_border,[
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
 String? spaceId,recipientId,recipientName;
 String? busyKind,error;
 String? lastSent;
 bool loading=true;
 List<Map<String,dynamic>> custom=[];

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
     final templates=await db.from('gesture_templates').select('id,title,message,kind,scheduled_moment').eq('space_id',space).eq('creator_id',me).order('created_at',ascending:false);
     setState((){
       spaceId=space;recipientId=other;
       recipientName=other==null?null:(names?[other]??'your partner');
       custom=templates;
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
     case 'miss_together':return const Color(0xFFDC658A);
     case 'miss_home':return const Color(0xFFDC9960);
     case 'miss_kids':return const Color(0xFF729CC8);
     case 'miss_pets':return const Color(0xFFBC804D);
     default:return const Color(0xFF518FB7);
   }
 }
 Future<void> _sendCustom(Map<String,dynamic> item) async {
   if(busyKind!=null||spaceId==null||recipientId==null)return;
   setState(()=>busyKind=item['id'].toString());
   try{
     await db.from('partner_gestures').insert({
       'space_id':spaceId,'recipient_id':recipientId,
       'kind':item['kind'],'message':item['message'],
     });
     if(mounted)ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content:Text('Your personal gesture was sent.')));
   }catch(_){
     if(mounted)ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content:Text('Could not send this gesture.')));
   }finally{if(mounted)setState(()=>busyKind=null);}
 }
 Future<void> _createCustom([Map<String,dynamic>? original]) async {
   final name=TextEditingController(text:original?['title']?.toString()??''),
     body=TextEditingController(text:original?['message']?.toString()??'');
   var kind=original?['kind']?.toString()??'hug';
   String? trigger=original?['scheduled_moment']?.toString();
   try{
     final data=await showDialog<Map<String,String?>>(context:context,
       builder:(ctx)=>StatefulBuilder(builder:(ctx,update)=>AlertDialog(
         title:Text(original==null?'Create a love gesture':'Edit my gesture'),
         content:SingleChildScrollView(child:Column(
           mainAxisSize:MainAxisSize.min,children:[
             TextField(controller:name,maxLength:60,
               decoration:const InputDecoration(labelText:'Gesture name')),
             TextField(controller:body,maxLength:240,minLines:2,maxLines:4,
               decoration:const InputDecoration(labelText:'Your message')),
             DropdownButtonFormField<String>(
               initialValue:kind,decoration:const InputDecoration(labelText:'Theme'),
               items:[for(final option in _options)
                 DropdownMenuItem(value:option.id,child:Text(option.title))],
               onChanged:(v)=>update(()=>kind=v??kind)),
             DropdownButtonFormField<String>(
               initialValue:trigger??'manual',
               decoration:const InputDecoration(labelText:'Optional automatic trigger'),
               items:const [
                 DropdownMenuItem(value:'manual',child:Text('Manual only')),
                 DropdownMenuItem(value:'morning',child:Text('Morning')),
                 DropdownMenuItem(value:'after_work',child:Text('After work')),
                 DropdownMenuItem(value:'goodnight',child:Text('Before bed')),
               ],
               onChanged:(v)=>update(()=>trigger=v=='manual'?null:v)),
             const Text('Automatic messages require an enabled ritual and your partner’s consent.'),
           ])),
         actions:[
           TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
           FilledButton(onPressed:(){
             if(name.text.trim().isEmpty||body.text.trim().isEmpty)return;
             Navigator.pop(ctx,{
               'title':name.text.trim(),'message':body.text.trim(),
               'kind':kind,'trigger':trigger,
             });
           },child:const Text('Save')),
         ],
       )));
     if(data==null||spaceId==null||recipientId==null)return;
     if(original==null){
       await db.from('gesture_templates').insert({
         'space_id':spaceId,'recipient_id':recipientId,
         'title':data['title'],'message':data['message'],
         'kind':data['kind'],'scheduled_moment':data['trigger'],
       });
     }else{
       await db.from('gesture_templates').update({
         'title':data['title'],'message':data['message'],
         'kind':data['kind'],'scheduled_moment':data['trigger'],
       }).eq('id',original['id'].toString())
         .eq('creator_id',db.auth.currentUser!.id);
     }
     await _load();
   }catch(_){
     if(mounted)ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content:Text('Could not save this gesture.')));
   }finally{name.dispose();body.dispose();}
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
   final random=Random();
   var i=random.nextInt(option.messages.length);
   if(option.messages.length>1&&option.messages[i]==lastSent){
     i=(i+1)%option.messages.length;
   }
   final message=option.messages[i];
   setState((){busyKind=option.id;error=null;});
   try{
     await db.from('partner_gestures').insert({
       'space_id':spaceId,'recipient_id':recipientId,
       'kind':option.id,'message':message,
     });
     if(mounted){
       setState(()=>lastSent=message);
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
         Text(widget.manageOnly?'My gesture library & thoughtful rituals':
           'Small gestures, felt across any distance.',
           style:Theme.of(context).textTheme.titleMedium),
         const SizedBox(height:6),
         Text(widget.manageOnly?'Manage your own messages and choose when rituals are allowed.':
           'Tap a gesture to send it. Your personal library and scheduled rituals are in Settings.'),
         const SizedBox(height:16),
         if(loading)const Center(child:CircularProgressIndicator()),
         if(!loading&&recipientId==null)
           const Text('Connect your partner to send a gesture.'),
         if(error!=null)Text(error!,
           style:TextStyle(color:Theme.of(context).colorScheme.error)),
         if(recipientId!=null)...[
           if(!widget.manageOnly)Text('Send to '+(recipientName??'your partner'),
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
                           child:Icon(option.icon,color:color,size:25)),
                         const SizedBox(height:9),
                         Text(option.title,textAlign:TextAlign.center,
                           maxLines:2,overflow:TextOverflow.ellipsis,
                           style:Theme.of(context).textTheme.titleSmall),
                         const SizedBox(height:3),
                         Text('Tap to send',
                           style:Theme.of(context).textTheme.labelSmall),
                       ]),
                   ),
                 ),
               );
             },
           )),
           const SizedBox(height:14),
           FilledButton.tonalIcon(
             onPressed:_createCustom,
             icon:const Icon(Icons.add_reaction_outlined),
             label:const Text('Create my own gesture')),
           if(custom.isNotEmpty)...[
             const SizedBox(height:15),
             Text('My gestures',style:Theme.of(context).textTheme.titleMedium),
             for(final item in custom)Card(elevation:0,child:ListTile(
               leading:Icon(Icons.favorite_outline,color:_tint(item['kind'].toString())),
               title:Text(item['title']?.toString()??'Gesture'),
               subtitle:Text(
                 (item['message']?.toString()??'')+
                 (item['scheduled_moment']==null?'':' · Scheduled: '+item['scheduled_moment'].toString()),
                 maxLines:2,overflow:TextOverflow.ellipsis),
               onTap:widget.manageOnly?()=>_createCustom(item):()=>_sendCustom(item),
               trailing:widget.manageOnly?
                 Row(mainAxisSize:MainAxisSize.min,children:[
                   IconButton(icon:const Icon(Icons.edit_outlined),
                     tooltip:'Edit gesture',
                     onPressed:()=>_createCustom(item)),
                   IconButton(icon:const Icon(Icons.delete_outline),
                     tooltip:'Remove gesture',
                     onPressed:()=>_deleteCustom(item['id'].toString())),
                 ]):null,
             )),
           ],
           if(widget.manageOnly)...[
           const SizedBox(height:16),
           ScheduledGesturesPanel(
             spaceId:spaceId!,recipientId:recipientId!,
             recipientName:recipientName??'your partner'),
           ],
         ],
       ],
     )),
   );
 }
}
