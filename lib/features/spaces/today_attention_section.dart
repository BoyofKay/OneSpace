import 'package:material_ui/material_ui.dart';

import '../calendar/calendar_rules.dart';
import 'today_attention_rules.dart';

class TodayAttentionSection extends StatefulWidget {
  const TodayAttentionSection({super.key, required this.items,
    required this.onOpen, required this.onSnooze,
    this.onOpenPlans,this.onOpenCheckins,this.loading=false,this.error,
    this.onRetry});
  final List<TodayAttentionItem> items;
  final void Function(String activityId) onOpen;
  final Future<void> Function(TodayAttentionItem item, int days) onSnooze;
  final VoidCallback? onOpenPlans;
  final VoidCallback? onOpenCheckins;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  @override State<TodayAttentionSection> createState() => _TodayAttentionSectionState();
}

class _TodayAttentionSectionState extends State<TodayAttentionSection> {
  bool expanded = false;
  bool showAll=false;
  @override Widget build(BuildContext context) {
    final items = widget.items;
    final now = DateTime.now();
    return ExpansionTile(
      tilePadding:EdgeInsets.zero,
      initiallyExpanded:false,
      onExpansionChanged:(v)=>setState(()=>expanded=v),
      leading:const Icon(Icons.notifications_active_outlined),
      title:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Needs attention ('+items.length.toString()+')',
          style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17)),
        if(!expanded)Text(items.isEmpty?'All clear right now':
          'Overdue, urgent and items requiring action',
          style:Theme.of(context).textTheme.bodySmall),
      ]),
      childrenPadding:const EdgeInsets.fromLTRB(8,0,8,10),
      children:[
        if(widget.loading)const ListTile(
          leading:SizedBox(width:20,height:20,child:CircularProgressIndicator(
            strokeWidth:2)),
          title:Text('Checking for actions that need you…')),
        if(widget.error!=null)ListTile(
          leading:const Icon(Icons.error_outline),
          title:Text(widget.error!),
          trailing:TextButton(onPressed:widget.onRetry,
            child:const Text('Retry'))),
        if(items.isEmpty&&!widget.loading&&widget.error==null)
          const ListTile(title:Text('All clear. Nothing needs your action.')),
        for(final item in (showAll?items:items.take(6))) ListTile(
          dense:true,
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
            if(item.source=='checkin')widget.onOpenCheckins?.call();
            else if(item.source=='task')widget.onOpenPlans?.call();
            else if(item.activityId.isNotEmpty)widget.onOpen(item.activityId);
          },
          trailing:PopupMenuButton<int>(
            tooltip:'Snooze for me',
            onSelected:(days)=>widget.onSnooze(item,days),
            itemBuilder:(_)=>const [
              PopupMenuItem(value:1,child:Text('Until tomorrow')),
              PopupMenuItem(value:3,child:Text('For 3 days')),
              PopupMenuItem(value:7,child:Text('For 7 days')),
            ],
          ),
        ),
        if(items.length>6)ListTile(
          title:Text(showAll?'Show fewer actions':
            'Show all ${items.length} actions'),
          trailing:Icon(showAll?Icons.expand_less:Icons.expand_more),
          onTap:()=>setState(()=>showAll=!showAll),
        ),
      ],
    );
  }
}

class TodayCalendarSection extends StatefulWidget {
 const TodayCalendarSection({super.key,required this.entries,required this.onOpen,
  this.onOpenActivity,this.onOpenPlans});
 final List<TodayCalendarEntry> entries;
 final VoidCallback onOpen;
 final void Function(String id)? onOpenActivity;
 final VoidCallback? onOpenPlans;
 @override State<TodayCalendarSection> createState()=>_TodayCalendarSectionState();
}
class _TodayCalendarSectionState extends State<TodayCalendarSection> {
 bool expanded=false;
 @override Widget build(BuildContext context) {
   final entries=widget.entries;
   return ExpansionTile(
     tilePadding:EdgeInsets.zero,
     initiallyExpanded:false,
     onExpansionChanged:(value)=>setState(()=>expanded=value),
     leading:const Icon(Icons.calendar_month_outlined),
     title:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Text('Coming up together ('+entries.length.toString()+')',
         style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17)),
       if(!expanded)Text(entries.isEmpty?'Nothing scheduled for the coming week':
         'Next 7 days · events, appointments and deadlines',
         style:Theme.of(context).textTheme.bodySmall),
     ]),
     childrenPadding:const EdgeInsets.fromLTRB(8,0,8,10),
     children:[
       if(entries.isEmpty)const ListTile(title:Text('Nothing scheduled in the next 7 days.')),
       for(final entry in entries.take(5)) ListTile(
         dense:true,
         leading:Icon(entry.kind=='occasion'?Icons.celebration_outlined:
           entry.source=='activity'?Icons.hub_outlined:
           entry.source=='todo'?Icons.checklist_outlined:
           entry.source=='component'?Icons.alarm_outlined:
           Icons.event_outlined),
         title:Text(entry.title,maxLines:1,overflow:TextOverflow.ellipsis),
         subtitle:Text(CalendarRules.sqlDate(entry.date)+' · '+
           (entry.source=='todo'?'To-do':entry.source=='activity'?'Activity':
             entry.source=='component'?'Activity item':'Calendar')),
         onTap:(){
           if(entry.activityId!=null && widget.onOpenActivity!=null){
             widget.onOpenActivity!(entry.activityId!);
           }else if(entry.source=='todo'&&widget.onOpenPlans!=null){
             widget.onOpenPlans!();
           }else{widget.onOpen();}
         },
       ),
       TextButton.icon(onPressed:widget.onOpen,
         icon:const Icon(Icons.open_in_new),
         label:const Text('Open shared calendar')),
     ],
   );
 }
}
