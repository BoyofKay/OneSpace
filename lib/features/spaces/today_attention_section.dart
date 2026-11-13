import 'package:material_ui/material_ui.dart';

import '../calendar/calendar_rules.dart';
import 'today_attention_rules.dart';

class TodayAttentionSection extends StatefulWidget {
  const TodayAttentionSection({super.key, required this.items,
    required this.onOpen, required this.onSnooze});
  final List<TodayAttentionItem> items;
  final void Function(String activityId) onOpen;
  final Future<void> Function(TodayAttentionItem item, int days) onSnooze;
  @override State<TodayAttentionSection> createState() => _TodayAttentionSectionState();
}

class _TodayAttentionSectionState extends State<TodayAttentionSection> {
  bool expanded = true;
  @override Widget build(BuildContext context) {
    final items = widget.items;
    final now = DateTime.now();
    return ExpansionTile(
      initiallyExpanded:true,
      onExpansionChanged:(v)=>setState(()=>expanded=v),
      leading:const Icon(Icons.notifications_active_outlined),
      title: Text('Needs attention (${items.length})'),
      childrenPadding:const EdgeInsets.fromLTRB(8,0,8,10),
      children:[
        if(items.isEmpty) const ListTile(
          title:Text('Nothing needs attention right now.')),
        for(final item in items.take(6)) ListTile(
          dense:true,
          leading:Icon(item.isReminder ? Icons.alarm_outlined :
            item.daysUntil(now) != null && item.daysUntil(now)! < 0
              ? Icons.error_outline : Icons.flag_outlined),
          title:Text(item.title,maxLines:2),
          subtitle:Text(item.relativeLabel(now)),
          onTap:()=>widget.onOpen(item.activityId),
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
        if(items.length>6) ListTile(
          title:Text('And ${items.length-6} more.'),
          trailing:const Icon(Icons.chevron_right),
          onTap:()=>widget.onOpen(items[6].activityId),
        ),
      ],
    );
  }
}

class TodayCalendarSection extends StatefulWidget {
 const TodayCalendarSection({super.key,required this.entries,required this.onOpen});
 final List<TodayCalendarEntry> entries;
 final VoidCallback onOpen;
 @override State<TodayCalendarSection> createState()=>_TodayCalendarSectionState();
}
class _TodayCalendarSectionState extends State<TodayCalendarSection> {
 @override Widget build(BuildContext context) {
   final entries=widget.entries;
   return ExpansionTile(
     initiallyExpanded:true,
     leading:const Icon(Icons.calendar_month_outlined),
     title:Text('Coming up together (${entries.length})'),
     childrenPadding:const EdgeInsets.fromLTRB(8,0,8,10),
     children:[
       if(entries.isEmpty)const ListTile(title:Text('Nothing scheduled in the next 7 days.')),
       for(final entry in entries.take(5)) ListTile(
         dense:true,
         leading:Icon(entry.kind=='occasion'?Icons.celebration_outlined:Icons.event_outlined),
         title:Text(entry.title,maxLines:1,overflow:TextOverflow.ellipsis),
         subtitle:Text(CalendarRules.sqlDate(entry.date)),
         onTap:widget.onOpen,
       ),
       TextButton.icon(onPressed:widget.onOpen,
         icon:const Icon(Icons.open_in_new),
         label:const Text('Open shared calendar')),
     ],
   );
 }
}
