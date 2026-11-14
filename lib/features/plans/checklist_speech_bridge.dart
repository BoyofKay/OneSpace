import 'package:flutter/services.dart';

/// Explicit, device-local speech requests. OneSpace sends no text to its
/// backend and never activates the microphone for checklist playback.
class ChecklistSpeechBridge {
 const ChecklistSpeechBridge._();
 static const channel=MethodChannel('onespace/checklist_speech');

 static Future<void> speak(String text,{
  String language='en', double rate=1,
 }) async{
  if(text.trim().isEmpty)return;
  await channel.invokeMethod<void>('speak',{
   'text':text,'language':language,'rate':rate,
  });
 }

 static Future<void> stop()async{
  try{await channel.invokeMethod<void>('stop');}
  on MissingPluginException{
   // A stopped widget does not need to fail on unsupported platforms.
  }
 }
}
