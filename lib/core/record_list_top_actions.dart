import 'package:material_ui/material_ui.dart';

/// Consistent action placement for record collections.
///
/// The history button exposes archived records without erasing their data.
/// Filters belong in a top action sheet, not in the middle of content.
/// Feature-specific privacy and status decisions still belong to each screen.
class RecordListTopActions extends StatelessWidget{
 const RecordListTopActions({super.key,
  required this.showHistory,required this.onToggleHistory,
  this.filters,this.hasActiveFilters=false});
 final bool showHistory;
 final VoidCallback onToggleHistory;
 final WidgetBuilder? filters;
 final bool hasActiveFilters;

 @override Widget build(BuildContext context)=>Row(
  mainAxisSize:MainAxisSize.min,children:[
   IconButton(
    tooltip:showHistory?'Hide archived history':'Show archived history',
    icon:Icon(showHistory?
     Icons.history_toggle_off_outlined:Icons.history_outlined),
    onPressed:onToggleHistory),
   if(filters!=null)IconButton(
    tooltip:hasActiveFilters?'Filters (active)':'Filters',
    icon:Icon(hasActiveFilters?
      Icons.filter_alt:Icons.filter_alt_outlined),
    onPressed:()=>showModalBottomSheet<void>(
     context:context,showDragHandle:true,isScrollControlled:true,
     builder:(ctx)=>SafeArea(child:Padding(
      padding:const EdgeInsets.fromLTRB(16,8,16,24),
      child:Column(mainAxisSize:MainAxisSize.min,
       crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Filters',style:Theme.of(ctx).textTheme.titleLarge),
        const SizedBox(height:12),
        filters!(ctx),
       ])))),
   ),
  ]);
}
