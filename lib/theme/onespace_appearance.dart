import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum OneSpacePalette { ocean, rose, sage, indigo }
enum SeasonChoice { off, automatic, valentines, spring, halloween, winter }

class OneSpaceAppearance extends ChangeNotifier {
 OneSpaceAppearance._();
 static final instance=OneSpaceAppearance._();
 static const _paletteKey='appearance.palette.v1';
 static const _modeKey='appearance.mode.v1';
 static const _seasonKey='appearance.season.v1';
 OneSpacePalette palette=OneSpacePalette.ocean;
 ThemeMode mode=ThemeMode.system;
 SeasonChoice season=SeasonChoice.automatic;
 bool loaded=false;

 Future<void> load()async{
  try{
   final prefs=await SharedPreferences.getInstance();
   palette=_enumOf(OneSpacePalette.values,prefs.getString(_paletteKey),OneSpacePalette.ocean);
   mode=_enumOf(ThemeMode.values,prefs.getString(_modeKey),ThemeMode.system);
   season=_enumOf(SeasonChoice.values,prefs.getString(_seasonKey),SeasonChoice.automatic);
  }catch(_){ /* Default theme must remain available offline. */ }
  loaded=true;
  notifyListeners();
 }
 T _enumOf<T extends Enum>(List<T> all,String? name,T fallback){
  for(final value in all){if(value.name==name)return value;}
  return fallback;
 }
 Future<void> setPalette(OneSpacePalette value)async{
  palette=value;notifyListeners();
  try{(await SharedPreferences.getInstance()).setString(_paletteKey,value.name);}catch(_){}
 }
 Future<void> setMode(ThemeMode value)async{
  mode=value;notifyListeners();
  try{(await SharedPreferences.getInstance()).setString(_modeKey,value.name);}catch(_){}
 }
 Future<void> setSeason(SeasonChoice value)async{
  season=value;notifyListeners();
  try{(await SharedPreferences.getInstance()).setString(_seasonKey,value.name);}catch(_){}
 }

 static String paletteName(OneSpacePalette value)=>switch(value){
  OneSpacePalette.ocean=>'Coastal Blue',
  OneSpacePalette.rose=>'Rose & Plum',
  OneSpacePalette.sage=>'Sage & Sand',
  OneSpacePalette.indigo=>'Midnight Indigo',
 };
 static Color paletteSeed(OneSpacePalette value)=>switch(value){
  OneSpacePalette.ocean=>const Color(0xFF167E81),
  OneSpacePalette.rose=>const Color(0xFFA54D74),
  OneSpacePalette.sage=>const Color(0xFF597D6C),
  OneSpacePalette.indigo=>const Color(0xFF5859A9),
 };
 static String seasonName(SeasonChoice value)=>switch(value){
  SeasonChoice.off=>'Off',
  SeasonChoice.automatic=>'Automatic — by date',
  SeasonChoice.valentines=>"Valentine's",
  SeasonChoice.spring=>'Spring',
  SeasonChoice.halloween=>'Halloween',
  SeasonChoice.winter=>'Winter holidays',
 };
 static SeasonChoice effectiveSeason(SeasonChoice setting,DateTime date){
  if(setting!=SeasonChoice.automatic)return setting;
  // Seasonal styling is decorative, not a statement of a public holiday.
  if(date.month==2&&date.day>=10&&date.day<=15)return SeasonChoice.valentines;
  if(date.month==10&&date.day>=25)return SeasonChoice.halloween;
  if(date.month==12&&date.day>=18 || date.month==1&&date.day<=2){
    return SeasonChoice.winter;
  }
  if(date.month>=3&&date.month<=5)return SeasonChoice.spring;
  return SeasonChoice.off;
 }
 static Color? seasonAccent(SeasonChoice choice)=>switch(choice){
  SeasonChoice.valentines=>const Color(0xFFBE4A76),
  SeasonChoice.spring=>const Color(0xFF4F9A74),
  SeasonChoice.halloween=>const Color(0xFFBD7134),
  SeasonChoice.winter=>const Color(0xFF567BA6),
  _=>null,
 };
}

class OneSpaceTheme {
 const OneSpaceTheme._();
 static ThemeData build({required OneSpacePalette palette,required Brightness brightness}){
  final dark=brightness==Brightness.dark;
  final scheme=ColorScheme.fromSeed(
   seedColor:OneSpaceAppearance.paletteSeed(palette),
   brightness:brightness,
  );
  final background=dark?const Color(0xFF11161C):const Color(0xFFF7F9FB);
  final surface=dark?const Color(0xFF1C232B):Colors.white;
  final border=dark?const Color(0xFF35424B):const Color(0xFFE5EAEE);
  return ThemeData(
   useMaterial3:true,
   brightness:brightness,
   colorScheme:scheme,
   scaffoldBackgroundColor:background,
   splashFactory:InkRipple.splashFactory,
   appBarTheme:AppBarTheme(
    backgroundColor:background,
    foregroundColor:scheme.onSurface,
    elevation:0,scrolledUnderElevation:0,
    centerTitle:false,
    titleTextStyle:TextStyle(
     fontSize:20,fontWeight:FontWeight.w700,color:scheme.onSurface),
   ),
   cardTheme:CardThemeData(
    color:surface,elevation:0,margin:const EdgeInsets.symmetric(vertical:5),
    shape:RoundedRectangleBorder(
     borderRadius:BorderRadius.circular(20),
     side:BorderSide(color:border,width:.9),
    ),
   ),
   inputDecorationTheme:InputDecorationTheme(
    filled:true,fillColor:surface,
    contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:14),
    border:OutlineInputBorder(borderRadius:BorderRadius.circular(14)),
    enabledBorder:OutlineInputBorder(
     borderRadius:BorderRadius.circular(14),
     borderSide:BorderSide(color:border)),
    focusedBorder:OutlineInputBorder(
     borderRadius:BorderRadius.circular(14),
     borderSide:BorderSide(color:scheme.primary,width:1.8)),
   ),
   navigationBarTheme:NavigationBarThemeData(
    height:72,
    backgroundColor:surface,
    elevation:0,
    indicatorColor:scheme.primaryContainer,
    labelBehavior:NavigationDestinationLabelBehavior.alwaysShow,
   ),
   navigationRailTheme:NavigationRailThemeData(
    backgroundColor:surface,
    indicatorColor:scheme.primaryContainer,
    selectedIconTheme:IconThemeData(color:scheme.onPrimaryContainer),
   ),
   floatingActionButtonTheme:FloatingActionButtonThemeData(
    backgroundColor:scheme.primaryContainer,
    foregroundColor:scheme.onPrimaryContainer,
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)),
   ),
   chipTheme:ChipThemeData(
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),
    side:BorderSide(color:border),
    selectedColor:scheme.primaryContainer,
   ),
   filledButtonTheme:FilledButtonThemeData(style:FilledButton.styleFrom(
    padding:const EdgeInsets.symmetric(horizontal:20,vertical:14),
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),
   )),
   outlinedButtonTheme:OutlinedButtonThemeData(style:OutlinedButton.styleFrom(
    padding:const EdgeInsets.symmetric(horizontal:18,vertical:13),
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),
   )),
   dividerTheme:DividerThemeData(color:border,thickness:1,space:1),
   pageTransitionsTheme:const PageTransitionsTheme(builders:{
    TargetPlatform.android:FadeUpwardsPageTransitionsBuilder(),
    TargetPlatform.iOS:CupertinoPageTransitionsBuilder(),
   }),
   visualDensity:VisualDensity.standard,
  );
 }
}
