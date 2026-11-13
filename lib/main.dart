import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/auth_gate.dart';
import 'theme/onespace_appearance.dart';
import 'core/back_exit_policy.dart';
import 'features/search/global_search_screen.dart';
import 'features/share_in/share_intake_screen.dart';
import 'features/share_in/share_intake_rules.dart';
import 'features/connect/couple_letters_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/coordinate/coordinate_screen.dart';
import 'features/hubs/section_hubs.dart';
import 'features/remember/remember_screen.dart';
import 'core/secure_auth_storage.dart';
import 'core/performance_timings.dart';
import 'features/lists/lists_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/notes/notes_screen.dart';
import 'features/memories/memories_screen.dart';
import 'features/goals/goals_screen.dart';
import 'features/checkins/checkins_screen.dart';
import 'features/plans/plans_screen.dart';
import 'features/profile/profile_settings_screen.dart';
import 'features/settings/onespace_settings_screen.dart';
import 'features/spaces/shared_space_screen.dart';
import 'l10n/onespace_locale_controller.dart';
import 'l10n/onespace_strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Replace Flutter's unreadable black/red build-error surface with a
  // recoverable diagnostic card. Never hide the underlying exception.
  ErrorWidget.builder=(details)=>OneSpaceErrorFallback(details:details);
  final timer = Stopwatch()..start();
  // Render a real frame before initializing secure storage and the network
  // session. Previously OneSpace displayed a blank startup while awaiting
  // Supabase.initialize(), which can be slow on a remote region.
  runApp(OneSpaceBootstrap(startupClock: timer));
  // Appearance loads without blocking the first frame or auth restoration.
  OneSpaceAppearance.instance.load();
}

/// A visible, copyable diagnostic replaces a device-only red error surface.
/// This does not suppress the exception; it makes the root cause reportable.
class OneSpaceErrorFallback extends StatelessWidget {
 const OneSpaceErrorFallback({super.key,required this.details});
 final FlutterErrorDetails details;
 @override Widget build(BuildContext context){
   final text=details.exceptionAsString();
   final theme=Theme.of(context);
   return Material(
     color:theme.colorScheme.surface,
     child:SafeArea(child:Center(child:ConstrainedBox(
       constraints:const BoxConstraints(maxWidth:420),
       child:Padding(padding:const EdgeInsets.all(20),
         child:Column(mainAxisSize:MainAxisSize.min,children:[
           Icon(Icons.report_problem_outlined,size:44,
             color:theme.colorScheme.error),
           const SizedBox(height:12),
           Text('This part of OneSpace could not open',
             textAlign:TextAlign.center,
             style:theme.textTheme.titleLarge),
           const SizedBox(height:8),
           const Text('Your saved data has not been deleted. '
             'Copy the technical details so we can identify and repair the cause.',
             textAlign:TextAlign.center),
           const SizedBox(height:12),
           Container(
             constraints:const BoxConstraints(maxHeight:150),
             child:SingleChildScrollView(child:SelectableText(text,
               style:theme.textTheme.bodySmall))),
           const SizedBox(height:15),
           FilledButton.icon(
             icon:const Icon(Icons.copy),
             label:const Text('Copy error details'),
             onPressed:()=>Clipboard.setData(ClipboardData(text:text))),
         ]),
       ),
     ))),
   );
 }
}

/// Runs immediately; it does not require an initialized Supabase singleton.
/// Client-backed screens are never mounted until startup is complete.
class OneSpaceBootstrap extends StatefulWidget {
  const OneSpaceBootstrap({super.key, required this.startupClock});
  final Stopwatch startupClock;

  @override
  State<OneSpaceBootstrap> createState() => _OneSpaceBootstrapState();
}

class _OneSpaceBootstrapState extends State<OneSpaceBootstrap> {
  bool _ready = false;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PerformanceTimings.instance.record(
        'First app frame', widget.startupClock.elapsed);
    });
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() { _busy = true; _error = null; });
    final clock = Stopwatch()..start();
    try {
      await Supabase.initialize(
        url: 'https://ugwrpeduzyzrujkizqfo.supabase.co',
        publishableKey: 'sb_publishable_TtW_uUboFxD4adF5o7FSfA_cpjojMCe',
        authOptions: FlutterAuthClientOptions(
          localStorage: SecureAuthStorage(),
        ),
      );
      PerformanceTimings.instance.record(
        'Supabase session initialization', clock.elapsed);
      if (mounted) setState(() { _ready = true; _busy = false; });
    } catch (_) {
      PerformanceTimings.instance.record(
        'Session initialization failed',clock.elapsed);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'OneSpace could not open its saved session. '
            'Check the device and network, then retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const OneSpaceApp();
    return MaterialApp(
      debugShowCheckedModeBanner:false,
      home:Scaffold(
        body:SafeArea(
          child:Center(child:ConstrainedBox(
            constraints:const BoxConstraints(maxWidth:360),
            child:Padding(
              padding:const EdgeInsets.all(28),
              child:Column(mainAxisSize:MainAxisSize.min,children:[
                const Icon(Icons.favorite_rounded,
                  color:Color(0xFF167E81),size:60),
                const SizedBox(height:12),
                const Text('OneSpace',style:TextStyle(
                  fontSize:30,fontWeight:FontWeight.w800)),
                const SizedBox(height:6),
                const Text('One Life. Two Places. One Space.'),
                const SizedBox(height:25),
                if (_busy) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height:16),
                  const Text('Opening your secure space…'),
                ],
                if (_error != null) ...[
                  Text(_error!,textAlign:TextAlign.center),
                  const SizedBox(height:14),
                  FilledButton.icon(
                    onPressed:_initialize,
                    icon:const Icon(Icons.refresh),
                    label:const Text('Retry')),
                ],
              ]),
            ),
          )),
        ),
      ),
    );
  }
}

class OneSpaceApp extends StatelessWidget {
  const OneSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation:OneSpaceAppearance.instance,
      builder:(context,_) {
        final appearance=OneSpaceAppearance.instance;
        return ValueListenableBuilder<Locale?>(
          valueListenable:OneSpaceLocaleController.instance,
          builder:(context,currentLocale,child)=>MaterialApp(
            title:'OneSpace',
            locale:currentLocale,
            supportedLocales:const [Locale('en'),Locale('ar')],
            localizationsDelegates:const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            debugShowCheckedModeBanner:false,
            theme:OneSpaceTheme.build(
              palette:appearance.palette,brightness:Brightness.light),
            darkTheme:OneSpaceTheme.build(
              palette:appearance.palette,brightness:Brightness.dark),
            themeMode:appearance.mode,
            themeAnimationDuration:
              WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations
                ?Duration.zero:const Duration(milliseconds:280),
            themeAnimationCurve:Curves.easeInOutCubic,
            home:const AuthGate(signedIn:OneSpaceHome()),
          ),
        );
      },
    );
  }
}

class OneSpaceHome extends StatefulWidget {
  const OneSpaceHome({super.key});

  @override
  State<OneSpaceHome> createState() => _OneSpaceHomeState();
}

class _OneSpaceHomeState extends State<OneSpaceHome> {
  int selectedIndex = 0;
  int refreshToken = 0;
  bool showProfile = false;
  final Set<int> visited = {0};
  final BackExitPolicy _exitPolicy=BackExitPolicy();
  static const _incomingShares=MethodChannel('onespace/incoming_share');
  bool _handlingIncomingShare=false;

  @override void initState(){
    super.initState();
    _incomingShares.setMethodCallHandler((call)async{
      if(call.method=='shareAvailable')await _takeIncomingShare();
    });
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted)_takeIncomingShare();
    });
  }

  @override void dispose(){
    _incomingShares.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _takeIncomingShare() async{
    if(_handlingIncomingShare||!mounted)return;
    _handlingIncomingShare=true;
    try{
      final message=await _incomingShares.invokeMapMethod<String,dynamic>(
       'takePendingShare');
      if(!mounted||message==null)return;
      final data=ShareIntakeRules.fromExternal(message);
      if(!data.hasContent)return;
      open(ShareIntakeScreen(shared:data));
    }on MissingPluginException{
      // iOS shares currently require manual paste, not a share extension.
    }on PlatformException{
      // Invalid shares must not interrupt authentication or normal browsing.
    }finally{
      _handlingIncomingShare=false;
    }
  }


  void _handleAndroidBack(){
    if(showProfile){
      _exitPolicy.reset();
      setState((){showProfile=false;refreshToken++;});
      return;
    }
    if(selectedIndex!=0){
      _exitPolicy.reset();
      navigate(0);
      return;
    }
    if(_exitPolicy.shouldExit(DateTime.now())){
      SystemNavigator.pop();
    }else{
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration:Duration(seconds:2),
        content:Text('Swipe back again to exit OneSpace'),
      ));
    }
  }

  void navigate(int index) {
    _exitPolicy.reset();
    setState(() {
      if ((index == 0 || index == 1) && selectedIndex != index) refreshToken++;
      selectedIndex = index;
      showProfile = false;
      visited.add(index);
    });
  }

  void open(Widget screen) {
    _exitPolicy.reset();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => screen),
    ).then((_) {
      if (mounted) setState(() => refreshToken++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = showProfile ? 5 : selectedIndex;
    final screen=MediaQuery.sizeOf(context);
    final wide=screen.width>=900&&screen.height>=620;
    final pages=IndexedStack(index:visible,children:[
        SharedSpaceScreen(
          refreshToken:refreshToken,
          onOpenPlans:()=>open(const PlansScreen()),
          onOpenLists:()=>open(const ListsScreen()),
          onOpenNotes:()=>open(const NotesScreen()),
          onOpenCalendar:()=>open(const CalendarScreen()),
          onOpenMemories:()=>open(const MemoriesScreen()),
          onOpenGoals:()=>open(const GoalsScreen()),
          onOpenCheckins:()=>open(const CheckinsScreen()),
          onOpenLetters:()=>open(const CoupleLettersScreen()),
          onOpenCoordinate:()=>navigate(2),
          onOpenWorld:()=>navigate(4),
          onOpenProfile:()=>setState(() => showProfile = true),
        ),
        if(visited.contains(1)) RememberScreen(refreshToken:refreshToken)
          else const SizedBox.shrink(),
        if(visited.contains(2))const CoordinateScreen()
          else const SizedBox.shrink(),
        if(visited.contains(3))const SectionHub(section:'connect')
          else const SizedBox.shrink(),
        if(visited.contains(4))const SectionHub(section:'world')
          else const SizedBox.shrink(),
        if(showProfile)const ProfileSettingsScreen()
          else const SizedBox.shrink(),
      ]);
    return PopScope<Object?>(
      canPop:false,
      onPopInvokedWithResult:(didPop,result){
        if(!didPop)_handleAndroidBack();
      },
      child:Scaffold(
      appBar: AppBar(
        leading: showProfile ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() {
            showProfile = false;
            refreshToken++;
          }),
          tooltip: tr(context, 'backHome'),
        ) : null,
        title:const Text('OneSpace',
          maxLines:1,overflow:TextOverflow.ellipsis,
          style:TextStyle(fontWeight:FontWeight.w800)),
        actions:[
          if(!showProfile)const NotificationBell(),
          PopupMenuButton<String>(
            tooltip:'More options',
            icon:const Icon(Icons.more_vert),
            onSelected:(choice){
              if(choice=='settings')open(const OneSpaceSettingsScreen());
              if(choice=='search')open(const GlobalSearchScreen());
              if(choice=='share')open(const ShareIntakeScreen());
              if(choice=='language')open(Scaffold(
                appBar:AppBar(title:const Text('Language')),
                body:const SafeArea(child:ProfileSettingsScreen(
                  settingsOnly:true,section:'language'))));
            },
            itemBuilder:(_)=>const [
              PopupMenuItem(value:'settings',child:ListTile(
                leading:Icon(Icons.settings_outlined),
                title:Text('Settings'))),
              PopupMenuItem(value:'search',child:ListTile(
                leading:Icon(Icons.search_outlined),
                title:Text('Search our space'))),
              PopupMenuItem(value:'share',child:ListTile(
                leading:Icon(Icons.add_link),
                title:Text('Save a link or idea'))),
              PopupMenuItem(value:'language',child:ListTile(
                leading:Icon(Icons.translate),
                title:Text('Language'))),
            ],
          ),
          if(!showProfile)IconButton(
            key:const Key('profileTopBarButton'),
            icon:const Icon(Icons.account_circle_outlined,size:28),
            tooltip:tr(context,'profile'),
            onPressed:()=>setState(()=>showProfile=true)),
        ],
      ),
      body:SafeArea(child:wide&&!showProfile?
       Row(children:[
        NavigationRail(
         selectedIndex:selectedIndex,
         onDestinationSelected:navigate,
         labelType:NavigationRailLabelType.all,
         minWidth:78,
         destinations:[
          NavigationRailDestination(icon:const Icon(Icons.today_outlined),
           selectedIcon:const Icon(Icons.today),label:Text(tr(context,'todayTab'))),
          NavigationRailDestination(icon:const Icon(Icons.bookmark_border),
           selectedIcon:const Icon(Icons.bookmark),label:Text(tr(context,'rememberTab'))),
          NavigationRailDestination(icon:const Icon(Icons.hub_outlined),
           selectedIcon:const Icon(Icons.hub),label:Text(tr(context,'coordinateTab'))),
          NavigationRailDestination(icon:const Icon(Icons.favorite_border),
           selectedIcon:const Icon(Icons.favorite),label:Text(tr(context,'connectTab'))),
          NavigationRailDestination(icon:const Icon(Icons.public_outlined),
           selectedIcon:const Icon(Icons.public),label:Text(tr(context,'worldTab'))),
         ],
        ),
        VerticalDivider(width:1,color:Theme.of(context).colorScheme.outlineVariant),
        Expanded(child:Center(child:ConstrainedBox(
         constraints:const BoxConstraints(maxWidth:1050),child:pages))),
       ]):pages),
      bottomNavigationBar:showProfile||wide?null:NavigationBar(
        labelBehavior:screen.width<380?
          NavigationDestinationLabelBehavior.onlyShowSelected:
          NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex:selectedIndex,
        onDestinationSelected:navigate,
        destinations:[
          NavigationDestination(icon:const Icon(Icons.today_outlined),
            selectedIcon:const Icon(Icons.today),label:tr(context,'todayTab')),
          NavigationDestination(icon:const Icon(Icons.bookmark_border),
            selectedIcon:const Icon(Icons.bookmark),label:tr(context,'rememberTab')),
          NavigationDestination(icon:const Icon(Icons.hub_outlined),
            selectedIcon:const Icon(Icons.hub),label:tr(context,'coordinateTab')),
          NavigationDestination(icon:const Icon(Icons.favorite_border),
            selectedIcon:const Icon(Icons.favorite),label:tr(context,'connectTab')),
          NavigationDestination(icon:const Icon(Icons.public_outlined),
            selectedIcon:const Icon(Icons.public),label:tr(context,'worldTab')),
        ],
      ),
    ));
  }
}
