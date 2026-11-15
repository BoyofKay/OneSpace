import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum OneSpacePalette { midnightBlue, monochrome, cleanLight, softRose, oneSpace, oceanTeal, sageGarden, lavenderDusk, desertSand }
/// R64: the background pattern behind every screen (seasons override it while active).
enum BackgroundStyle { calm, hearts, stars, waves, pattern, plain }
enum SeasonChoice { off, automatic, valentines, spring, halloween, winter, eid, birthday, anniversary, thanksgiving, christmas, newYear, ramadan, nationalDay }

class OneSpaceAppearance extends ChangeNotifier with WidgetsBindingObserver {
 OneSpaceAppearance._(){WidgetsBinding.instance.addObserver(this);}
 @override void didChangeAppLifecycleState(AppLifecycleState state){
  if(state==AppLifecycleState.resumed)notifyListeners();
 }
 static final instance=OneSpaceAppearance._();
 static const _paletteKey='appearance.palette.v1';
 static const _modeKey='appearance.mode.v1';
 static const _seasonKey='appearance.season.v1';
 static const _backgroundKey='appearance.background.v1';
 BackgroundStyle background=BackgroundStyle.calm;
 OneSpacePalette palette=OneSpacePalette.cleanLight;
 ThemeMode mode=ThemeMode.system;
 SeasonChoice season=SeasonChoice.automatic;
 bool loaded=false;
 SeasonChoice? personalSeason;
 void setPersonalSeason(SeasonChoice? value){
  if(personalSeason==value)return;
  personalSeason=value;
  notifyListeners();
 }

 Future<void> load()async{
  try{
   final prefs=await SharedPreferences.getInstance();
   final saved=prefs.getString(_paletteKey);
   // Keep old selections valid; never reset sessions or other preferences.
   final migrated=switch(saved){
    'ocean'||'indigo'=>'midnightBlue',
    'sage'=>'monochrome',
    'rose'=>'softRose',
    _=>saved,
   };
   palette=_enumOf(OneSpacePalette.values,migrated,OneSpacePalette.cleanLight);
   mode=_enumOf(ThemeMode.values,prefs.getString(_modeKey),ThemeMode.system);
   season=_enumOf(SeasonChoice.values,prefs.getString(_seasonKey),SeasonChoice.automatic);
   background=_enumOf(BackgroundStyle.values,prefs.getString(_backgroundKey),BackgroundStyle.calm);
  }catch(_){ /* Default theme must remain available offline. */ }
  loaded=true;
  notifyListeners();
 }
 T _enumOf<T extends Enum>(List<T> all,String? name,T fallback){
  for(final value in all){if(value.name==name)return value;}
  return fallback;
 }
 Future<void> setPalette(OneSpacePalette value)async{
  palette=value;
  // A named concept should initially look like its preview; brightness can
  // still be overridden independently afterward, including Follow Phone.
  mode=(value==OneSpacePalette.midnightBlue||
       value==OneSpacePalette.monochrome)?ThemeMode.dark:ThemeMode.light;
  notifyListeners();
  try{
   final prefs=await SharedPreferences.getInstance();
   await prefs.setString(_paletteKey,value.name);
   await prefs.setString(_modeKey,mode.name);
  }catch(_){}
 }
 Future<void> setMode(ThemeMode value)async{
  mode=value;notifyListeners();
  try{(await SharedPreferences.getInstance()).setString(_modeKey,value.name);}catch(_){}
 }
 Future<void> setBackground(BackgroundStyle value)async{
  background=value;notifyListeners();
  try{(await SharedPreferences.getInstance()).setString(_backgroundKey,value.name);}catch(_){}
 }
 static String backgroundName(BackgroundStyle value)=>switch(value){
  BackgroundStyle.calm=>'Calm circles',
  BackgroundStyle.hearts=>'Little hearts',
  BackgroundStyle.stars=>'Starry night',
  BackgroundStyle.waves=>'Soft waves',
  BackgroundStyle.pattern=>'Arabesque',
  BackgroundStyle.plain=>'Plain',
 };
 Future<void> setSeason(SeasonChoice value)async{
  season=value;notifyListeners();
  try{(await SharedPreferences.getInstance()).setString(_seasonKey,value.name);}catch(_){}
 }

 static String paletteName(OneSpacePalette value)=>switch(value){
  OneSpacePalette.midnightBlue=>'Midnight Blue',
  OneSpacePalette.monochrome=>'Monochrome',
  OneSpacePalette.cleanLight=>'Clean Light',
  OneSpacePalette.softRose=>'Soft Rose',
  OneSpacePalette.oneSpace=>'OneSpace Coral & Teal',
  OneSpacePalette.oceanTeal=>'Ocean Teal',
  OneSpacePalette.sageGarden=>'Sage Garden',
  OneSpacePalette.lavenderDusk=>'Lavender Dusk',
  OneSpacePalette.desertSand=>'Desert Sand',
 };
 static Color paletteSeed(OneSpacePalette value)=>switch(value){
  OneSpacePalette.midnightBlue=>const Color(0xFF4A80D8),
  OneSpacePalette.monochrome=>const Color(0xFF62646B),
  OneSpacePalette.cleanLight=>const Color(0xFF3768BA),
  OneSpacePalette.softRose=>const Color(0xFFBA688B),
  OneSpacePalette.oneSpace=>const Color(0xFFE8745A),
  OneSpacePalette.oceanTeal=>const Color(0xFF1F6E78),
  OneSpacePalette.sageGarden=>const Color(0xFF5E8C61),
  OneSpacePalette.lavenderDusk=>const Color(0xFF8A6FC2),
  OneSpacePalette.desertSand=>const Color(0xFFB98348),
 };
 /// Background and card colours per palette (light, dark).
 static (Color,Color) paletteCanvas(OneSpacePalette p,bool dark)=>switch(p){
  OneSpacePalette.midnightBlue=>dark?(const Color(0xFF080F20),const Color(0xFF16213B)):(const Color(0xFFEDF3FC),Colors.white),
  OneSpacePalette.monochrome=>dark?(const Color(0xFF0D0E10),const Color(0xFF1F2024)):(const Color(0xFFF4F4F4),Colors.white),
  OneSpacePalette.cleanLight=>dark?(const Color(0xFF111827),const Color(0xFF1C2638)):(const Color(0xFFF6F8FC),Colors.white),
  OneSpacePalette.softRose=>dark?(const Color(0xFF211820),const Color(0xFF342431)):(const Color(0xFFFFF6FA),Colors.white),
  OneSpacePalette.oneSpace=>dark?(const Color(0xFF1E1715),const Color(0xFF2E2320)):(const Color(0xFFFBF8F1),Colors.white),
  OneSpacePalette.oceanTeal=>dark?(const Color(0xFF0B1D20),const Color(0xFF15302F)):(const Color(0xFFEEF7F7),Colors.white),
  OneSpacePalette.sageGarden=>dark?(const Color(0xFF121A14),const Color(0xFF1F2B21)):(const Color(0xFFF3F7F1),Colors.white),
  OneSpacePalette.lavenderDusk=>dark?(const Color(0xFF17131F),const Color(0xFF272035)):(const Color(0xFFF6F3FC),Colors.white),
  OneSpacePalette.desertSand=>dark?(const Color(0xFF1C1611),const Color(0xFF2E251C)):(const Color(0xFFFBF6EE),Colors.white),
 };
 static String seasonName(SeasonChoice value)=>switch(value){
  SeasonChoice.off=>'Off',
  SeasonChoice.automatic=>'Automatic — by date',
  SeasonChoice.valentines=>"Valentine's",
  SeasonChoice.spring=>'Spring',
  SeasonChoice.halloween=>'Halloween',
  SeasonChoice.winter=>'Winter celebrations',
  SeasonChoice.eid=>'Eid celebration',
  SeasonChoice.birthday=>'Birthday celebration',
  SeasonChoice.anniversary=>'Anniversary',
  SeasonChoice.thanksgiving=>'Thanksgiving',
  SeasonChoice.christmas=>'Christmas',
  SeasonChoice.newYear=>'New Year',
  SeasonChoice.ramadan=>'Ramadan',
  SeasonChoice.nationalDay=>'Saudi National Day',
 };
 static SeasonChoice effectiveSeason(SeasonChoice setting,DateTime date,
   {SeasonChoice? personal}){
  if(setting!=SeasonChoice.automatic)return setting;
  if(personal!=null)return personal;
  // Seasonal styling is decorative, not a statement of a public holiday.
  if(date.month==2&&date.day>=10&&date.day<=15)return SeasonChoice.valentines;
  if(date.month==10&&date.day>=25)return SeasonChoice.halloween;
  if(date.month==12&&date.day>=29||date.month==1&&date.day<=3){
    return SeasonChoice.newYear;
  }
  if(date.month==12&&date.day>=23&&date.day<=27){
    return SeasonChoice.christmas;
  }
  if(date.month==11){
    final first=DateTime(date.year,11,1).weekday;
    final fourthThursday=1+(DateTime.thursday-first+7)%7+21;
    if(date.day>=fourthThursday-1&&date.day<=fourthThursday+1){
      return SeasonChoice.thanksgiving;
    }
  }
  if(date.month>=3&&date.month<=5)return SeasonChoice.spring;
  return SeasonChoice.off;
 }
 static Color? seasonAccent(SeasonChoice choice)=>switch(choice){
  SeasonChoice.valentines=>const Color(0xFFBE4A76),
  SeasonChoice.spring=>const Color(0xFF4F9A74),
  SeasonChoice.halloween=>const Color(0xFFBD7134),
  SeasonChoice.winter=>const Color(0xFF567BA6),
  SeasonChoice.eid=>const Color(0xFF328F78),
  SeasonChoice.birthday=>const Color(0xFF9A54BE),
  SeasonChoice.anniversary=>const Color(0xFFB84677),
  SeasonChoice.thanksgiving=>const Color(0xFFB4783F),
  SeasonChoice.christmas=>const Color(0xFF2D8659),
  SeasonChoice.newYear=>const Color(0xFFAD8E46),
  SeasonChoice.ramadan=>const Color(0xFF7A5BA6),
  SeasonChoice.nationalDay=>const Color(0xFF1F8A55),
  _=>null,
 };
}

/// Visual tokens stay semantic so the entire component tree can adapt.
class OneSpaceVisualTokens extends ThemeExtension<OneSpaceVisualTokens> {
 const OneSpaceVisualTokens({
  required this.canvas,required this.panel,required this.raisedPanel,
  required this.edge,required this.highlight,required this.seasonal,
  required this.motifColor,required this.heroStart,required this.heroEnd,
 });
 final Color canvas,panel,raisedPanel,edge,highlight,seasonal,motifColor,heroStart,heroEnd;
 @override OneSpaceVisualTokens copyWith({
  Color? canvas,Color? panel,Color? raisedPanel,Color? edge,
  Color? highlight,Color? seasonal,Color? motifColor,
  Color? heroStart,Color? heroEnd,
 })=>OneSpaceVisualTokens(
  canvas:canvas??this.canvas,panel:panel??this.panel,
  raisedPanel:raisedPanel??this.raisedPanel,edge:edge??this.edge,
  highlight:highlight??this.highlight,seasonal:seasonal??this.seasonal,
  motifColor:motifColor??this.motifColor,heroStart:heroStart??this.heroStart,
  heroEnd:heroEnd??this.heroEnd);
 @override OneSpaceVisualTokens lerp(
  covariant ThemeExtension<OneSpaceVisualTokens>? other,double t){
  if(other is! OneSpaceVisualTokens)return this;
  Color mix(Color a,Color b)=>Color.lerp(a,b,t)??a;
  return OneSpaceVisualTokens(
   canvas:mix(canvas,other.canvas),panel:mix(panel,other.panel),
   raisedPanel:mix(raisedPanel,other.raisedPanel),
   edge:mix(edge,other.edge),highlight:mix(highlight,other.highlight),
   seasonal:mix(seasonal,other.seasonal),
   motifColor:mix(motifColor,other.motifColor),
   heroStart:mix(heroStart,other.heroStart),heroEnd:mix(heroEnd,other.heroEnd));
 }
}

class OneSpaceTheme {
 const OneSpaceTheme._();
 static ThemeData build({
  required OneSpacePalette palette,
  required Brightness brightness,
  SeasonChoice season=SeasonChoice.off,
 }){
  final dark=brightness==Brightness.dark;
  final seed=OneSpaceAppearance.paletteSeed(palette);
  final holiday=OneSpaceAppearance.seasonAccent(season);
  // Seasonal color is an entire scheme-level overlay, not just a Today card.
  final accent=holiday==null?seed:Color.lerp(seed,holiday,.65)!;
  final scheme=ColorScheme.fromSeed(seedColor:accent,brightness:brightness);
  final (bg,surface)=OneSpaceAppearance.paletteCanvas(palette,dark);
  final border=dark?Colors.white.withValues(alpha:.13)
    :scheme.outlineVariant.withValues(alpha:.75);
  final card=holiday==null?surface:Color.alphaBlend(
    holiday.withValues(alpha:dark ? .15 : .065),surface);
  final accentText=scheme.onSurface;
  final tokens=OneSpaceVisualTokens(
   canvas:bg,panel:card,raisedPanel:surface,edge:border,
   highlight:accent,seasonal:holiday??seed,
   motifColor:(holiday??seed).withValues(alpha:dark ? .18 : .11),
   heroStart:Color.alphaBlend(accent.withValues(alpha:dark ? .30 : .15),surface),
   heroEnd:Color.alphaBlend(seed.withValues(alpha:dark ? .10 : .045),bg),
  );
  final radius=BorderRadius.circular(20);
  return ThemeData(
   useMaterial3:true,
   brightness:brightness,
   colorScheme:scheme,
   extensions:[tokens],
   // A transparent Scaffold exposes the unified canvas and decorative
   // motifs across every screen, including routes, dialogs and sheets.
   scaffoldBackgroundColor:Colors.transparent,
   splashFactory:InkRipple.splashFactory,
   appBarTheme:AppBarTheme(
    backgroundColor:Color.alphaBlend(accent.withValues(alpha:dark ? .13 : .06),surface),
    foregroundColor:accentText,elevation:0,scrolledUnderElevation:0,
    centerTitle:false,
    titleTextStyle:TextStyle(fontSize:21,fontWeight:FontWeight.w800,
     letterSpacing:-.3,color:accentText),
   ),
   cardTheme:CardThemeData(
    color:card,elevation:0,
    margin:const EdgeInsets.symmetric(vertical:6),
    shape:RoundedRectangleBorder(borderRadius:radius,
     side:BorderSide(color:border,width:1)),
   ),
   dialogTheme:DialogThemeData(
    backgroundColor:card,
    surfaceTintColor:accent,
    shape:RoundedRectangleBorder(
     borderRadius:BorderRadius.circular(26),
     side:BorderSide(color:border)),
   ),
   bottomSheetTheme:BottomSheetThemeData(
    backgroundColor:card,modalBackgroundColor:card,
    showDragHandle:true,
    shape:const RoundedRectangleBorder(
     borderRadius:BorderRadius.vertical(top:Radius.circular(28))),
   ),
   snackBarTheme:SnackBarThemeData(
    backgroundColor:scheme.inverseSurface,
    contentTextStyle:TextStyle(color:scheme.onInverseSurface,
     fontWeight:FontWeight.w600),
    behavior:SnackBarBehavior.floating,
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),
   ),
   popupMenuTheme:PopupMenuThemeData(
    color:card,elevation:7,
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18),
     side:BorderSide(color:border)),
   ),
   inputDecorationTheme:InputDecorationTheme(
    filled:true,fillColor:surface,
    contentPadding:const EdgeInsets.symmetric(horizontal:17,vertical:15),
    border:OutlineInputBorder(borderRadius:BorderRadius.circular(15)),
    enabledBorder:OutlineInputBorder(
     borderRadius:BorderRadius.circular(15),
     borderSide:BorderSide(color:border)),
    focusedBorder:OutlineInputBorder(
     borderRadius:BorderRadius.circular(15),
     borderSide:BorderSide(color:scheme.primary,width:2)),
   ),
   navigationBarTheme:NavigationBarThemeData(
    height:74,backgroundColor:card,elevation:2,
    indicatorColor:scheme.primaryContainer,
    labelBehavior:NavigationDestinationLabelBehavior.alwaysShow,
   ),
   navigationRailTheme:NavigationRailThemeData(
    backgroundColor:card,indicatorColor:scheme.primaryContainer,
    selectedIconTheme:IconThemeData(color:scheme.onPrimaryContainer),
   ),
   floatingActionButtonTheme:FloatingActionButtonThemeData(
    backgroundColor:scheme.primaryContainer,
    foregroundColor:scheme.onPrimaryContainer,
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(19)),
    elevation:5,
   ),
   chipTheme:ChipThemeData(
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),
    side:BorderSide(color:border),
    selectedColor:scheme.primaryContainer,
   ),
   listTileTheme:ListTileThemeData(
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),
    iconColor:scheme.primary,
    contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:3),
   ),
   dividerTheme:DividerThemeData(color:border,thickness:1,space:1),
   filledButtonTheme:FilledButtonThemeData(style:FilledButton.styleFrom(
    padding:const EdgeInsets.symmetric(horizontal:22,vertical:15),
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(15)))),
   outlinedButtonTheme:OutlinedButtonThemeData(style:OutlinedButton.styleFrom(
    padding:const EdgeInsets.symmetric(horizontal:18,vertical:14),
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(15)))),
   textTheme:ThemeData(brightness:brightness).textTheme.apply(
    bodyColor:accentText,displayColor:accentText),
   visualDensity:VisualDensity.standard,
  );
 }
}
