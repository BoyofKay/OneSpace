import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../calendar/calendar_rules.dart';

const tripItemKinds=<String,String>{
 'flight':'Flight','stay':'Accommodation','transport':'Transport',
 'activity':'Things to do','booking':'Reservation','note':'Travel note',
};

class TripItemEditor extends StatefulWidget {
 const TripItemEditor({super.key,required this.tripId,this.existing});
 final String tripId;
 final Map<String,dynamic>? existing;
 @override State<TripItemEditor> createState()=>_TripItemEditorState();
}

class _TripItemEditorState extends State<TripItemEditor> {
 final db=Supabase.instance.client;
 late final TextEditingController title,location,destination,provider;
 late final TextEditingController reference,link,details,cost,currency;
 late String kind;
 DateTime? localDate,endDate;
 TimeOfDay? localTime,endTime;
 bool done=false,saving=false;
 String? error;

 @override void initState(){
  super.initState();
  final e=widget.existing??{};
  title=TextEditingController(text:(e['title']??'').toString());
  location=TextEditingController(text:(e['location']??'').toString());
  destination=TextEditingController(text:(e['destination']??'').toString());
  provider=TextEditingController(text:(e['provider']??'').toString());
  reference=TextEditingController(text:(e['booking_reference']??'').toString());
  link=TextEditingController(text:(e['source_url']??'').toString());
  details=TextEditingController(text:(e['details']??'').toString());
  cost=TextEditingController(text:(e['estimated_cost']??'').toString());
  currency=TextEditingController(text:(e['currency']??'USD').toString());
  kind=(e['kind']??'flight').toString();
  localDate=DateTime.tryParse((e['local_date']??'').toString());
  endDate=DateTime.tryParse((e['end_date']??'').toString());
  localTime=parseLocalTime(e['local_time']);
  endTime=parseLocalTime(e['end_time']);
  done=e['done']==true;
 }

 @override void dispose(){
  for(final c in [title,location,destination,provider,reference,
    link,details,cost,currency]){c.dispose();}
  super.dispose();
 }

 static TimeOfDay? parseLocalTime(Object? raw){
  if(raw==null)return null;
  final bits=raw.toString().split(':');
  if(bits.length<2)return null;
  final h=int.tryParse(bits[0]),m=int.tryParse(bits[1]);
  if(h==null||m==null||h<0||h>23||m<0||m>59)return null;
  return TimeOfDay(hour:h,minute:m);
 }
 static String? writeLocalTime(TimeOfDay? t){
  if(t==null)return null;
  return t.hour.toString().padLeft(2,'0')+':'+
    t.minute.toString().padLeft(2,'0')+':00';
 }

 Future<void> pickDate(bool isEnd)async{
  final today=DateTime.now();
  final d=await showDatePicker(context:context,
    initialDate:(isEnd?endDate:localDate)??today,
    firstDate:DateTime(2000),lastDate:DateTime(2100));
  if(!mounted||d==null)return;
  setState((){if(isEnd){endDate=d;}else{localDate=d;}});
 }
 Future<void> pickTime(bool isEnd)async{
  final t=await showTimePicker(context:context,
   initialTime:(isEnd?endTime:localTime)??TimeOfDay.now());
  if(!mounted||t==null)return;
  setState((){if(isEnd){endTime=t;}else{localTime=t;}});
 }
 Future<void> save() async{
  if(saving)return;
  if(title.text.trim().isEmpty){setState(()=>error='Give this entry a title.');return;}
  if(localDate!=null&&endDate!=null&&endDate!.isBefore(localDate!)){
   setState(()=>error='The end date cannot precede the start date.');return;
  }
  final source=link.text.trim(),url=Uri.tryParse(source);
  if(source.isNotEmpty&&(url==null||!['http','https'].contains(url.scheme)||url.host.isEmpty)){
   setState(()=>error='Use a valid http or https link.');return;
  }
  final amount=cost.text.trim().isEmpty?null:double.tryParse(cost.text.trim());
  if(cost.text.trim().isNotEmpty&&(amount==null||amount<0||amount>9999999999)){
   setState(()=>error='Enter a valid positive cost, or leave it blank.');return;
  }
  final code=currency.text.trim().toUpperCase();
  if(!RegExp(r'^[A-Z]{3}$').hasMatch(code)){
   setState(()=>error='Use a three-letter currency code, for example USD or SAR.');return;
  }
  setState((){saving=true;error=null;});
  try{
   final values=<String,dynamic>{
    'kind':kind,'title':title.text.trim(),
    'location':location.text.trim(),'destination':destination.text.trim(),
    'local_date':localDate==null?null:CalendarRules.sqlDate(localDate!),
    'local_time':writeLocalTime(localTime),
    'end_date':endDate==null?null:CalendarRules.sqlDate(endDate!),
    'end_time':writeLocalTime(endTime),
    'provider':provider.text.trim(),
    'booking_reference':reference.text.trim(),
    'source_url':source,'details':details.text.trim(),
    'estimated_cost':amount,'currency':code,'done':done,
   };
   if(widget.existing==null){
    await db.from('trip_items').insert({...values,'trip_id':widget.tripId});
   }else{
    await db.from('trip_items').update(values).eq('id',widget.existing!['id'])
     .eq('trip_id',widget.tripId);
   }
   if(mounted)Navigator.pop(context,true);
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){
   if(mounted)setState(()=>error='Unable to save the itinerary entry.');
  }finally{
   if(mounted)setState(()=>saving=false);
  }
 }

 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:Text(widget.existing==null?'Add itinerary item':'Edit itinerary item')),
  body:ListView(padding:const EdgeInsets.all(16),children:[
   Text('Keep booking details in one place',
    style:Theme.of(context).textTheme.titleLarge),
   const SizedBox(height:4),
   Text('Departure and arrival dates/times are local to each place, exactly as shown on the booking.'),
   const SizedBox(height:16),
   DropdownButtonFormField<String>(
    initialValue:kind,decoration:const InputDecoration(labelText:'Type',border:OutlineInputBorder()),
    items:[for(final item in tripItemKinds.entries)
     DropdownMenuItem(value:item.key,child:Text(item.value))],
    onChanged:saving?null:(v)=>setState(()=>kind=v??kind)),
   const SizedBox(height:10),
   TextField(controller:title,maxLength:160,
    decoration:const InputDecoration(labelText:'Title',border:OutlineInputBorder())),
   const SizedBox(height:10),
   TextField(controller:location,maxLength:240,
    decoration:const InputDecoration(labelText:'From / location (optional)',border:OutlineInputBorder())),
   const SizedBox(height:10),
   TextField(controller:destination,maxLength:240,
    decoration:const InputDecoration(labelText:'To / destination (optional)',border:OutlineInputBorder())),
   const SizedBox(height:8),
   ListTile(leading:const Icon(Icons.event_outlined),title:const Text('Start / departure date'),
    subtitle:Text(localDate==null?'Not set':CalendarRules.sqlDate(localDate!)),
    onTap:()=>pickDate(false),
    trailing:IconButton(tooltip:'Clear start date',icon:const Icon(Icons.clear),
     onPressed:()=>setState(()=>localDate=null))),
   ListTile(leading:const Icon(Icons.schedule_outlined),title:const Text('Local departure time'),
    subtitle:Text(localTime?.format(context)??'Not set'),
    onTap:()=>pickTime(false),
    trailing:IconButton(tooltip:'Clear start time',icon:const Icon(Icons.clear),
     onPressed:()=>setState(()=>localTime=null))),
   ListTile(leading:const Icon(Icons.event_available_outlined),title:const Text('End / arrival date'),
    subtitle:Text(endDate==null?'Not set':CalendarRules.sqlDate(endDate!)),
    onTap:()=>pickDate(true),
    trailing:IconButton(tooltip:'Clear end date',icon:const Icon(Icons.clear),
     onPressed:()=>setState(()=>endDate=null))),
   ListTile(leading:const Icon(Icons.access_time_outlined),title:const Text('Local arrival time'),
    subtitle:Text(endTime?.format(context)??'Not set'),
    onTap:()=>pickTime(true),
    trailing:IconButton(tooltip:'Clear end time',icon:const Icon(Icons.clear),
     onPressed:()=>setState(()=>endTime=null))),
   const SizedBox(height:8),
   TextField(controller:provider,maxLength:160,
    decoration:const InputDecoration(labelText:'Airline / hotel / provider',border:OutlineInputBorder())),
   const SizedBox(height:10),
   TextField(controller:reference,maxLength:120,
    decoration:const InputDecoration(labelText:'Booking reference (optional)',border:OutlineInputBorder())),
   const SizedBox(height:10),
   TextField(controller:link,maxLength:1800,keyboardType:TextInputType.url,
    decoration:const InputDecoration(labelText:'Booking or itinerary link',border:OutlineInputBorder())),
   const SizedBox(height:10),
   TextField(controller:details,maxLength:5000,maxLines:4,
    decoration:const InputDecoration(labelText:'Notes and details',border:OutlineInputBorder())),
   const SizedBox(height:10),
   Row(children:[
    Expanded(flex:2,child:TextField(controller:cost,keyboardType:const TextInputType.numberWithOptions(decimal:true),
      decoration:const InputDecoration(labelText:'Estimated cost',border:OutlineInputBorder()))),
    const SizedBox(width:10),
    Expanded(child:TextField(controller:currency,maxLength:3,textCapitalization:TextCapitalization.characters,
      decoration:const InputDecoration(labelText:'Currency',border:OutlineInputBorder()))),
   ]),
   SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Completed'),
    value:done,onChanged:(v)=>setState(()=>done=v)),
   if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
   const SizedBox(height:12),
   FilledButton.icon(onPressed:saving?null:save,icon:const Icon(Icons.save_outlined),
    label:Text(saving?'Saving…':'Save itinerary item')),
  ]));
}
