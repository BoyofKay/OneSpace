import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../coordinate/activity_detail_screen.dart';
import '../calendar/calendar_screen.dart';
import '../plans/plans_screen.dart';
import '../reminders/reminders_screen.dart';
import '../connect/couple_letters_screen.dart';
import '../connect/gesture_experience.dart';
import '../notes/notes_screen.dart';
import '../checkins/checkins_screen.dart';
import '../connect/shared_experiences_screen.dart';
import '../world/trips_screen.dart';
import '../occasions/occasions_screen.dart';
import '../memories/scrapbook_studio_screen.dart';

/// One stable realtime subscription per signed-in account, not per frame.
class NotificationBell extends StatefulWidget {
 const NotificationBell({super.key});
 @override State<NotificationBell> createState()=>_NotificationBellState();
}
class _NotificationBellState extends State<NotificationBell> {
 final db=Supabase.instance.client;
 Stream<List<Map<String,dynamic>>>? _stream;
 String? _streamUser;
 Stream<List<Map<String,dynamic>>> _forUser(String user) {
  if(_streamUser!=user||_stream==null){
   _streamUser=user;
   _stream=db.from('space_notifications').stream(primaryKey:['id'])
    .eq('recipient_id',user).order('created_at',ascending:false).limit(100);
  }
  return _stream!;
 }
 @override Widget build(BuildContext context) {
  final user=db.auth.currentUser?.id;
  if(user==null){
   _stream=null;_streamUser=null;
   return const SizedBox.shrink();
  }
  return StreamBuilder<List<Map<String,dynamic>>>(
   stream:_forUser(user),
   builder:(context,snapshot){
    final unread=snapshot.data?.where((n)=>n['read_at']==null).length??0;
    return IconButton(
     tooltip:unread==0?'Notifications':'Notifications, $unread unread',
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
 Stream<List<Map<String,dynamic>>>? _stream;
 String? _streamUser;
 Stream<List<Map<String,dynamic>>> _feed(String user){
  if(_streamUser!=user||_stream==null){
   _streamUser=user;
   _stream=db.from('space_notifications').stream(primaryKey:['id'])
    .eq('recipient_id',user).order('created_at',ascending:false).limit(100);
  }
  return _stream!;
 }

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
   }else if(type=='scrapbook'){
     screen=ScrapbookStudioScreen(
      spaceId:item['space_id'].toString(),
      memoryId:item['object_id'].toString());
   }else if(type=='reminder'){
     screen=RemindersScreen(initialReminderId:item['object_id']?.toString());
   }else if(type=='task'){
     screen=PlansScreen(focusTaskId:item['object_id']?.toString());
   }else if(type=='note'){
     screen=NotesScreen(initialNoteId:item['object_id']?.toString());
   }else if(type=='occasion'){
     screen=OccasionsScreen(initialPlanId:(item['occasion_id']??item['object_id'])?.toString());
   }else if(type=='trip'){
     screen=TripsScreen(initialTripId:(item['trip_id']??item['object_id'])?.toString());
   }else if(type=='experience'){
     screen=SharedExperiencesScreen(initialExperienceId:
       (item['experience_id']??item['object_id'])?.toString());
   }else if(type=='letter'){
     screen=const CoupleLettersScreen();
   }else if(type=='checkin_request'){
     screen=CheckinsScreen(initialRequestId:item['object_id']?.toString());
   }else if(type=='checkin'){
     screen=const CheckinsScreen();
   }else if(type=='gesture'){
     await GestureNotificationDialog.show(context,
       item['object_id'].toString());
     return;
   }else{return;}
   Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>screen));
 }

 @override Widget build(BuildContext context){
   final userId=db.auth.currentUser?.id;
   if(userId==null)return const Scaffold(
     body:Center(child:Text('Sign in required')));
   return Scaffold(
     appBar:AppBar(title:const Text('Notifications'),actions:[
      PopupMenuButton<String>(
       tooltip:'Notification filters',
       icon:Icon(unreadOnly?Icons.filter_alt:Icons.filter_alt_outlined),
       initialValue:unreadOnly?'unread':'all',
       onSelected:(choice)=>setState(()=>unreadOnly=choice=='unread'),
       itemBuilder:(_)=>const [
        PopupMenuItem(value:'all',child:Text('All notifications')),
        PopupMenuItem(value:'unread',child:Text('Unread only')),
       ]),
     ]),
     body:StreamBuilder<List<Map<String,dynamic>>>(
       stream:_feed(userId),
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
             child:Wrap(spacing:8,runSpacing:4,
              alignment:WrapAlignment.spaceBetween,
              crossAxisAlignment:WrapCrossAlignment.center,children:[
               Text('Unread: $unread',
                 style:Theme.of(context).textTheme.labelLarge),
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
                     leading:kind=='gesture'&&item['object_id']!=null?
                       GestureNotificationIcon(
                         gestureId:item['object_id'].toString()):
                       Icon(kind=='reminder'&&item['object_kind']=='reminder'?Icons.alarm_outlined:
                       kind=='scrapbook_invite'?Icons.collections_bookmark_outlined:
                       kind=='mention'?Icons.alternate_email:
                       kind=='reply'?Icons.reply:
                       kind.startsWith('trip_')?Icons.flight_takeoff_outlined:
                       kind=='occasion_shared'?Icons.card_giftcard_outlined:
                       kind.startsWith('experience_')?Icons.movie_outlined:
                       kind=='letter'?Icons.mail_outline:
                       kind=='gesture'?Icons.favorite_border:
                       kind.startsWith('checkin_')?Icons.mark_chat_read_outlined:
                       Icons.event_outlined),
                     title:Text(item['headline']?.toString()??'Update',
                       style:TextStyle(fontWeight:unreadItem?
                         FontWeight.bold:FontWeight.normal)),
                     subtitle:Text(kind=='reminder'&&item['object_kind']=='reminder'?
                         'Open to complete, follow up, or snooze':
                       kind=='scrapbook_invite'?'Open to accept and create scrapbook pages together':
                       kind=='mention'?'Your partner mentioned you':
                       kind=='reply'?'Your partner replied':
                       kind=='letter'?'New letter':
                       kind=='gesture'?
                         (item['generated_automatically']==true
                           ?'Scheduled by your partner'
                           :'Personally sent by your partner'):
                       kind=='checkin_request'?'Your partner is checking on you':
                       kind=='checkin_response'?'Your partner replied':
                       kind=='checkin_shared'?'Your partner shared their feelings':
                       kind=='occasion_shared'?'Your partner planned an occasion':
                       kind=='trip_document'?'Your partner shared a travel document':
                       kind=='trip_suggestion'?'New shared trip':
                       kind=='trip_message'?'Your partner wrote about a trip':
                       kind=='experience_suggestion'?'New experience idea':
                       kind=='experience_comment'?'Your partner added a thought':
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
