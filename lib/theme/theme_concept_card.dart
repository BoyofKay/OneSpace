import 'package:material_ui/material_ui.dart';
import 'onespace_appearance.dart';
import 'package:onespace/l10n/phrases.dart';

/// The selector previews a real composition, not a single palette circle.
class ThemeConceptCard extends StatelessWidget{
 const ThemeConceptCard({super.key,required this.palette,
  required this.selected,required this.onTap,required this.label});
 final OneSpacePalette palette;
 final bool selected;
 final VoidCallback onTap;
 final String label;
 @override Widget build(BuildContext context){
  final dark=palette==OneSpacePalette.midnightBlue||
    palette==OneSpacePalette.monochrome;
  final primary=OneSpaceAppearance.paletteSeed(palette);
  final base=OneSpaceAppearance.paletteCanvas(palette,dark).$1;
  final surface=dark?Color.alphaBlend(Colors.white.withValues(alpha:.07),base)
    :Colors.white;
  final ink=dark?Colors.white:const Color(0xFF243044);
  final border=dark?Colors.white.withValues(alpha:.12):primary.withValues(alpha:.13);
  return Semantics(button:true,selected:selected,label:label,
   child:InkWell(onTap:onTap,borderRadius:BorderRadius.circular(20),
    child:AnimatedContainer(duration:const Duration(milliseconds:220),
     decoration:BoxDecoration(borderRadius:BorderRadius.circular(20),
      border:Border.all(color:selected?Theme.of(context).colorScheme.primary:
       Theme.of(context).colorScheme.outlineVariant,width:selected?2.5:1)),
     padding:const EdgeInsets.all(9),
     child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      AspectRatio(aspectRatio:.78,child:ClipRRect( // R80: taller so small phones (≤384 dp) don’t overflow
       borderRadius:BorderRadius.circular(15),
       child:ColoredBox(color:base,child:Padding(
        padding:const EdgeInsets.all(10),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
         Row(children:[
          Icon(Icons.favorite_rounded,color:primary,size:16),
          const Spacer(),
          Icon(Icons.notifications_outlined,color:ink,size:13),
          const SizedBox(width:7),
          CircleAvatar(radius:8,backgroundColor:primary),
         ]),
         const SizedBox(height:12),
         Text(tt('Our space'),style:TextStyle(
          color:ink,fontSize:13,fontWeight:FontWeight.w800)),
         const SizedBox(height:8),
         Expanded(flex:4,child:Container(
          padding:const EdgeInsets.all(9),
          decoration:BoxDecoration(borderRadius:BorderRadius.circular(12),
           gradient:LinearGradient(colors:[
            primary.withValues(alpha:dark ? .60 : .19),
            surface,
           ])),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
           Icon(Icons.auto_awesome_rounded,color:primary,size:19),
           const Spacer(),
           Text(tt('One life, two places'),style:TextStyle(color:ink,
            fontSize:9,fontWeight:FontWeight.w700)),
           Container(margin:const EdgeInsets.only(top:5),height:4,width:68,
            decoration:BoxDecoration(color:primary.withValues(alpha:.55),
             borderRadius:BorderRadius.circular(3))),
          ]),
         )),
         const SizedBox(height:7),
         Expanded(flex:2,child:Row(children:[
          for(final icon in [Icons.event_available_outlined,
            Icons.card_giftcard_outlined])...[
           Expanded(child:Container(margin:const EdgeInsetsDirectional.only(end:5),
            decoration:BoxDecoration(
             color:surface,borderRadius:BorderRadius.circular(9),
             border:Border.all(color:border)),
            child:Center(child:Icon(icon,size:17,color:primary)))),
          ],
         ])),
         const SizedBox(height:9),
         Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[
          for(final icon in [Icons.today_outlined,
           Icons.bookmark_border,Icons.favorite_border,Icons.public_outlined])
           Icon(icon,size:14,color:ink.withValues(alpha:.75)),
         ]),
        ]),
       )),
      )),
      const SizedBox(height:9),
      Row(children:[
       Expanded(child:Text(tt(label),maxLines:1,overflow:TextOverflow.ellipsis,
        style:Theme.of(context).textTheme.labelLarge)),
       Icon(selected?Icons.check_circle_rounded:Icons.circle_outlined,
        color:selected?Theme.of(context).colorScheme.primary:
         Theme.of(context).colorScheme.outline,size:19),
      ]),
     ]),
    ),
   ));
 }
}
