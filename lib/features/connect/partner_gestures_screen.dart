import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/current_space_cache.dart';

/// Intentionally sent gestures. Messages are explicitly identified as presets;
/// there is no automated impersonation or push-notification claim here.
class PartnerGesturesScreen extends StatefulWidget {
 const PartnerGesturesScreen({super.key});
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
];

class _PartnerGesturesScreenState extends State<PartnerGesturesScreen> {
 final db=Supabase.instance.client;
 String? spaceId,recipientId,recipientName;
 String? busyKind,error;
 String? lastSent;
 bool loading=true;

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
     setState((){
       spaceId=space;recipientId=other;
       recipientName=other==null?null:(names?[other]??'your partner');
       loading=false;
     });
   }catch(_){
     if(mounted){setState((){
       error='Could not load your shared space.';
       loading=false;
     });}
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
     appBar:AppBar(title:const Text('A little love')),
     body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),
       children:[
         Text('Small gestures, felt across any distance.',
           style:Theme.of(context).textTheme.titleMedium),
         const SizedBox(height:6),
         Text('Choose one to send a short, varied preset message. '
           'Your partner sees that you deliberately sent it.'),
         const SizedBox(height:16),
         if(loading)const Center(child:CircularProgressIndicator()),
         if(!loading&&recipientId==null)
           const Text('Connect your partner to send a gesture.'),
         if(error!=null)Text(error!,
           style:TextStyle(color:Theme.of(context).colorScheme.error)),
         if(recipientId!=null)...[
           Text('Send to '+(recipientName??'your partner'),
             style:Theme.of(context).textTheme.titleSmall),
           const SizedBox(height:12),
           Wrap(spacing:8,runSpacing:8,children:[
             for(final option in _options)
               FilledButton.tonalIcon(
                 onPressed:busyKind==null?()=>_send(option):null,
                 icon:Icon(option.icon),
                 label:Text(busyKind==option.id?'Sending…':option.title),
               ),
           ]),
           const SizedBox(height:24),
           Text('Our recent gestures',
             style:Theme.of(context).textTheme.titleMedium),
           const SizedBox(height:8),
           StreamBuilder<List<Map<String,dynamic>>>(
             stream:db.from('partner_gestures')
               .stream(primaryKey:['id']).eq('space_id',spaceId!)
               .order('created_at',ascending:false).limit(40),
             builder:(context,snapshot){
               if(snapshot.hasError){
                 return const Text('Could not load gestures.');
               }
               if(!snapshot.hasData){
                 return const Center(child:CircularProgressIndicator());
               }
               if(snapshot.data!.isEmpty){
                 return const Text('Your first gesture will appear here.');
               }
               return Column(children:[
                 for(final item in snapshot.data!)
                   ListTile(
                     leading:Icon(item['sender_id']==db.auth.currentUser?.id
                       ?Icons.outgoing_mail:Icons.favorite_outline),
                     title:Text(item['message']?.toString()??''),
                     subtitle:Text(item['sender_id']==db.auth.currentUser?.id
                       ?'You sent this':'Sent by your partner'),
                   ),
               ]);
             },
           ),
         ],
       ],
     )),
   );
 }
}
