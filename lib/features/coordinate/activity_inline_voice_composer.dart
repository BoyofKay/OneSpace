import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'activity_voice_rules.dart';
import 'activity_voice_service.dart';

/// Inline chat voice flow: microphone -> recording -> Stop -> Preview/Send
/// or Delete. Never uploads until Send; local draft is kept on upload error.
/// The recording is stopped when OneSpace leaves the foreground.
class ActivityInlineVoiceComposer extends StatefulWidget {
 const ActivityInlineVoiceComposer({
   super.key,required this.activityId,required this.onFinished,
   required this.onCancel,this.replyToId,this.componentId,
 });
 final String activityId;
 final String? replyToId,componentId;
 final VoidCallback onFinished,onCancel;
 @override State<ActivityInlineVoiceComposer> createState()=>
   _ActivityInlineVoiceComposerState();
}

class _ActivityInlineVoiceComposerState extends State<ActivityInlineVoiceComposer>
 with WidgetsBindingObserver {
 final AudioRecorder recorder=AudioRecorder();
 final AudioPlayer player=AudioPlayer();
 Timer? timer;
 DateTime? started;
 String? path,error;
 int duration=0;
 bool recording=false,starting=false,stopping=false,sending=false;
 bool wasBackgrounded=false;
 String? previewedPath;

 @override void initState(){
   super.initState();
   WidgetsBinding.instance.addObserver(this);
   WidgetsBinding.instance.addPostFrameCallback((_){
     if(mounted)unawaited(_start());
   });
 }
 @override void didChangeAppLifecycleState(AppLifecycleState state){
   if(state==AppLifecycleState.paused||
      state==AppLifecycleState.hidden||
      state==AppLifecycleState.detached){
     wasBackgrounded=true;
     if(recording)unawaited(_stop());
   }else if(state==AppLifecycleState.resumed){
     wasBackgrounded=false;
   }
 }
 Future<void> _start() async {
   if(starting||recording||sending||stopping)return;
   setState((){
     starting=true;error=null;
   });
   try{
     if(!await recorder.hasPermission()){
       throw StateError('Allow microphone access to send a voice message.');
     }
     if(!mounted||wasBackgrounded)return;
     await _deleteDraft();
     final tmp=await getTemporaryDirectory();
     final next=tmp.path+'/onespace-chat-'+const Uuid().v4()+'.m4a';
     await recorder.start(const RecordConfig(
       encoder:AudioEncoder.aacLc,
       bitRate:64000,sampleRate:44100,numChannels:1,
     ),path:next);
     if(!mounted){
       await recorder.cancel();
       return;
     }
     setState((){
       path=next;
       started=DateTime.now();
       duration=0;
       recording=true;
       wasBackgrounded=false;
     });
     timer?.cancel();
     timer=Timer.periodic(const Duration(seconds:1),(_){
       if(!mounted||!recording||started==null)return;
       final seconds=DateTime.now().difference(started!).inSeconds;
       if(seconds>=ActivityVoiceRules.maxSeconds){
         unawaited(_stop());
       }else{
         setState(()=>duration=seconds);
       }
     });
   }catch(e){
     if(mounted)setState(()=>error='Microphone unavailable. Check permission and try again.');
   }finally{
     if(mounted)setState(()=>starting=false);
   }
 }
 Future<void> _stop() async {
   if(!recording||stopping||sending)return;
   setState(()=>stopping=true);
   timer?.cancel();
   try{
     final recorded=await recorder.stop();
     final elapsed=started==null?0:DateTime.now().difference(started!).inSeconds;
     if(mounted)setState((){
       path=recorded;
       duration=elapsed<0?0:(elapsed>ActivityVoiceRules.maxSeconds?
         ActivityVoiceRules.maxSeconds:elapsed);
       recording=false;
       if(recorded==null||elapsed<1){
         error='Record at least one second.';
       }
     });
   }catch(e){
     if(mounted)setState((){
       recording=false;
       error='Could not stop recording. Try again.';
     });
   }finally{
     if(mounted)setState(()=>stopping=false);
   }
 }
 Future<void> _togglePreview() async {
   final local=path;
   if(local==null||recording||sending||stopping)return;
   try{
     if(player.playing){
       await player.pause();
     }else{
       if(previewedPath!=local){
         await player.setFilePath(local);
         previewedPath=local;
       }
       if(player.processingState==ProcessingState.completed){
         await player.seek(Duration.zero);
       }
       unawaited(player.play());
     }
     if(mounted)setState((){});
   }catch(e){
     if(mounted)setState(()=>error='Could not preview the recording.');
   }
 }
 Future<void> _deleteDraft() async {
   try{await player.stop();}catch(_){}
   final filePath=path;
   path=null;
   previewedPath=null;
   if(filePath!=null){
     try{
       final file=File(filePath);
       if(await file.exists())await file.delete();
     }catch(_){}
   }
 }
 Future<void> _cancel() async {
   if(sending||stopping)return;
   timer?.cancel();
   if(recording){
     try{await recorder.cancel();}catch(_){}
     recording=false;
   }
   await _deleteDraft();
   if(mounted)widget.onCancel();
 }
 Future<void> _send() async {
   if(path==null||recording||stopping||sending||duration<1)return;
   setState((){
     sending=true;error=null;
   });
   try{
     final bytes=await File(path!).readAsBytes();
     await ActivityVoiceService(Supabase.instance.client).send(
       bytes:bytes,seconds:duration,
       activityId:widget.activityId,
       destination:VoiceDestination.comment,
       replyToCommentId:widget.replyToId,
       relatedComponentId:widget.componentId,
     );
     await _deleteDraft();
     if(mounted)widget.onFinished();
   }catch(_){
     if(mounted)setState(()=>
       error='Could not send. Your recording is saved here to retry.');
   }finally{
     if(mounted)setState(()=>sending=false);
   }
 }
 Future<void> _deleteIfExists(String local) async {
   try{
     final file=File(local);
     if(await file.exists())await file.delete();
   }catch(_){}
 }
 @override void dispose(){
   WidgetsBinding.instance.removeObserver(this);
   timer?.cancel();
   if(recording)unawaited(recorder.cancel());
   unawaited(recorder.dispose());
   unawaited(player.dispose());
   final local=path;
   if(local!=null){
     unawaited(_deleteIfExists(local));
   }
   super.dispose();
 }
 @override Widget build(BuildContext context){
   final scheme=Theme.of(context).colorScheme;
   final ready=path!=null&&!recording&&duration>=1;
   return Column(mainAxisSize:MainAxisSize.min,children:[
     if(error!=null)Text(error!,
       style:TextStyle(color:scheme.error),
       maxLines:3,overflow:TextOverflow.ellipsis),
     Row(children:[
       IconButton(
         tooltip:'Discard voice message',
         icon:const Icon(Icons.delete_outline),
         onPressed:sending||stopping?null:_cancel),
       if(recording)...[
         Icon(Icons.fiber_manual_record,color:scheme.error,size:17),
         const SizedBox(width:7),
         Expanded(child:Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,
           children:[for(var i=0;i<17;i++)Container(
             width:3,
             height:7+(i%4)*5,
             decoration:BoxDecoration(
               color:scheme.primary.withValues(alpha:.7),
               borderRadius:BorderRadius.circular(3)),
           )],
         )),
       ]else if(ready)...[
         IconButton(
           tooltip:player.playing?'Pause preview':'Play preview',
           onPressed:sending?null:_togglePreview,
           icon:Icon(player.playing?Icons.pause_circle_filled:
             Icons.play_circle_filled)),
         Expanded(child:Text('Voice message ready',
           maxLines:1,overflow:TextOverflow.ellipsis)),
       ]else...[
         const Icon(Icons.mic_none_outlined),
         const SizedBox(width:8),
         const Expanded(child:Text('Opening microphone…',
           maxLines:1)),
       ],
       Text(ActivityVoiceRules.durationLabel(duration),
         style:Theme.of(context).textTheme.labelMedium),
       const SizedBox(width:4),
       if(recording)
         IconButton(
           tooltip:'Stop recording',
           onPressed:stopping?null:_stop,
           icon:const Icon(Icons.stop_circle_outlined))
       else if(ready)
         IconButton(
           tooltip:'Send voice message',
           onPressed:sending?null:_send,
           icon:sending?const SizedBox.square(dimension:18,
             child:CircularProgressIndicator(strokeWidth:2)):
             const Icon(Icons.send_rounded))
       else IconButton(
         tooltip:'Record again',
         onPressed:starting||stopping?null:_start,
         icon:const Icon(Icons.mic_rounded)),
     ]),
   ]);
 }
}
