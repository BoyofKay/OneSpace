import 'package:material_ui/material_ui.dart';

import 'today_attention_rules.dart';

class TodayAttentionSection extends StatefulWidget {
  const TodayAttentionSection({super.key, required this.items,
    required this.onOpen, required this.onSnooze,
    this.onOpenPlans,this.onOpenCheckins,this.onOpenReminder,this.loading=false,this.error,
    this.onRetry});
  final List<TodayAttentionItem> items;
  final void Function(String activityId) onOpen;
  final Future<void> Function(TodayAttentionItem item, int days) onSnooze;
  final VoidCallback? onOpenPlans;
  final VoidCallback? onOpenCheckins;
  final void Function(String reminderId)? onOpenReminder;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  @override State<TodayAttentionSection> createState() => _TodayAttentionSectionState();
}

class _TodayAttentionSectionState extends State<TodayAttentionSection> {
  bool showAll=false;
  @override Widget build(BuildContext context) {
    final items = widget.items;
    final now = DateTime.now();
    return TodaySectionCard(
      icon:Icons.notifications_active_outlined,
      title:'Needs your attention',
      count:items.isEmpty?null:items.length,
      children:[
        if(widget.loading&&items.isEmpty)const ListTile(
          leading:SizedBox(width:20,height:20,child:CircularProgressIndicator(
            strokeWidth:2)),
          title:Text('Checking for actions that need you…')),
        if(widget.error!=null)ListTile(
          leading:const Icon(Icons.error_outline),
          title:Text(widget.error!),
          trailing:TextButton(onPressed:widget.onRetry,
            child:const Text('Retry'))),
        if(items.isEmpty&&!widget.loading&&widget.error==null)
          const TodayEmptyHint('Nothing is waiting on you right now.'),
        for(final item in (showAll?items:items.take(6))) ListTile(
          dense:true,
          contentPadding:const EdgeInsets.symmetric(horizontal:4),
          leading:Icon(item.source=='checkin'?
            Icons.mark_chat_unread_outlined:
            item.source=='task'?Icons.checklist_outlined:
            item.kind=='mention'?Icons.alternate_email:
            item.isReminder?Icons.alarm_outlined:
            item.daysUntil(now)!=null&&item.daysUntil(now)!<0?
              Icons.error_outline:Icons.flag_outlined),
          title:Text(item.title,maxLines:2),
          subtitle:Text(item.reason??item.relativeLabel(now)),
          onTap:(){
            if(item.source=='reminder'){widget.onOpenReminder?.call(item.id);}
            else if(item.source=='checkin'){widget.onOpenCheckins?.call();}
            else if(item.source=='task'){widget.onOpenPlans?.call();}
            else if(item.activityId.isNotEmpty){widget.onOpen(item.activityId);}
          },
          trailing:PopupMenuButton<int>(
            tooltip:'Snooze for me',
            icon:const Icon(Icons.snooze_outlined,size:20),
            onSelected:(days)=>widget.onSnooze(item,days),
            itemBuilder:(_)=>const [
              PopupMenuItem(value:1,child:Text('Snooze until tomorrow')),
              PopupMenuItem(value:3,child:Text('Snooze for 3 days')),
              PopupMenuItem(value:7,child:Text('Snooze for 7 days')),
            ],
          ),
        ),
        if(items.length>6)TextButton(
          onPressed:()=>setState(()=>showAll=!showAll),
          child:Text(showAll?'Show fewer':'Show all ${items.length}')),
      ],
    );
  }
}

class TodayCalendarSection extends StatefulWidget {
 const TodayCalendarSection({super.key,required this.entries,required this.onOpen,
  this.onOpenActivity,this.onOpenExperience,this.onOpenTrip,this.onOpenOccasion,this.onOpenPlans,
  this.onOpenReminder});
 final List<TodayCalendarEntry> entries;
 final VoidCallback onOpen;
 final void Function(String id)? onOpenActivity;
 final void Function(String id)? onOpenExperience;
 final void Function(String id)? onOpenTrip;
 final void Function(String id)? onOpenOccasion;
 final VoidCallback? onOpenPlans;
 final void Function(String id)? onOpenReminder;
 @override State<TodayCalendarSection> createState()=>_TodayCalendarSectionState();
}
class _TodayCalendarSectionState extends State<TodayCalendarSection> {
 @override Widget build(BuildContext context) {
   final now=DateTime.now();
   final today=DateTime(now.year,now.month,now.day);
   final entries=[...widget.entries]..sort((x,y)=>x.date.compareTo(y.date));
   final todays=entries.where((e)=>!e.date.isAfter(today)).toList();
   final later=entries.where((e)=>e.date.isAfter(today)&&
     e.date.difference(today).inDays<=7).toList();
   final days=<DateTime,List<TodayCalendarEntry>>{};
   for(final e in later){
     days.putIfAbsent(DateTime(e.date.year,e.date.month,e.date.day),()=>[]).add(e);
   }
   final theme=Theme.of(context);
   return TodaySectionCard(
     icon:Icons.calendar_month_outlined,
     title:'Today and the next 7 days',
     trailing:IconButton(tooltip:'Open shared calendar',
       onPressed:widget.onOpen,icon:const Icon(Icons.open_in_new,size:20)),
     children:[
       if(entries.isEmpty)...[
         const TodayEmptyHint('A free day. Nothing planned for the next 7 days.'),
         Align(alignment:Alignment.centerLeft,child:TextButton.icon(
           onPressed:widget.onOpen,icon:const Icon(Icons.add),
           label:const Text('Add to the calendar'))),
       ]else...[
         Padding(padding:const EdgeInsets.fromLTRB(4,4,4,0),
           child:Text('Today',style:theme.textTheme.labelLarge)),
         if(todays.isEmpty)const TodayEmptyHint('Nothing planned for today.'),
         for(final entry in (showAllToday?todays:todays.take(3)))_row(entry),
         if(todays.length>3)TextButton(
           onPressed:()=>setState(()=>showAllToday=!showAllToday),
           child:Text(showAllToday?'Show fewer':'Show all ${todays.length} for today')),
         for(final day in days.keys)...[
           Padding(padding:const EdgeInsets.fromLTRB(4,10,4,0),
             child:Text(_dayLabel(day,today),style:theme.textTheme.labelLarge)),
           for(final entry in days[day]!)_row(entry),
         ],
       ],
     ],
   );
 }

 bool showAllToday=false;

 static String _dayLabel(DateTime day,DateTime today){
   const names=['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
   const months=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
   if(day.difference(today).inDays==1)return 'Tomorrow';
   return '${names[day.weekday-1]}, ${day.day} ${months[day.month-1]}';
 }

 Widget _row(TodayCalendarEntry entry){
   final overdue=entry.date.isBefore(DateTime(DateTime.now().year,
     DateTime.now().month,DateTime.now().day));
   return ListTile(
     dense:true,
     contentPadding:const EdgeInsets.symmetric(horizontal:4),
     leading:Icon(entry.kind=='occasion'?Icons.celebration_outlined:
       entry.source=='activity'?Icons.hub_outlined:
       entry.source.startsWith('occasion')?Icons.card_giftcard_outlined:
       entry.source=='trip'||entry.source=='trip_item'?Icons.flight_outlined:
       entry.source=='experience'?Icons.movie_outlined:
       entry.source=='todo'?Icons.checklist_outlined:
       entry.source=='component'||entry.source=='reminder'?Icons.alarm_outlined:
       Icons.event_outlined),
     title:Text(entry.title,maxLines:1,overflow:TextOverflow.ellipsis),
     subtitle:Text((overdue?'Overdue · ':'')+
       (entry.source.startsWith('occasion')?'Occasion':
        entry.source=='trip'?'Trip':entry.source=='trip_item'?'Trip item':
        entry.source=='experience'?'Together time':
        entry.source=='todo'?'To-do':entry.source=='activity'?'Activity':
        entry.source=='component'?'Activity item':
        entry.source=='reminder'?(entry.kind=='repeating_reminder'?'Repeating reminder':'Reminder'):
        'Calendar'),
       style:overdue?TextStyle(color:Theme.of(context).colorScheme.error):null),
     onTap:(){
       if(entry.reminderId!=null&&widget.onOpenReminder!=null){
         widget.onOpenReminder!(entry.reminderId!);
       }else if(entry.activityId!=null && widget.onOpenActivity!=null){
         widget.onOpenActivity!(entry.activityId!);
       }else if(entry.occasionId!=null&&widget.onOpenOccasion!=null){
         widget.onOpenOccasion!(entry.occasionId!);
       }else if(entry.tripId!=null&&widget.onOpenTrip!=null){
         widget.onOpenTrip!(entry.tripId!);
       }else if(entry.source=='experience'&&entry.experienceId!=null&&widget.onOpenExperience!=null){
         widget.onOpenExperience!(entry.experienceId!);
       }else if(entry.source=='todo'&&widget.onOpenPlans!=null){
         widget.onOpenPlans!();
       }else{widget.onOpen();}
     },
   );
 }
}

/// R49: every Today section is a card that is always present (spec 3.1).
class TodaySectionCard extends StatelessWidget {
  const TodaySectionCard({super.key,required this.icon,required this.title,
    required this.children,this.count,this.trailing});
  final IconData icon;
  final String title;
  final int? count;
  final Widget? trailing;
  final List<Widget> children;
  @override Widget build(BuildContext context){
    final theme=Theme.of(context);
    return Card(
      elevation:0,
      margin:const EdgeInsets.only(bottom:12),
      color:theme.colorScheme.surfaceContainerLow,
      child:Padding(
        padding:const EdgeInsets.fromLTRB(12,8,8,8),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Row(children:[
            Icon(icon,size:20,color:theme.colorScheme.primary),
            const SizedBox(width:8),
            Expanded(child:Text(count==null?title:'$title ($count)',
              style:theme.textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w700))),
            if(trailing!=null)trailing!,
          ]),
          const SizedBox(height:4),
          ...children,
        ]),
      ),
    );
  }
}

/// A short, kind line that keeps an empty section in place.
class TodayEmptyHint extends StatelessWidget {
  const TodayEmptyHint(this.text,{super.key});
  final String text;
  @override Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.fromLTRB(4,6,4,6),
    child:Text(text,style:Theme.of(context).textTheme.bodyMedium?.copyWith(
      color:Theme.of(context).colorScheme.onSurfaceVariant)));
}
