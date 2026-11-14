import 'package:material_ui/material_ui.dart';
import 'checklist_readout_rules.dart';
import 'checklist_speech_bridge.dart';

/// Read-only listening view: does not check off items on someone's behalf.
/// This is an opt-in, foreground-only operation on the phone.
class ChecklistReadoutSheet extends StatefulWidget {
 const ChecklistReadoutSheet({
  super.key,required this.listTitle,required this.items,required this.ownChecks,
 });
 final String listTitle;
 final List<Map<String,dynamic>> items;
 final Map<String,Map<String,dynamic>> ownChecks;
 @override State<ChecklistReadoutSheet> createState()=>_ChecklistReadoutSheetState();
}

class _ChecklistReadoutSheetState extends State<ChecklistReadoutSheet>
 with WidgetsBindingObserver{
 bool remainingOnly=true,reading=false,working=false;
 double speed=1.0;
 int at=0;
 String? error;

 List<String> get steps=>ChecklistReadoutRules.lines(
  widget.items,widget.ownChecks,remainingOnly:remainingOnly);
 @override void initState(){
  super.initState();WidgetsBinding.instance.addObserver(this);
 }
 @override void didChangeAppLifecycleState(AppLifecycleState state){
  if(state!=AppLifecycleState.resumed){
   // Never continue reading a sensitive private checklist after lock.
   ChecklistSpeechBridge.stop();
   if(mounted)setState(()=>reading=false);
  }
 }
 @override void dispose(){
  WidgetsBinding.instance.removeObserver(this);
  ChecklistSpeechBridge.stop();
  super.dispose();
 }
 String get language=>Localizations.localeOf(context).languageCode;
 Future<void> speak(String words)async{
  if(working)return;
  setState((){working=true;error=null;});
  try{
   await ChecklistSpeechBridge.speak(words,language:language,rate:speed);
   if(mounted)setState(()=>reading=true);
  }on PlatformException catch(e){
   if(mounted)setState((){
    reading=false;
    error=e.code=='VOICE_UNAVAILABLE'?
     'Your phone has no working speech voice. Check its text-to-speech settings.':
     'Could not start reading. Try another device voice.';
   });
  }on MissingPluginException{
   if(mounted)setState((){
    reading=false;error='Checklist voice is not supported in this build.';
   });
  }catch(_){
   if(mounted)setState((){
    reading=false;error='The phone could not read this checklist.';
   });
  }finally{
   if(mounted)setState(()=>working=false);
  }
 }
 Future<void> stop()async{
  await ChecklistSpeechBridge.stop();
  if(mounted)setState(()=>reading=false);
 }
 Future<void> move(int next)async{
  final lines=steps;
  if(lines.isEmpty)return;
  setState(()=>at=next.clamp(0,lines.length-1).toInt());
  await speak('Item ${at+1}. ${lines[at]}.');
 }
 @override Widget build(BuildContext context){
  final stepsNow=steps;
  final theme=Theme.of(context);
  final safeIndex=stepsNow.isEmpty?0:at.clamp(0,stepsNow.length-1).toInt();
  return SafeArea(child:Padding(
   padding:EdgeInsets.fromLTRB(16,8,16,
    MediaQuery.viewInsetsOf(context).bottom+20),
   child:ListView(shrinkWrap:true,children:[
    Row(children:[
     const Icon(Icons.record_voice_over_outlined),
     const SizedBox(width:8),
     Expanded(child:Text('Listen to checklist',
      style:theme.textTheme.titleLarge)),
     IconButton(tooltip:'Close voice readout',
      onPressed:()=>Navigator.of(context).pop(),
      icon:const Icon(Icons.close)),
    ]),
    Text(widget.listTitle,style:theme.textTheme.titleMedium),
    const SizedBox(height:6),
    const Text('Uses your phone’s speech engine, which may require internet for some voices. No microphone, recording, or automatic completion.'),
    const SizedBox(height:10),
    SegmentedButton<bool>(
     segments:const [
      ButtonSegment(value:true,label:Text('Still to do')),
      ButtonSegment(value:false,label:Text('All items')),
     ],
     selected:{remainingOnly},
     onSelectionChanged:(values)async{
      await stop();
      if(mounted)setState((){remainingOnly=values.first;at=0;});
     }),
    const SizedBox(height:10),
    Text('${stepsNow.length} item(s) to read'),
    if(stepsNow.isEmpty)
     const Padding(padding:EdgeInsets.symmetric(vertical:10),
      child:Text('No items in this selection.')),
    const SizedBox(height:8),
    Row(children:[
     const Text('Voice speed'),
     Expanded(child:Slider(value:speed,min:0.75,max:1.25,
      divisions:2,label:'${speed.toStringAsFixed(2)}×',
      onChanged:(v)=>setState(()=>speed=v))),
     Text('${speed.toStringAsFixed(2)}×'),
    ]),
    FilledButton.icon(
     onPressed:working||stepsNow.isEmpty?null:()=>speak(
      ChecklistReadoutRules.script(listTitle:widget.listTitle,
       lines:stepsNow,remainingOnly:remainingOnly)),
     icon:const Icon(Icons.play_arrow_outlined),
     label:const Text('Read this checklist aloud'),
    ),
    if(stepsNow.isNotEmpty)...[
     const SizedBox(height:12),
     Text('Step ${safeIndex+1} of ${stepsNow.length}',
      style:theme.textTheme.labelLarge),
     Card(child:Padding(padding:const EdgeInsets.all(16),
      child:Text(stepsNow[safeIndex],style:theme.textTheme.titleMedium))),
     Row(children:[
      IconButton(tooltip:'Previous step',icon:const Icon(Icons.skip_previous),
       onPressed:working||safeIndex==0?null:()=>move(safeIndex-1)),
      Expanded(child:OutlinedButton.icon(
       onPressed:working?null:()=>move(safeIndex),
       icon:const Icon(Icons.replay_outlined),
       label:const Text('Read this step'))),
      IconButton(tooltip:'Next step',icon:const Icon(Icons.skip_next),
       onPressed:working||safeIndex>=stepsNow.length-1?null:
        ()=>move(safeIndex+1)),
     ]),
    ],
    if(reading)TextButton.icon(
     onPressed:stop,icon:const Icon(Icons.stop_circle_outlined),
     label:const Text('Stop reading')),
    if(error!=null)Text(error!,style:TextStyle(
     color:theme.colorScheme.error)),
    const SizedBox(height:8),
    Text('Your progress stays unchanged. Mark items complete in the checklist when ready.',
     style:theme.textTheme.bodySmall),
   ]),
  ));
 }
}
