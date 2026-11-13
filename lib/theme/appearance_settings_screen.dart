import 'package:material_ui/material_ui.dart';
import 'onespace_appearance.dart';
import 'theme_concept_card.dart';
import '../l10n/onespace_strings.dart';

class AppearanceSettingsScreen extends StatelessWidget{
 const AppearanceSettingsScreen({super.key});
 static String paletteLabel(BuildContext context,OneSpacePalette p)=>tr(context,switch(p){
  OneSpacePalette.midnightBlue=>'themeMidnightBlue',
  OneSpacePalette.monochrome=>'themeMonochrome',
  OneSpacePalette.cleanLight=>'themeCleanLight',
  OneSpacePalette.softRose=>'themeSoftRose',
 });
 static String seasonLabel(BuildContext context,SeasonChoice s)=>tr(context,switch(s){
  SeasonChoice.off=>'themeOff',SeasonChoice.automatic=>'themeAutomatic',
  SeasonChoice.valentines=>'themeValentine',SeasonChoice.spring=>'themeSpring',
  SeasonChoice.halloween=>'themeHalloween',SeasonChoice.winter=>'themeWinter',
  SeasonChoice.eid=>'themeEid',SeasonChoice.birthday=>'themeBirthday',
  SeasonChoice.anniversary=>'themeAnniversary',
  SeasonChoice.thanksgiving=>'themeThanksgiving',
  SeasonChoice.christmas=>'themeChristmas',SeasonChoice.newYear=>'themeNewYear',
 });
 @override Widget build(BuildContext context){
  final state=OneSpaceAppearance.instance;
  return Scaffold(
   appBar:AppBar(title:Text(tr(context,'themeSettings'))),
   body:SafeArea(child:AnimatedBuilder(animation:state,builder:(context,_) {
    final theme=Theme.of(context),scheme=theme.colorScheme;
    final width=MediaQuery.sizeOf(context).width;
    return ListView(padding:EdgeInsets.symmetric(
     horizontal:width>720?mathMax(20,(width-660)/2):16,vertical:16),children:[
     Text(tr(context,'themePersonalize'),style:theme.textTheme.headlineSmall),
     const SizedBox(height:6),
     Text(tr(context,'themeDeviceHint')),
     const SizedBox(height:24),
     Text(tr(context,'themePalettes'),style:theme.textTheme.titleLarge),
     const SizedBox(height:10),
     LayoutBuilder(builder:(ctx,box){
      final columns=box.maxWidth>=540?4:2;
      final tile=(box.maxWidth-12*(columns-1))/columns;
      return Wrap(spacing:12,runSpacing:12,children:[
       for(final p in OneSpacePalette.values)
        SizedBox(width:tile,
         child:ThemeConceptCard(
          palette:p,label:paletteLabel(context,p),
          selected:state.palette==p,onTap:()=>state.setPalette(p))),
      ]);
     }),
     const SizedBox(height:24),
     Text(tr(context,'themeBrightness'),style:theme.textTheme.titleLarge),
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
         label:Text(tr(context,item.$1==ThemeMode.system?'themePhone':
          item.$1==ThemeMode.light?'themeLight':'themeDark')),
         selected:state.mode==item.$1,
         onSelected:(_)=>state.setMode(item.$1)),
       ]);
      }
      return SegmentedButton<ThemeMode>(
       showSelectedIcon:true,
       segments:[
        ButtonSegment(value:ThemeMode.system,icon:const Icon(Icons.brightness_auto_outlined),
         label:Text(tr(context,'themePhone'))),
        ButtonSegment(value:ThemeMode.light,icon:const Icon(Icons.light_mode_outlined),
         label:Text(tr(context,'themeLight'))),
        ButtonSegment(value:ThemeMode.dark,icon:const Icon(Icons.dark_mode_outlined),
         label:Text(tr(context,'themeDark'))),
       ],
       selected:{state.mode},
       onSelectionChanged:(value)=>state.setMode(value.first));
     }),
     const SizedBox(height:8),
     Text(tr(context,'themePhoneHint')+' Selecting a theme first applies its signature light or dark look; you can override it here.',
      style:theme.textTheme.bodySmall),
     const SizedBox(height:24),
     Text(tr(context,'themeSeasonal'),style:theme.textTheme.titleLarge),
     const SizedBox(height:6),
     Text(tr(context,'themeSeasonHint')),
     const SizedBox(height:10),
     DropdownButtonFormField<SeasonChoice>(
      initialValue:state.season,
      decoration:InputDecoration(prefixIcon:const Icon(Icons.auto_awesome_outlined),
       labelText:tr(context,'themeSeasonLabel')),
      items:[for(final choice in SeasonChoice.values)
       DropdownMenuItem(value:choice,child:Text(seasonLabel(context,choice)))],
      onChanged:(value){if(value!=null)state.setSeason(value);}),
     const SizedBox(height:14),
     const SeasonalThemePreview(),
     const SizedBox(height:20),
     Text(tr(context,'themeComfort'),style:theme.textTheme.titleMedium),
     const SizedBox(height:8),
     Text(tr(context,'themeComfortHint')),
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
     SeasonChoice.eid=>(Icons.nights_stay_rounded,'Eid Mubarak','A beautiful season of togetherness'),
     SeasonChoice.birthday=>(Icons.cake_outlined,'Happy birthday!','Make the day feel extraordinary'),
     SeasonChoice.anniversary=>(Icons.favorite_rounded,'Another chapter together','Celebrate your story'),
     SeasonChoice.thanksgiving=>(Icons.local_florist_outlined,'A grateful season','Celebrate what matters'),
     SeasonChoice.christmas=>(Icons.auto_awesome_outlined,'Christmas glow','Warm moments across the miles'),
     SeasonChoice.newYear=>(Icons.celebration_outlined,'A new chapter','Dream together, begin together'),
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
