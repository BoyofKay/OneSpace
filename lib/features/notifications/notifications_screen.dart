import '../spaces/my_space_screen.dart';
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
import '../memories/memories_screen.dart';
import 'package:onespace/l10n/phrases.dart';
import 'notification_context.dart';
import '../places/places_screen.dart';
import '../counters/counters_screen.dart';
import '../../core/current_space_cache.dart';

/// One stable realtime subscription per signed-in account, not per frame.
class NotificationBell extends StatefulWidget {
 const NotificationBell({super.key});
 @override State<NotificationBell> createState()=>_NotificationBellState();
}
class _NotificationBellState extends State<NotificationBell> with WidgetsBindingObserver {
 final db=Supabase.instance.client;
 Stream<List<Map<String,dynamic>>>? _stream;
 String? _streamUser;
 // Notifications removed with a shared space (separation) arrive as deletes
 // the filtered live stream cannot see, so the count would stay stuck.
 // Re-read them whenever the pairing changes or the app comes back.
 void _refresh(){if(mounted)setState((){_stream=null;});}
 @override void initState(){
  super.initState();
  CurrentSpaceCache.paired.addListener(_refresh);
  WidgetsBinding.instance.addObserver(this);
 }
 @override void dispose(){
  CurrentSpaceCache.paired.removeListener(_refresh);
  WidgetsBinding.instance.removeObserver(this);
  super.dispose();
 }
 @override void didChangeAppLifecycleState(AppLifecycleState state){
  if(state==AppLifecycleState.resumed)_refresh();
 }
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
     tooltip:unread==0?tt('Notifications'):tt('Notifications, {} unread').replaceFirst('{}','$unread'),
     onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(
      builder:(_)=>const NotificationsScreen())),
     icon:Badge(isLabelVisible:unread>0,label:Text(tt(unread>99?'99+':'$unread')),
      child:const Icon(Icons.notifications_none_outlined)),
    );
   },
  );
 }
}

/// R48: one place that knows where every notification leads. Used by the
/// notification list and by tapping a push, so both open the exact item.
Future<void> openNotificationTarget(BuildContext context,
  Map<String,dynamic> item) async {
 final db=Supabase.instance.client;
 final userId=db.auth.currentUser?.id;
 if(userId==null)return;
 if(item['read_at']==null&&item['id']!=null){
   try{
     await db.from('space_notifications')
       .update({'read_at':DateTime.now().toUtc().toIso8601String()})
       .eq('id',item['id'].toString()).eq('recipient_id',userId);
   }catch(_){}
 }
 if(!context.mounted)return;
 final type=item['object_kind']?.toString()??'';
 final kind=item['kind']?.toString()??'';
 final objectId=item['object_id']?.toString();
 final Widget screen;
 if(type=='activity'){
   final id=(item['activity_id']??objectId)?.toString();
   if(id==null)return;
   screen=ActivityScreen(id:id,focusConversation:
     kind=='message'||kind=='mention'||kind=='reply');
 }else if(type=='calendar'){
   screen=CalendarScreen(initialEventId:
     (item['calendar_event_id']??objectId)?.toString());
 }else if(type=='scrapbook'){
   screen=ScrapbookStudioScreen(
    spaceId:item['space_id'].toString(),
    memoryId:(item['memory_id']??objectId).toString());
 }else if(type=='memory'){
   screen=MemoriesScreen(initialMemoryId:(item['memory_id']??objectId)?.toString());
 }else if(type=='reminder'){
   screen=RemindersScreen(initialReminderId:objectId);
 }else if(type=='task'){
   screen=PlansScreen(focusTaskId:objectId);
 }else if(type=='note'){
   screen=NotesScreen(initialNoteId:objectId);
 }else if(type=='occasion'){
   screen=OccasionsScreen(initialPlanId:(item['occasion_id']??objectId)?.toString());
 }else if(type=='trip'){
   screen=TripsScreen(initialTripId:(item['trip_id']??objectId)?.toString());
 }else if(type=='experience'){
   screen=SharedExperiencesScreen(initialExperienceId:
     (item['experience_id']??objectId)?.toString());
 }else if(type=='place'){
   screen=PlacesScreen(initialId:objectId);
 }else if(type=='counter'){
   screen=CountersScreen(initialId:objectId);
 }else if(type=='letter'){
   screen=const CoupleLettersScreen();
 }else if(type=='checkin_request'){
   screen=CheckinsScreen(initialRequestId:objectId);
 }else if(type=='checkin'){
   screen=const CheckinsScreen();
 }else if(type=='space'){
   screen=const MySpaceScreen();
 }else if(type=='gesture'){
   if(objectId==null)return;
   await GestureNotificationDialog.show(context,objectId);
   return;
 }else{
   screen=const NotificationsScreen();
 }
 await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>screen));
}

/// Opens the item behind a push. The push only carries the notification id;
/// the row is read under the signed-in user's own access rules.
Future<void> openNotificationById(BuildContext context,String? id,
  {bool summary=false}) async {
 if(summary||id==null||id.isEmpty){
   await Navigator.of(context).push(MaterialPageRoute<void>(
     builder:(_)=>const NotificationsScreen()));
   return;
 }
 Map<String,dynamic>? row;
 try{
   row=await Supabase.instance.client.from('space_notifications')
     .select().eq('id',id).maybeSingle();
 }catch(_){}
 if(!context.mounted)return;
 if(row==null){
   await Navigator.of(context).push(MaterialPageRoute<void>(
     builder:(_)=>const NotificationsScreen()));
   return;
 }
 await openNotificationTarget(context,row);
}

class NotificationsScreen extends StatefulWidget {
 const NotificationsScreen({super.key});
 @override State<NotificationsScreen> createState()=>_NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
 final db=Supabase.instance.client;
 String filter=NotificationCategories.all;
 bool saving=false;
 /// R75: live details per notification id ("Thu 20 Nov · 7:00 PM · Home").
 Map<String,NotificationContext> details={};
 String _detailsFor='';

 void _ensureDetails(List<Map<String,dynamic>> items){
   final key=items.map((n)=>n['id']).join(',');
   if(key==_detailsFor)return;
   _detailsFor=key;
   WidgetsBinding.instance.addPostFrameCallback((_) async {
     if(!mounted)return;
     final loaded=await loadNotificationContext(context,items);
     if(mounted&&_detailsFor==key)setState(()=>details=loaded);
   });
 }

 Future<void> _markRead(Map<String,dynamic> item,String userId) async {
   if(item['read_at']!=null||item['id']==null)return;
   try{
     await db.from('space_notifications')
       .update({'read_at':DateTime.now().toUtc().toIso8601String()})
       .eq('id',item['id'].toString()).eq('recipient_id',userId);
   }catch(_){}
 }
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
   await openNotificationTarget(context,item);
 }

 Widget _tile(Map<String,dynamic> item,String userId,ThemeData theme){
   final kind=item['kind']?.toString()??'';
   final unreadItem=item['read_at']==null;
   final title=tt((item['push_title']??item['headline'])?.toString()??'Update');
   final rawBody=(item['push_body']?.toString().trim().isNotEmpty??false)
     ?item['push_body'].toString():item['headline']?.toString()??'';
   final detail=(item['detail']??'').toString().trim();
   final body=[
     if(rawBody.isNotEmpty&&rawBody!=title)rawBody,
     if(detail.isNotEmpty&&detail!=rawBody)detail,
   ].join(' · ');
   final extra=details[item['id']?.toString()];
   final more=(item['batch_count'] as num?)?.toInt()??1;
   final color=theme.colorScheme.primary;
   return Dismissible(
     key:ValueKey('n-${item['id']}'),
     direction:unreadItem?DismissDirection.endToStart:DismissDirection.none,
     background:Container(color:theme.colorScheme.primaryContainer,
       alignment:AlignmentDirectional.centerEnd,padding:const EdgeInsets.symmetric(horizontal:20),
       child:Row(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.done),const SizedBox(width:6),Text(tt('Mark read'))])),
     confirmDismiss:(_) async {await _markRead(item,userId);return false;},
     child:Material(
       color:unreadItem?color.withValues(alpha:.06):Colors.transparent,
       child:InkWell(onTap:()=>_open(item,userId),child:Padding(
         padding:const EdgeInsetsDirectional.fromSTEB(16,10,12,10),
         child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
           kind=='gesture'&&item['object_id']!=null
             ?GestureNotificationIcon(gestureId:item['object_id'].toString())
             :CircleAvatar(radius:20,backgroundColor:color.withValues(alpha:.12),
               child:Icon(notificationIcon(item),color:color,size:20)),
           const SizedBox(width:12),
           Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
             Text(title,maxLines:2,overflow:TextOverflow.ellipsis,
               style:theme.textTheme.titleSmall?.copyWith(fontWeight:unreadItem?FontWeight.w700:FontWeight.w500)),
             if(body.isNotEmpty)Padding(padding:const EdgeInsets.only(top:2),
               child:Text(kind=='gesture'||kind=='message'||kind=='trip_message'||kind=='experience_comment'||kind=='reply'
                   ?'“${tt(body)}”':tt(body),
                 maxLines:3,overflow:TextOverflow.ellipsis,style:theme.textTheme.bodyMedium)),
             if(extra!=null&&extra.text.isNotEmpty)Padding(padding:const EdgeInsets.only(top:4),
               child:Row(children:[
                 Icon(extra.icon,size:15,color:theme.colorScheme.secondary),
                 const SizedBox(width:5),
                 Flexible(child:Text(extra.text,maxLines:2,overflow:TextOverflow.ellipsis,
                   style:theme.textTheme.bodySmall?.copyWith(color:theme.colorScheme.secondary))),
               ])),
             if(more>1)Padding(padding:const EdgeInsets.only(top:2),
               child:Text(tt('+{} more updates like this').replaceFirst('{}','${more-1}'),
                 style:theme.textTheme.bodySmall)),
           ])),
           const SizedBox(width:8),
           Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
             Text(tt(notificationAge(item['created_at'])),style:theme.textTheme.labelSmall),
             if(unreadItem)Padding(padding:const EdgeInsets.only(top:6),
               child:Icon(Icons.circle,size:9,color:color)),
           ]),
         ]))),
     ),
   );
 }

 @override Widget build(BuildContext context){
   final userId=db.auth.currentUser?.id;
   if(userId==null)return Scaffold(
     body:Center(child:Text(tt('Sign in required'))));
   return Scaffold(
     appBar:AppBar(title:Text(tt('Notifications'))),
     body:StreamBuilder<List<Map<String,dynamic>>>(
       stream:_feed(userId),
       builder:(context,snapshot){
         if(snapshot.hasError)return Center(
           child:Text(tt('Notifications are unavailable.')));
         if(!snapshot.hasData)return const Center(
           child:CircularProgressIndicator());
         final all=snapshot.data!;
         final unread=all.where((item)=>item['read_at']==null).length;
         final shown=all.where((n)=>NotificationCategories.matches(n,filter)).toList();
         _ensureDetails(all.take(60).toList());
         final theme=Theme.of(context);
         final rows=<Widget>[];
         String? lastDay;
         for(final item in shown){
           final day=notificationDay(item['created_at']);
           if(day!=lastDay){
             lastDay=day;
             rows.add(Padding(padding:const EdgeInsetsDirectional.fromSTEB(16,14,16,4),
               child:Text(tt(day),style:theme.textTheme.labelLarge?.copyWith(color:theme.colorScheme.primary))));
           }
           rows.add(_tile(item,userId,theme));
         }
         return Column(children:[
           SizedBox(height:52,child:ListView(scrollDirection:Axis.horizontal,
             padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),children:[
               for(final e in NotificationCategories.labels.entries)Padding(
                 padding:const EdgeInsetsDirectional.only(end:6),
                 child:ChoiceChip(
                   label:Text(e.key==NotificationCategories.unread&&unread>0
                     ?'${tt(e.value)} ($unread)':tt(e.value)),
                   selected:filter==e.key,
                   onSelected:(_)=>setState(()=>filter=e.key))),
             ])),
           if(unread>0)Align(alignment:AlignmentDirectional.centerEnd,child:TextButton.icon(
             onPressed:saving?null:()=>_markAllRead(userId),
             icon:const Icon(Icons.done_all),label:Text(tt('Mark all read')))),
           if(error!=null)Text(tt(error!),style:TextStyle(color:theme.colorScheme.error)),
           Expanded(
             child:shown.isEmpty
               ?Center(child:Text(tt(filter==NotificationCategories.unread?'No unread notifications.':'All caught up.')))
               :ListView(padding:const EdgeInsets.only(bottom:24),children:rows),
           ),
         ]);
       },
     ),
   );
 }
}

/// Icon for a notification row; follows the item type, then the action.
IconData notificationIcon(Map<String,dynamic> item){
 final kind=item['kind']?.toString()??'';
 final object=item['object_kind']?.toString()??'';
 final action=item['action']?.toString()??'';
 if(kind=='change'){
   if(action=='removed')return Icons.delete_outline;
   if(action=='restored')return Icons.restore;
   if(action=='moved')return Icons.event_repeat_outlined;
   if(action=='assigned')return Icons.assignment_ind_outlined;
   if(action=='cancelled')return Icons.cancel_outlined;
   return Icons.check_circle_outline;
 }
 if(kind=='message'||kind=='trip_message'||kind=='experience_comment'){
   return Icons.chat_bubble_outline;
 }
 if(kind=='joined')return Icons.people_outline;
 if(kind=='mention')return Icons.alternate_email;
 if(kind=='reply')return Icons.reply;
 if(kind=='letter')return Icons.mail_outline;
 if(kind=='gesture')return Icons.favorite_border;
 if(kind=='scrapbook_invite')return Icons.collections_bookmark_outlined;
 if(kind.startsWith('checkin_'))return Icons.mark_chat_read_outlined;
 switch(object){
   case 'reminder': return Icons.alarm_outlined;
   case 'task': return Icons.checklist_outlined;
   case 'activity': return Icons.forum_outlined;
   case 'memory': case 'scrapbook': return Icons.photo_album_outlined;
   case 'trip': return Icons.flight_takeoff_outlined;
   case 'occasion': return Icons.card_giftcard_outlined;
   case 'experience': return Icons.movie_outlined;
   case 'place': return Icons.place_outlined;
   case 'counter': return Icons.hourglass_bottom_rounded;
 }
 return Icons.event_outlined;
}

/// "Just now", "5 min ago", "3 h ago", "Yesterday", "4 days ago", or a date.
String notificationAge(Object? raw,{DateTime? now}){
 final at=DateTime.tryParse(raw?.toString()??'')?.toLocal();
 if(at==null)return '';
 final current=now??DateTime.now();
 final gap=current.difference(at);
 if(gap.inMinutes<1)return 'Just now';
 if(gap.inMinutes<60)return '${gap.inMinutes} min ago';
 if(gap.inHours<24)return '${gap.inHours} h ago';
 final days=DateTime(current.year,current.month,current.day)
   .difference(DateTime(at.year,at.month,at.day)).inDays;
 if(days==1)return 'Yesterday';
 if(days<7)return '$days days ago';
 return '${at.day}/${at.month}/${at.year}';
}
