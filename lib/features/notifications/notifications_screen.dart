import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../coordinate/activity_detail_screen.dart';
import '../calendar/calendar_screen.dart';
import '../connect/couple_letters_screen.dart';
import '../connect/partner_gestures_screen.dart';
import '../notes/notes_screen.dart';

class NotificationBell extends StatelessWidget {
 const NotificationBell({super.key});
 @override Widget build(BuildContext context) {
  final db=Supabase.instance.client;
  final user=db.auth.currentUser?.id;
  if(user==null)return const SizedBox.shrink();
  return StreamBuilder<List<Map<String,dynamic>>>(
   stream:db.from('space_notifications').stream(primaryKey:['id'])
     .eq('recipient_id',user).order('created_at',ascending:false).limit(100),
   builder:(context,snapshot){
    final unread=snapshot.data?.where((n)=>n['read_at']==null).length??0;
    return IconButton(
     tooltip:'Notifications',
     onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(
      builder:(_)=>const NotificationsScreen())),
     icon:Badge(isLabelVisible:unread>0,label:Text(unread>99?'99+':'$unread'),
       child:const Icon(Icons.notifications_none_outlined)),
    );
   },
  );
 }
}

class NotificationsScreen extends StatefulWidget {
 const NotificationsScreen({super.key});
 @override State<NotificationsScreen> createState()=>_NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
 final db=Supabase.instance.client;
 bool unreadOnly=false;
 bool saving=false;
 String? error;

 Future<void> _markAllRead(String userId) async {
   if(saving)return;
   setState((){saving=true;error=null;});
   try{
     await db.from('space_notifications')
       .update({'read_at':DateTime.now().toUtc().toIso8601String()})
       .eq('recipient_id',userId).isFilter('read_at',null);
   }catch(_){
     if(mounted){setState(()=>error='Could not mark all as read.');}
   }finally{
     if(mounted){setState(()=>saving=false);}
   }
 }

 Future<void> _open(Map<String,dynamic> item,String userId) async {
   if(item['read_at']==null){
     try{
       await db.from('space_notifications')
         .update({'read_at':DateTime.now().toUtc().toIso8601String()})
         .eq('id',item['id'].toString()).eq('recipient_id',userId);
     }catch(_){}
   }
   if(!mounted)return;
   final type=item['object_kind']?.toString()??'';
   final Widget screen;
   if(type=='activity'){
     final id=item['activity_id']?.toString();
     if(id==null)return;
     screen=ActivityScreen(id:id);
   }else if(type=='calendar'){
     screen=CalendarScreen(initialEventId:
       (item['calendar_event_id']??item['object_id'])?.toString());
   }else if(type=='note'){
     screen=NotesScreen(initialNoteId:item['object_id']?.toString());
   }else if(type=='letter'){
     screen=const CoupleLettersScreen();
   }else if(type=='gesture'){
     screen=const PartnerGesturesScreen();
   }else{return;}
   Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>screen));
 }

 @override Widget build(BuildContext context){
   final userId=db.auth.currentUser?.id;
   if(userId==null)return const Scaffold(
     body:Center(child:Text('Sign in required')));
   return Scaffold(
     appBar:AppBar(title:const Text('Notifications')),
     body:StreamBuilder<List<Map<String,dynamic>>>(
       stream:db.from('space_notifications').stream(primaryKey:['id'])
         .eq('recipient_id',userId).order('created_at',ascending:false).limit(100),
       builder:(context,snapshot){
         if(snapshot.hasError)return const Center(
           child:Text('Notifications are unavailable.'));
         if(!snapshot.hasData)return const Center(
           child:CircularProgressIndicator());
         final all=snapshot.data!;
         final unread=all.where((item)=>item['read_at']==null).length;
         final shown=unreadOnly?
           all.where((item)=>item['read_at']==null).toList():all;
         return Column(children:[
           Padding(
             padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
             child:Row(children:[
               FilterChip(
                 selected:unreadOnly,
                 label:Text('Unread ($unread)'),
                 onSelected:(v)=>setState(()=>unreadOnly=v)),
               const Spacer(),
               TextButton.icon(
                 onPressed:unread==0||saving?null:()=>_markAllRead(userId),
                 icon:const Icon(Icons.done_all),
                 label:const Text('Mark all read')),
             ]),
           ),
           if(error!=null)Text(error!,style:TextStyle(
             color:Theme.of(context).colorScheme.error)),
           Expanded(
             child:shown.isEmpty?
               Center(child:Text(unreadOnly?'No unread notifications.':'All caught up.')):
               ListView.builder(
                 itemCount:shown.length,
                 itemBuilder:(context,i){
                   final item=shown[i];
                   final kind=item['kind']?.toString()??'';
                   final unreadItem=item['read_at']==null;
                   return ListTile(
                     leading:Icon(kind=='mention'?Icons.alternate_email:
                       kind=='reply'?Icons.reply:
                       kind=='letter'?Icons.mail_outline:
                       kind=='gesture'?Icons.favorite_border:Icons.event_outlined),
                     title:Text(item['headline']?.toString()??'Update',
                       style:TextStyle(fontWeight:unreadItem?
                         FontWeight.bold:FontWeight.normal)),
                     subtitle:Text(kind=='mention'?'Your partner mentioned you':
                       kind=='reply'?'Your partner replied':
                       kind=='letter'?'New letter':
                       kind=='gesture'?
                         (item['generated_automatically']==true
                           ?'Scheduled by your partner'
                           :'Personally sent by your partner'):
                       kind=='event'?'New shared event':
                       kind=='reminder'?'Your partner sent an event reminder':
                         'Shared update'),
                     trailing:unreadItem?const Icon(Icons.circle,size:8):null,
                     onTap:()=>_open(item,userId),
                   );
                 },
               ),
           ),
         ]);
       },
     ),
   );
 }
}
