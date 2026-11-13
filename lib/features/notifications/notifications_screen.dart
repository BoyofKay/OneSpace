import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../coordinate/activity_detail_screen.dart';
import '../calendar/calendar_screen.dart';
import '../connect/couple_letters_screen.dart';

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

class NotificationsScreen extends StatelessWidget {
 const NotificationsScreen({super.key});
 @override Widget build(BuildContext context) {
  final db=Supabase.instance.client;
  final user=db.auth.currentUser?.id;
  if(user==null)return const Scaffold(body:Center(child:Text('Sign in required')));
  return Scaffold(
   appBar:AppBar(title:const Text('Notifications')),
   body:StreamBuilder<List<Map<String,dynamic>>>(
    stream:db.from('space_notifications').stream(primaryKey:['id'])
     .eq('recipient_id',user).order('created_at',ascending:false).limit(100),
    builder:(context,snapshot){
     if(snapshot.hasError)return const Center(child:Text('Notifications unavailable'));
     if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
     final items=snapshot.data!;
     if(items.isEmpty)return const Center(child:Text('All caught up.'));
     return ListView.builder(itemCount:items.length,itemBuilder:(context,index){
      final row=items[index];
      final kind=row['kind']?.toString()??'';
      final unread=row['read_at']==null;
      return ListTile(
       leading:Icon(kind=='mention'?Icons.alternate_email:
          kind=='reply'?Icons.reply:
          kind=='letter'?Icons.mail_outline:Icons.event_outlined),
       title:Text(row['headline']?.toString()??'Update',
         style:TextStyle(fontWeight:unread?FontWeight.bold:FontWeight.normal)),
       subtitle:Text(kind=='mention'?'Mentioned you':
          kind=='reply'?'Replied to you':
          kind=='letter'?'New letter':'Shared event'),
       trailing:unread?const Icon(Icons.circle,size:8):null,
       onTap:() async {
        if(unread){
         try{
          await db.from('space_notifications').update({
           'read_at':DateTime.now().toUtc().toIso8601String(),
          }).eq('id',row['id'].toString()).eq('recipient_id',user);
         }catch(_){}
        }
        if(!context.mounted)return;
        final object=row['object_kind']?.toString()??'';
        final Widget target;
        if(object=='activity'){
         target=ActivityScreen(id:row['activity_id'].toString());
        }else if(object=='calendar'){
         target=CalendarScreen(initialEventId:row['object_id']?.toString());
        }else if(object=='letter'){
         target=const CoupleLettersScreen();
        }else{return;}
        Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>target));
       },
      );
     });
    },
   ),
  );
 }
}
