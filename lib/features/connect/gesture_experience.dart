import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/current_space_cache.dart';

class GestureTheme {
 const GestureTheme(this.icon,this.color,this.title);
 final IconData icon;
 final Color color;
 final String title;
 static GestureTheme forKind(String? kind){
   switch(kind){
     case 'hug':return const GestureTheme(Icons.volunteer_activism_outlined,Color(0xFFE77992),'A warm hug');
     case 'thinking':return const GestureTheme(Icons.favorite_border,Color(0xFF9977D7),'On my mind');
     case 'smile':return const GestureTheme(Icons.sentiment_satisfied_alt,Color(0xFFE5A440),'A smile for you');
     case 'morning':return const GestureTheme(Icons.wb_sunny_outlined,Color(0xFFD99242),'Good morning');
     case 'goodnight':return const GestureTheme(Icons.nightlight_round,Color(0xFF7382C7),'Sweet dreams');
     case 'proud':return const GestureTheme(Icons.auto_awesome_outlined,Color(0xFF409F8B),'Proud of you');
     default:return const GestureTheme(Icons.favorite_outline,Color(0xFF518FB7),'Here for you');
   }
 }
}

class GestureHistoryScreen extends StatefulWidget {
 const GestureHistoryScreen({super.key});
 @override State<GestureHistoryScreen> createState()=>_GestureHistoryScreenState();
}
class _GestureHistoryScreenState extends State<GestureHistoryScreen>{
 String tab='received';
 String? space;
 @override void initState(){
   super.initState();
   CurrentSpaceCache.instance.get().then((id){
     if(mounted)setState(()=>space=id);
   });
 }
 @override Widget build(BuildContext context){
   final me=Supabase.instance.client.auth.currentUser?.id;
   return Scaffold(
     appBar:AppBar(title:const Text('Our gestures')),
     body:Column(children:[
       Padding(padding:const EdgeInsets.all(12),child:SegmentedButton<String>(
         segments:const [
           ButtonSegment(value:'received',label:Text('Received'),icon:Icon(Icons.favorite_outline)),
           ButtonSegment(value:'sent',label:Text('Sent'),icon:Icon(Icons.outgoing_mail)),
         ],
         selected:{tab},onSelectionChanged:(v)=>setState(()=>tab=v.first),
       )),
       Expanded(child:space==null||me==null?
         const Center(child:CircularProgressIndicator()):
         StreamBuilder<List<Map<String,dynamic>>>(
           stream:Supabase.instance.client.from('partner_gestures')
             .stream(primaryKey:['id']).eq('space_id',space!)
             .order('created_at',ascending:false).limit(100),
           builder:(ctx,s){
             if(s.hasError)return const Center(child:Text('Unable to load gesture history'));
             if(!s.hasData)return const Center(child:CircularProgressIndicator());
             final items=s.data!.where((item)=>tab=='sent'?
               item['sender_id']==me:item['recipient_id']==me).toList();
             if(items.isEmpty)return Center(child:Text('No '+tab+' gestures yet.'));
             return ListView.builder(itemCount:items.length,itemBuilder:(ctx,i){
               final item=items[i];
               final style=GestureTheme.forKind(item['kind']?.toString());
               return Card(elevation:0,margin:const EdgeInsets.fromLTRB(12,4,12,6),
                 child:ListTile(
                   leading:CircleAvatar(
                     backgroundColor:style.color.withValues(alpha:.16),
                     child:Icon(style.icon,color:style.color)),
                   title:Text(item['message']?.toString()??''),
                   subtitle:Text(item['automated']==true?
                     'Scheduled automatically':'Sent personally'),
                 ));
             });
           },
         ),
       ),
     ]),
   );
 }
}

/// Theming and message are loaded by ID under the signed-in recipient's RLS.
class GestureNotificationDialog {
 const GestureNotificationDialog._();
 static Future<void> show(BuildContext context,String gestureId) async {
   try{
     final row=await Supabase.instance.client.from('partner_gestures')
       .select('kind,message,automated')
       .eq('id',gestureId).single();
     if(!context.mounted)return;
     final theme=GestureTheme.forKind(row['kind']?.toString());
     await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
       icon:CircleAvatar(radius:34,
         backgroundColor:theme.color.withValues(alpha:.16),
         child:Icon(theme.icon,size:36,color:theme.color)),
       title:Text(theme.title,textAlign:TextAlign.center),
       content:Column(mainAxisSize:MainAxisSize.min,children:[
         Text(row['message']?.toString()??'',textAlign:TextAlign.center,
           style:Theme.of(ctx).textTheme.titleMedium),
         const SizedBox(height:12),
         Text(row['automated']==true?'A scheduled gesture from your love':
           'A personal gesture from your love',
           style:Theme.of(ctx).textTheme.bodySmall,
           textAlign:TextAlign.center),
       ]),
       actions:[FilledButton(onPressed:()=>Navigator.pop(ctx),
         child:const Text('Close'))],
     ));
   }catch(_){
     if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content:Text('This gesture is no longer available.')));
   }
 }
}
