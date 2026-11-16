import '../../core/preferred_currency.dart';
import '../../core/form_kit.dart';
import '../../core/editor_scaffold.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../calendar/calendar_rules.dart';
import '../../core/responsive_field_pair.dart';
import 'package:onespace/l10n/phrases.dart';
import 'airports.dart';
import 'trip_widgets.dart';

const tripItemKinds=<String,String>{
 'flight':'Flight','stay':'Accommodation','transport':'Transport',
 'activity':'Things to do','booking':'Reservation','note':'Travel note',
};

class TripItemEditor extends StatefulWidget {
 const TripItemEditor({super.key,required this.tripId,this.existing,this.trip});
 final String tripId;
 final Map<String,dynamic>? existing;
 /// R67: the trip, to start a new flight from its airports and dates.
 final Map<String,dynamic>? trip;
 @override State<TripItemEditor> createState()=>_TripItemEditorState();
}

class _TripItemEditorState extends State<TripItemEditor> with FormChangeTracker<TripItemEditor> {
 /// R55: current form values; Save turns on only when they change.
 @override String get signature=>[title.text,location.text,destination.text,provider.text,reference.text,link.text,details.text,cost.text,currency.text,kind,localDate,endDate,localTime,endTime,fromCode,toCode].join('|');

 final db=Supabase.instance.client;
 late final TextEditingController title,location,destination,provider;
 late final TextEditingController reference,link,details,cost,currency;
 late String kind;
 DateTime? localDate,endDate;
 TimeOfDay? localTime,endTime;
 bool saving=false,titleTouched=false;
 String? fromCode,toCode;
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
  currency=TextEditingController(text:(e['currency']??PreferredCurrency.code).toString());
  kind=(e['kind']??'flight').toString();
  localDate=DateTime.tryParse((e['local_date']??'').toString());
  endDate=DateTime.tryParse((e['end_date']??'').toString());
  localTime=parseLocalTime(e['local_time']);
  endTime=parseLocalTime(e['end_time']);
  final t=widget.trip??const {};
  if(widget.existing==null&&(t['travel_mode']??'flight')!='flight')kind='transport';
  if(widget.existing==null&&kind=='flight'){
   location.text=(t['origin']??'').toString();
   destination.text=(t['destination']??'').toString();
   localDate=DateTime.tryParse((t['start_on']??'').toString());
  }
  if(Airports.isCode(location.text))fromCode=location.text;
  if(Airports.isCode(destination.text))toCode=destination.text;
  titleTouched=title.text.trim().isNotEmpty;
  Airports.load().then((_){if(mounted){setState((){});suggestTitle();}});
 }

 /// R67: a flight's title follows its airports ("RUH → PHL") until typed.
 void suggestTitle(){
  if(titleTouched||kind!='flight')return;
  final a=fromCode??location.text.trim(),b=toCode??destination.text.trim();
  if(a.isEmpty&&b.isEmpty)return;
  title.text='${a.isEmpty?'?':a} → ${b.isEmpty?'?':b}';
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
    'estimated_cost':amount,'currency':code,
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

 /// R57: labels follow what the entry is (a flight has airports and an
 /// airline; a stay has check-in/out and a host).
 Map<String,String> get words=>switch(kind){
  'flight'=>{'from':'From airport','to':'To airport','start':'Departs','end':'Arrives',
   'provider':'Airline and flight number','ref':'Booking reference','title':'Flight'},
  'stay'=>{'from':'Address','to':'','start':'Check-in','end':'Check-out',
   'provider':'Hotel or host','ref':'Confirmation number','title':'Where we stay'},
  'transport'=>{'from':'From','to':'To','start':'Departs','end':'Arrives',
   'provider':'Company (train, car, transfer)','ref':'Booking reference','title':'Train, car or transfer'},
  'activity'=>{'from':'Place','to':'','start':'Starts','end':'Ends',
   'provider':'Organizer','ref':'Ticket or booking reference','title':'What we will do'},
  'booking'=>{'from':'Place','to':'','start':'Date','end':'',
   'provider':'Restaurant or venue','ref':'Reservation reference','title':'Reservation'},
  _=>{'from':'','to':'','start':'','end':'','provider':'','ref':'','title':'Note'},
 };

 Widget whenChips(String label,DateTime? date,TimeOfDay? time,bool isEnd){
  final loc=MaterialLocalizations.of(context);
  return Padding(padding:const EdgeInsets.only(bottom:10),child:Row(children:[
   SizedBox(width:92,child:Text(tt(label),style:Theme.of(context).textTheme.labelLarge)),
   Expanded(child:Wrap(spacing:8,runSpacing:6,children:[
    InputChip(avatar:const Icon(Icons.event_outlined,size:18),
     label:Text(tt(date==null?'Date':loc.formatMediumDate(date))),
     onPressed:()=>pickDate(isEnd),
     onDeleted:date==null?null:()=>setState((){if(isEnd){endDate=null;}else{localDate=null;}})),
    InputChip(avatar:const Icon(Icons.schedule,size:18),
     label:Text(tt(time==null?'Time':time.format(context))),
     onPressed:()=>pickTime(isEnd),
     onDeleted:time==null?null:()=>setState((){if(isEnd){endTime=null;}else{localTime=null;}})),
   ])),
  ]));
 }

 @override Widget build(BuildContext context){
  final w=words;
  final isNote=kind=='note';
  return EditorScaffold(title:widget.existing==null?tt('Add to the itinerary'):tt('Edit itinerary entry'),
   isNew:widget.existing==null,isChanged:()=>changed,isComplete:()=>title.text.trim().isNotEmpty,
   listenTo:[title,location,destination,provider,reference,link,details,cost,currency],saving:saving,onSave:save,
   body:ListView(padding:const EdgeInsets.all(18),children:[
   ChoiceRow<String>(label:tt('What is it?'),options:tripItemKinds,selected:kind,
    icons:const {'flight':Icons.flight_outlined,'stay':Icons.hotel_outlined,
     'transport':Icons.directions_car_outlined,'activity':Icons.local_activity_outlined,
     'booking':Icons.restaurant_outlined,'note':Icons.sticky_note_2_outlined},
    onSelected:(v){if(!saving&&v!=null){setState(()=>kind=v);suggestTitle();}}),
   TextField(controller:title,maxLength:160,textCapitalization:TextCapitalization.sentences,
    onChanged:(_)=>titleTouched=true,
    decoration:InputDecoration(labelText:tt('Title *'),hintText:w['title'],border:const OutlineInputBorder())),
   if(!isNote)...[
    FormSection(tt('Where and when')),
    if(kind=='flight')...[
     AirportField(label:tt('From airport'),value:fromCode,onChanged:(v)=>setState((){
      fromCode=v;location.text=v??'';suggestTitle();})),
     AirportField(label:tt('To airport'),value:toCode,icon:Icons.flight_land_outlined,
      onChanged:(v)=>setState((){toCode=v;destination.text=v??'';suggestTitle();})),
    ]else...[
    if(w['from']!.isNotEmpty)Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(
     controller:location,maxLength:240,
     decoration:InputDecoration(labelText:w['from'],prefixIcon:const Icon(Icons.place_outlined),
      border:const OutlineInputBorder()))),
    if(w['to']!.isNotEmpty)Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(
     controller:destination,maxLength:240,
     decoration:InputDecoration(labelText:w['to'],prefixIcon:const Icon(Icons.flag_outlined),
      border:const OutlineInputBorder()))),
    ],
    whenChips(w['start']!,localDate,localTime,false),
    if(w['end']!.isNotEmpty)whenChips(w['end']!,endDate,endTime,true),
    Text(tt('Local times, exactly as on the booking.'),style:Theme.of(context).textTheme.bodySmall),
    FormSection(tt('Booking')),
    TextField(controller:provider,maxLength:160,
     decoration:InputDecoration(labelText:w['provider'],border:const OutlineInputBorder())),
    const SizedBox(height:10),
    TextField(controller:reference,maxLength:120,
     decoration:InputDecoration(labelText:w['ref'],prefixIcon:const Icon(Icons.confirmation_number_outlined),
      border:const OutlineInputBorder())),
    const SizedBox(height:10),
    TextField(controller:link,maxLength:1800,keyboardType:TextInputType.url,
     decoration:InputDecoration(labelText:tt('Link'),prefixIcon:Icon(Icons.link),
      border:OutlineInputBorder())),
    const SizedBox(height:10),
    ResponsiveFieldPair(
     first:TextField(controller:cost,
      keyboardType:const TextInputType.numberWithOptions(decimal:true),
      decoration:InputDecoration(labelText:tt('Cost'),border:OutlineInputBorder())),
     second:TextField(controller:currency,maxLength:3,
      textCapitalization:TextCapitalization.characters,
      decoration:InputDecoration(labelText:tt('Currency'),hintText:tt('USD'),border:OutlineInputBorder())),
    ),
   ],
   FormSection(tt('Notes')),
   TextField(controller:details,maxLength:5000,minLines:2,maxLines:6,
    decoration:InputDecoration(labelText:tt('Notes and details'),alignLabelWithHint:true,
     border:OutlineInputBorder())),
   if(error!=null)Padding(padding:const EdgeInsets.only(top:10),
    child:Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error))),
  ]));
 }
}
