import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'notifications_screen.dart';

/// FCM is an optional transport, not a second account system.
/// A preview without google-services.json works normally with in-app alerts.
/// Only the unlocked owner may register a device or open an alert.
class PushRegistrationGate extends StatefulWidget {
 const PushRegistrationGate({super.key,required this.child});
 final Widget child;
 @override State<PushRegistrationGate> createState()=>_PushRegistrationGateState();
}

class _PushRegistrationGateState extends State<PushRegistrationGate>
 with WidgetsBindingObserver {
 final db=Supabase.instance.client;
 StreamSubscription<String>? _tokenUpdates;
 StreamSubscription<RemoteMessage>? _openedNotifications;
 bool _initializing=false,_ready=false;
 String? _deviceId;
 @override void initState(){
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  WidgetsBinding.instance.addPostFrameCallback((_){
   if(mounted)unawaited(_start());
  });
 }
 static Future<String> deviceId() async {
  final prefs=SharedPreferencesAsync();
  final old=await prefs.getString('onespace_push_device_id_v1');
  if(old!=null&&Uuid.isValidUUID(fromString:old))return old;
  final id=const Uuid().v4();
  await prefs.setString('onespace_push_device_id_v1',id);
  return id;
 }
 Future<void> _registerToken(String token)async{
  if(!mounted||db.auth.currentUser==null||token.length<24)return;
  final id=_deviceId??await deviceId();
  _deviceId=id;
  try{
   await db.rpc('register_push_device',params:{
    'p_device_id':id,'p_fcm_token':token,'p_platform':Platform.isIOS?'ios':'android',
   });
  }catch(_){
   // In-app alerts remain visible while offline. A later unlock retries.
   debugPrint('OneSpace push-device registration will retry when available.');
  }
 }
 Future<void> _start()async{
  if(_initializing||_ready||!mounted||!(Platform.isAndroid||Platform.isIOS))return;
  _initializing=true;
  try{
   // Without registered Firebase app configuration this gracefully
   // declines to initialize. The prior notification system remains intact.
   await Firebase.initializeApp();
   if(!mounted||db.auth.currentUser==null)return;
   final messaging=FirebaseMessaging.instance;
   final prefs=SharedPreferencesAsync();
   final requested=await prefs.getBool('onespace_push_permission_requested_v1')??false;
   NotificationSettings permission;
   if(!requested){
    permission=await messaging.requestPermission(
     alert:true,badge:true,sound:true,provisional:false);
    await prefs.setBool('onespace_push_permission_requested_v1',true);
   }else{
    permission=await messaging.getNotificationSettings();
   }
   if(permission.authorizationStatus!=AuthorizationStatus.authorized&&
      permission.authorizationStatus!=AuthorizationStatus.provisional)return;
   final token=await messaging.getToken();
   if(token!=null)await _registerToken(token);
   _tokenUpdates=messaging.onTokenRefresh.listen((token){
    unawaited(_registerToken(token));
   });
   _openedNotifications=FirebaseMessaging.onMessageOpenedApp.listen(_onOpen);
   final initial=await messaging.getInitialMessage();
   if(initial!=null&&mounted){
    WidgetsBinding.instance.addPostFrameCallback((_){
     if(mounted)_onOpen(initial);
    });
   }
   _ready=true;
  }catch(_){
   // Firebase is not yet configured, Play Services are unavailable, or the
   // device denied notification permission. Never block login on FCM.
   debugPrint('OneSpace push integration inactive; in-app alerts remain available.');
  }finally{_initializing=false;}
 }
 /// R48: a tapped push opens the exact item (the Activity conversation, the
 /// reminder with its buttons, the gesture pop-up), never just the list.
 void _onOpen(RemoteMessage message){
  if(!mounted||db.auth.currentUser==null)return;
  final type=message.data['type'];
  if(type!='notification'&&type!='summary')return;
  unawaited(openNotificationById(context,
   message.data['notification_id']?.toString(),summary:type=='summary'));
 }
 @override void didChangeAppLifecycleState(AppLifecycleState state){
  if(state==AppLifecycleState.resumed&&_ready&&mounted){
   unawaited(_refreshOnResume());
  }
 }
 Future<void> _refreshOnResume()async{
  try{
   final settings=await FirebaseMessaging.instance.getNotificationSettings();
   if(settings.authorizationStatus==AuthorizationStatus.authorized||
      settings.authorizationStatus==AuthorizationStatus.provisional){
    final token=await FirebaseMessaging.instance.getToken();
    if(token!=null)await _registerToken(token);
   }
  }catch(_){}
 }
 @override void dispose(){
  WidgetsBinding.instance.removeObserver(this);
  _openedNotifications?.cancel();_tokenUpdates?.cancel();
  super.dispose();
 }
 @override Widget build(BuildContext context)=>widget.child;
}

/// Call before an intentional sign-out while the owner still has a valid
/// Supabase session. An inactivity lock must NEVER unregister the device.
Future<void> disableCurrentPushDevice()async{
 try{
  final id=await PushRegistrationGateStateHelpers.savedDeviceId();
  if(id==null)return;
  await Supabase.instance.client.rpc('disable_push_device',
   params:{'p_device_id':id}).timeout(const Duration(seconds:3));
 }catch(_){}
}
class PushRegistrationGateStateHelpers{
 const PushRegistrationGateStateHelpers._();
 static Future<String?> savedDeviceId()async=>
  SharedPreferencesAsync().getString('onespace_push_device_id_v1');
}
