import 'package:material_ui/material_ui.dart';
import 'onespace_appearance.dart';

class AppearanceSettingsScreen extends StatelessWidget{
 const AppearanceSettingsScreen({super.key});
 @override Widget build(BuildContext context){
  final state=OneSpaceAppearance.instance;
  return Scaffold(
   appBar:AppBar(title:const Text('Appearance & themes')),
   body:SafeArea(child:AnimatedBuilder(animation:state,builder:(context,_) {
    final theme=Theme.of(context),scheme=theme.colorScheme;
    final width=MediaQuery.sizeOf(context).width;
    return ListView(padding:EdgeInsets.symmetric(
     horizontal:width>720?mathMax(20,(width-660)/2):16,vertical:16),children:[
     Text('Make OneSpace yours',style:theme.textTheme.headlineSmall),
     const SizedBox(height:6),
     const Text('Themes belong to this phone. Each partner can have a different look without changing shared content.'),
     const SizedBox(height:24),
     Text('Color collection',style:theme.textTheme.titleLarge),
     const SizedBox(height:10),
     LayoutBuilder(builder:(ctx,box){
      final columns=box.maxWidth>=500?4:2;
      final tile=(box.maxWidth-12*(columns-1))/columns;
      return Wrap(spacing:12,runSpacing:12,children:[
       for(final p in OneSpacePalette.values)
        SizedBox(width:tile,child:Semantics(
         selected:state.palette==p,
         label:OneSpaceAppearance.paletteName(p),
         button:true,
         child:InkWell(
          borderRadius:BorderRadius.circular(18),
          onTap:()=>state.setPalette(p),
          child:Container(
           padding:const EdgeInsets.all(12),
           decoration:BoxDecoration(
            borderRadius:BorderRadius.circular(18),
            color:scheme.surface,
            border:Border.all(
             width:state.palette==p?2.3:1,
             color:state.palette==p?scheme.primary:scheme.outlineVariant)),
           child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[
             CircleAvatar(radius:14,backgroundColor:OneSpaceAppearance.paletteSeed(p)),
             const Spacer(),
             if(state.palette==p)Icon(Icons.check_circle,size:19,color:scheme.primary)
             else const Icon(Icons.circle_outlined,size:19),
            ]),
            const SizedBox(height:16),
            Text(OneSpaceAppearance.paletteName(p),
             maxLines:2,overflow:TextOverflow.ellipsis,
             style:theme.textTheme.labelLarge),
           ]),
          ),
         ))),
      ]);
     }),
     const SizedBox(height:24),
     Text('Brightness',style:theme.textTheme.titleLarge),
     const SizedBox(height:8),
     LayoutBuilder(builder:(ctx,box){
      if(box.maxWidth<390){
       return Wrap(spacing:8,runSpacing:8,children:[
        for(final item in const [
         (ThemeMode.system,'Phone',Icons.brightness_auto_outlined),
         (ThemeMode.light,'Light',Icons.light_mode_outlined),
         (ThemeMode.dark,'Dark',Icons.dark_mode_outlined),
        ])ChoiceChip(
         avatar:Icon(item.$3,size:18),
         label:Text(item.$2),
         selected:state.mode==item.$1,
         onSelected:(_)=>state.setMode(item.$1)),
       ]);
      }
      return SegmentedButton<ThemeMode>(
       showSelectedIcon:true,
       segments:const [
        ButtonSegment(value:ThemeMode.system,icon:Icon(Icons.brightness_auto_outlined),
         label:Text('Phone')),
        ButtonSegment(value:ThemeMode.light,icon:Icon(Icons.light_mode_outlined),
         label:Text('Light')),
        ButtonSegment(value:ThemeMode.dark,icon:Icon(Icons.dark_mode_outlined),
         label:Text('Dark')),
       ],
       selected:{state.mode},
       onSelectionChanged:(value)=>state.setMode(value.first));
     }),
     const SizedBox(height:8),
     Text('Phone follows the device setting, including automatic dark mode.',
      style:theme.textTheme.bodySmall),
     const SizedBox(height:24),
     Text('Seasonal celebrations',style:theme.textTheme.titleLarge),
     const SizedBox(height:6),
     const Text('Subtle holiday colors and icons—not flashing effects. Turn them off or preview any season.'),
     const SizedBox(height:10),
     DropdownButtonFormField<SeasonChoice>(
      initialValue:state.season,
      decoration:const InputDecoration(prefixIcon:Icon(Icons.auto_awesome_outlined),
       labelText:'Seasonal appearance'),
      items:[for(final choice in SeasonChoice.values)
       DropdownMenuItem(value:choice,child:Text(OneSpaceAppearance.seasonName(choice)))],
      onChanged:(value){if(value!=null)state.setSeason(value);}),
     const SizedBox(height:14),
     const SeasonalThemePreview(),
     const SizedBox(height:20),
     Text('Designed for comfort',style:theme.textTheme.titleMedium),
     const SizedBox(height:8),
     const Text('Responsive layouts, Material touch targets, clear content hierarchy and readable contrast. Decorative motion follows the phone’s reduced-motion setting.'),
    ]);
   })),
  );
 }
 static double mathMax(double a,double b)=>a>b?a:b;
}

class SeasonalThemePreview extends StatelessWidget{
 const SeasonalThemePreview({super.key,this.compact=false});
 final bool compact;
 @override Widget build(BuildContext context){
  return AnimatedBuilder(animation:OneSpaceAppearance.instance,
   builder:(ctx,_){
    final state=OneSpaceAppearance.instance;
    final effective=OneSpaceAppearance.effectiveSeason(state.season,DateTime.now());
    if(effective==SeasonChoice.off&&compact)return const SizedBox.shrink();
    final scheme=Theme.of(ctx).colorScheme;
    final accent=OneSpaceAppearance.seasonAccent(effective)??scheme.primary;
    final (icon,title,subtitle)=switch(effective){
     SeasonChoice.valentines=>(Icons.favorite_rounded,'A little extra love',"A season for thoughtful gestures"),
     SeasonChoice.spring=>(Icons.local_florist_outlined,'A fresh chapter','Small moments, new memories'),
     SeasonChoice.halloween=>(Icons.nights_stay_outlined,'Spooky season','Make room for playful memories'),
     SeasonChoice.winter=>(Icons.ac_unit_rounded,'Warm wishes','Celebrate your moments together'),
     _=>(Icons.palette_outlined,'Your OneSpace','One life, two places'),
    };
    final reduced=MediaQuery.disableAnimationsOf(ctx);
    final card=Container(
     padding:EdgeInsets.symmetric(horizontal:16,vertical:compact?12:18),
     decoration:BoxDecoration(
      borderRadius:BorderRadius.circular(20),
      gradient:LinearGradient(colors:[
       Color.alphaBlend(accent.withValues(alpha:.14),scheme.surface),
       Color.alphaBlend(accent.withValues(alpha:.035),scheme.surface),
      ]),
      border:Border.all(color:accent.withValues(alpha:.32)),
     ),
     child:Row(children:[
      CircleAvatar(radius:compact?21:25,backgroundColor:accent.withValues(alpha:.17),
       child:Icon(icon,color:accent,size:compact?23:27)),
      const SizedBox(width:13),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Text(title,style:Theme.of(ctx).textTheme.titleMedium),
       Text(subtitle,style:Theme.of(ctx).textTheme.bodySmall),
      ])),
     ]),
    );
    return AnimatedSwitcher(
     duration:reduced?Duration.zero:const Duration(milliseconds:280),
     child:KeyedSubtree(key:ValueKey(effective),child:card),
    );
   });
 }
}
