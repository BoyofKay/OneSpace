import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'core/app_env.dart';
import 'features/spaces/invitation_link_inbox.dart';
import 'core/preferred_currency.dart';
import 'features/share_in/shared_file_screen.dart';
import 'features/settings/account_data_screen.dart';
import 'core/voice.dart';
import 'features/support/whats_new.dart';
import 'core/voice_assistant.dart';
import 'features/coordinate/coordinate_hub.dart';
import 'features/profile/me_screen.dart';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
// R75: the notes editor (flutter_quill) and text selection menus still use
// Flutter's built-in Material, which needs its own localizations.
import 'package:flutter_localizations/flutter_localizations.dart' as sdk
    show GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/auth_gate.dart';
import 'theme/onespace_appearance.dart';
import 'theme/onespace_canvas.dart';
import 'core/weather_unit_preference.dart';
import 'core/back_exit_policy.dart';
import 'features/search/global_search_screen.dart';
import 'features/share_in/share_intake_screen.dart';
import 'features/share_in/items_to_sort_screen.dart';
import 'features/share_in/share_intake_rules.dart';
import 'features/world/phone_contact_bridge.dart';
import 'features/world/saved_contact_editor.dart';
import 'core/current_space_cache.dart';
import 'features/connect/couple_letters_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/hubs/section_hubs.dart';
import 'features/remember/remember_screen.dart';
import 'core/secure_auth_storage.dart';
import 'core/performance_timings.dart';
import 'core/error_reporter.dart';
import 'core/usage_events.dart';

import 'features/calendar/calendar_screen.dart';
import 'features/notes/notes_screen.dart';
import 'features/memories/memories_screen.dart';
import 'features/checkins/checkins_screen.dart';
import 'features/plans/plans_screen.dart';
import 'features/profile/profile_settings_screen.dart';
import 'features/spaces/shared_space_screen.dart';
import 'l10n/onespace_locale_controller.dart';
import 'l10n/onespace_strings.dart';
import 'package:onespace/l10n/phrases.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Replace Flutter's unreadable black/red build-error surface with a
  // recoverable diagnostic card. Never hide the underlying exception.
  ErrorWidget.builder=(details)=>OneSpaceErrorFallback(details:details);
  // R74: errors are reported automatically (no content) so testers' problems
  // are seen even when nobody writes to us.
  FlutterError.onError=(details){
    FlutterError.presentError(details);
    ErrorReporter.report(details.exception,details.stack,context:details.context?.toDescription());
  };
  PlatformDispatcher.instance.onError=(error,stack){
    ErrorReporter.report(error,stack);
    return false;
  };
  final timer = Stopwatch()..start();
  // Render a real frame before initializing secure storage and the network
  // session. Previously OneSpace displayed a blank startup while awaiting
  // Supabase.initialize(), which can be slow on a remote region.
  runApp(OneSpaceBootstrap(startupClock: timer));
  unawaited(InvitationLinkInbox.instance.start());
  // Appearance loads without blocking the first frame or auth restoration.
  OneSpaceAppearance.instance.load();
  WeatherUnitPreference.instance.load();
}

/// A visible, copyable diagnostic replaces a device-only red error surface.
/// This does not suppress the exception; it makes the root cause reportable.
class OneSpaceErrorFallback extends StatelessWidget {
 const OneSpaceErrorFallback({super.key,required this.details});
 final FlutterErrorDetails details;
 @override Widget build(BuildContext context){
   // Include the first stack frames so a phone-only crash can be diagnosed
   // without deleting shared data or requiring Android developer tools.
   final text=[
     'OneSpace Flutter error',
     details.exceptionAsString(),
     if(details.library!=null)'Library: ${details.library}',
     if(details.context!=null)'Context: ${details.context}',
     if(details.stack!=null)
       'Stack trace:\n'+details.stack.toString().split('\n').take(20).join('\n'),
   ].join('\n');
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
           Text(tt('This part of OneSpace could not open'),
             textAlign:TextAlign.center,
             style:theme.textTheme.titleLarge),
           const SizedBox(height:8),
           Text(tt('Your saved data has not been deleted. '
             'Copy the technical details so we can identify and repair the cause.'),
             textAlign:TextAlign.center),
           const SizedBox(height:12),
           Container(
             constraints:const BoxConstraints(maxHeight:150),
             child:SingleChildScrollView(child:SelectableText(text,
               style:theme.textTheme.bodySmall))),
           const SizedBox(height:15),
           FilledButton.icon(
             icon:const Icon(Icons.copy),
             label:Text(tt('Copy error details')),
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
      // No network or Auth session may start until Android confirms that this
      // installed application ID belongs to the selected backend.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        const channel = MethodChannel('onespace/environment');
        final installedPackage = await channel.invokeMethod<String>('packageId');
        if (!OneSpaceEnv.packageMatchesEnvironment(installedPackage)) {
          throw StateError('QA/Production configuration mismatch: this build '
            'cannot connect to its configured database. Please install the '
            'correct OneSpace app version.');
        }
      }
      await Supabase.initialize(
        url: OneSpaceEnv.supabaseUrl,
        publishableKey: OneSpaceEnv.publishableKey,
        authOptions: FlutterAuthClientOptions(
          localStorage: SecureAuthStorage(),
        ),
      );
      PerformanceTimings.instance.record(
        'Supabase session initialization', clock.elapsed);
      if (mounted) setState(() { _ready = true; _busy = false; });
    } catch (e) {
      PerformanceTimings.instance.record(
        'Session initialization failed',clock.elapsed);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is StateError && e.message.toString().startsWith('QA/Production')
            ? e.message.toString()
            : 'OneSpace could not open its saved session. '
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
                Image.asset('assets/branding/mark.png',width:96,height:96,
                  semanticLabel:tt('OneSpace logo')),
                const SizedBox(height:12),
                Text(tt('OneSpace'),style:TextStyle(
                  fontSize:30,fontWeight:FontWeight.w800)),
                const SizedBox(height:6),
                Text(tt('Two of us, One Space')),
                const SizedBox(height:25),
                if (_busy) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height:16),
                  Text(tt('Opening your secure space…')),
                ],
                if (_error != null) ...[
                  Text(tt(_error!),textAlign:TextAlign.center),
                  const SizedBox(height:14),
                  FilledButton.icon(
                    onPressed:_initialize,
                    icon:const Icon(Icons.refresh),
                    label:Text(tt('Retry'))),
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
        final activeSeason=OneSpaceAppearance.effectiveSeason(appearance.season,DateTime.now(),
         personal:appearance.personalSeason);
        return ValueListenableBuilder<Locale?>(
          valueListenable:OneSpaceLocaleController.instance,
          builder:(context,currentLocale,child)=>MaterialApp(
            title:tt('OneSpace'),
            locale:currentLocale,
            supportedLocales:const [Locale('en'),Locale('ar')],
            localizationsDelegates:const [
              GlobalMaterialLocalizations.delegate,
              sdk.GlobalMaterialLocalizations.delegate,
              sdk.GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              FlutterQuillLocalizations.delegate,
            ],
            debugShowCheckedModeBanner:false,
            theme:OneSpaceTheme.build(
              palette:appearance.palette,brightness:Brightness.light,season:activeSeason),
            darkTheme:OneSpaceTheme.build(
              palette:appearance.palette,brightness:Brightness.dark,season:activeSeason),
            themeMode:appearance.mode,
            builder:(context,child){
              OneSpacePhrases.follow(context);
              return OneSpaceCanvas(season:activeSeason,style:appearance.background,
                child:TabletFrame(child:child??const SizedBox.shrink()));
            },
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
  final _coordinate=GlobalKey<CoordinateHubState>();

  @override void initState(){
    super.initState();
    _incomingShares.setMethodCallHandler((call)async{
      if(call.method=='shareAvailable')await _takeIncomingShare();
    });
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted)_takeIncomingShare();
      if(mounted)_checkPendingDeletion();
      // D78: usage statistics (event names + times only; can be switched off in Settings).
      unawaited(UsageEvents.instance.start());
      PreferredCurrency.load();
      if(mounted)WhatsNew.maybeShow(context);
      // R61: "Voice command" from a long-press on the app icon.
      if(Voice.enabled)Voice.init((){if(mounted)VoiceAssistant.start(context,goToday:()=>navigate(0));});
    });
  }

  @override void dispose(){
    _incomingShares.setMethodCallHandler(null);
    super.dispose();
  }

  /// R59: signing in during the 7-day grace period offers to keep the account.
  Future<void> _checkPendingDeletion() async{
    try{
      final db=Supabase.instance.client;
      final me=db.auth.currentUser?.id;
      if(me==null)return;
      final row=await db.from('account_deletion_requests').select().eq('user_id',me).maybeSingle();
      if(!mounted||!AccountDataRules.pending(row))return;
      final due=DateTime.tryParse(row!['purge_after']?.toString()??'')?.toLocal();
      final keep=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        icon:const Icon(Icons.person_remove_outlined),
        title:Text(tt('Your account is scheduled for deletion')),
        content:Text(tt(due==null?'Do you want to keep it?':
          'It will be deleted on ${MaterialLocalizations.of(ctx).formatFullDate(due)}. Do you want to keep it?')),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(tt('Not now'))),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(tt('Keep my account'))),
        ]));
      if(keep==true){
        await db.rpc('cancel_account_deletion');
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:Text(tt('Deletion cancelled. Welcome back.'))));
      }
    }catch(_){/* never block the app on this check */}
  }

  Future<void> _takeIncomingShare() async{
    if(_handlingIncomingShare||!mounted)return;
    _handlingIncomingShare=true;
    try{
      // Incoming vCards always open a preview with a private default.
      final sharedContact=await PhoneContactBridge.takeSharedVcard();
      if(sharedContact!=null){
        final space=await CurrentSpaceCache.instance.get();
        if(!mounted)return;
        if(space!=null)open(SavedContactEditor(spaceId:space,imported:sharedContact));
        return;
      }
      final message=await _incomingShares.invokeMapMethod<String,dynamic>(
       'takePendingShare');
      if(!mounted||message==null)return;
      // R55: photos and PDFs shared from other apps.
      if(message['fileError']!=null||message['fileBytes']!=null){
        final file=SharedFile.fromExternal(message);
        final space=await CurrentSpaceCache.instance.get();
        if(!mounted)return;
        if(file==null||space==null){
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(
            tt(space==null?'Connect your shared space first.':
            (message['fileError']?.toString()??'OneSpace accepts photos (JPEG, PNG, WebP, HEIC) and PDFs up to 10 MB.')))));
          return;
        }
        open(SharedFileScreen(spaceId:space,file:file));
        return;
      }
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration:Duration(seconds:2),
        content:Text(tt('Swipe back again to exit OneSpace')),
      ));
    }
  }

  static const _tabNames=['today','remember','coordinate','connect','me'];
  void navigate(int index) {
    _exitPolicy.reset();
    if(index>=0&&index<_tabNames.length&&(index!=selectedIndex||showProfile))UsageEvents.instance.log('tab/${_tabNames[index]}');
    setState(() {
      if ((index == 0 || index == 1) && selectedIndex != index) refreshToken++;
      selectedIndex = index;
      showProfile = false;
      visited.add(index);
    });
  }

  void open(Widget screen) {
    _exitPolicy.reset();
    UsageEvents.instance.screen(screen);
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
          onOpenNotes:()=>open(const NotesScreen()),
          onOpenCalendar:()=>open(const CalendarScreen()),
          onOpenMemories:()=>open(const MemoriesScreen()),
          onOpenCheckins:()=>open(const CheckinsScreen()),
          onOpenLetters:()=>open(const CoupleLettersScreen()),
          onOpenCoordinate:()=>navigate(2),
          onOpenWorld:(){navigate(2);WidgetsBinding.instance.addPostFrameCallback((_)=>_coordinate.currentState?.show(1));},
          onOpenProfile:()=>navigate(4),
        ),
        if(visited.contains(1)) RememberScreen(refreshToken:refreshToken)
          else const SizedBox.shrink(),
        if(visited.contains(2))CoordinateHub(key:_coordinate)
          else const SizedBox.shrink(),
        if(visited.contains(3))const SectionHub(section:'connect')
          else const SizedBox.shrink(),
        if(visited.contains(4))const MeScreen()
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
        title:Row(mainAxisSize:MainAxisSize.min,children:[
          Image.asset('assets/branding/mark.png',width:30,height:30,excludeFromSemantics:true),
          const SizedBox(width:10),
          Flexible(child:Column(
          mainAxisSize:MainAxisSize.min,
          crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            Text(tt('OneSpace'),
              maxLines:1,overflow:TextOverflow.ellipsis,
              style:TextStyle(fontWeight:FontWeight.w800)),
            Text(tr(context,'tagline'),
              maxLines:1,overflow:TextOverflow.ellipsis,
              style:Theme.of(context).textTheme.labelSmall),
          ])),
        ]),
        actions:[
          // R60: voice commands ("Remind me…", "What's on today?", "Open notes").
          if(Voice.enabled)IconButton(tooltip:tt('Voice command'),visualDensity:VisualDensity.compact,icon:const Icon(Icons.mic_none_rounded),
            onPressed:()=>VoiceAssistant.start(context,goToday:()=>navigate(0))),
          if(!showProfile)const NotificationBell(),
          PopupMenuButton<String>(
            tooltip:tt('More options'),
            icon:const Icon(Icons.more_vert),
            onSelected:(choice){
              if(choice=='search')open(const GlobalSearchScreen());
              if(choice=='sort')open(const ItemsToSortScreen());
            },
            itemBuilder:(_)=>[
              PopupMenuItem(value:'search',child:ListTile(
                leading:Icon(Icons.search_outlined),
                title:Text(tt('Search our space')))),
              PopupMenuItem(value:'sort',child:ListTile(
                leading:Icon(Icons.inbox_outlined),
                title:Text(tt('Items to sort')))),
            ],
          ),
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
          NavigationRailDestination(icon:const Icon(Icons.person_outline),
           selectedIcon:const Icon(Icons.person),label:Text(tr(context,'meTab'))),
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
          NavigationDestination(icon:const Icon(Icons.person_outline),
            selectedIcon:const Icon(Icons.person),label:tr(context,'meTab')),
        ],
      ),
    ));
  }
}

/// R74: on tablets and wide windows the app is laid out at phone-like reading
/// width in the middle of the screen (pages, sheets and dialogs alike), so
/// forms, chips and lists keep the proportions they were designed for.
class TabletFrame extends StatelessWidget {
  const TabletFrame({super.key,required this.child});
  final Widget child;
  static const maxWidth=720.0;
  @override
  Widget build(BuildContext context){
    final media=MediaQuery.of(context);
    if(media.size.width<=maxWidth+120)return child;
    final line=Theme.of(context).colorScheme.outlineVariant;
    return Center(child:SizedBox(width:maxWidth,child:DecoratedBox(
      decoration:BoxDecoration(border:Border.symmetric(vertical:BorderSide(color:line))),
      child:ClipRect(child:MediaQuery(
        data:media.copyWith(size:Size(maxWidth,media.size.height)),
        child:child)))));
  }
}

