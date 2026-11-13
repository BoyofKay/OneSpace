import 'package:material_ui/material_ui.dart';

/// A compact pair of fields which becomes a vertical stack for narrow phones
/// or when the user has increased Android's text size.
class ResponsiveFieldPair extends StatelessWidget {
 const ResponsiveFieldPair({
  super.key,required this.first,required this.second,
  this.firstFlex=2,this.breakpoint=410,this.spacing=10,
 });
 final Widget first,second;
 final int firstFlex;
 final double breakpoint,spacing;

 @override Widget build(BuildContext context) {
  final scale=MediaQuery.textScalerOf(context).scale(16)/16;
  return LayoutBuilder(builder:(context,constraints){
   final stacked=constraints.maxWidth<breakpoint*scale;
   if(stacked){
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
     first,SizedBox(height:spacing),second,
    ]);
   }
   return Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Expanded(flex:firstFlex,child:first),
    SizedBox(width:spacing),
    Expanded(child:second),
   ]);
  });
 }
}
