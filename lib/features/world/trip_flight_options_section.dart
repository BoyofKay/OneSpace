import '../../core/form_kit.dart';
import '../../core/editor_scaffold.dart';
import '../../core/item_menu.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:onespace/l10n/phrases.dart';

import 'airports.dart';
import 'flight_links.dart';
import 'trip_widgets.dart';

const flightOptionStatuses=<String,String>{
 'considering':'Considering','proposed':'Proposed','booked':'Booked','rejected':'Not selected'};

String _sqlDate(DateTime d)=>d.toIso8601String().substring(0,10);

/// The trip's Google Flights search, filled in from the trip (R67).
Uri tripGoogleFlights(Map<String,dynamic> trip)=>FlightLinks.googleFlights(
 from:(trip['origin']??'').toString(),to:(trip['destination']??'').toString(),
 depart:DateTime.tryParse((trip['start_on']??'').toString()),
 back:DateTime.tryParse((trip['end_on']??'').toString()),
 oneWay:trip['trip_type']=='one_way',
 adults:(trip['adults'] as num?)?.toInt()??1,
 children:(trip['children'] as num?)?.toInt()??0,
 infants:(trip['infants'] as num?)?.toInt()??0);

/// Reads a shared or pasted flight, using the airport list for codes/cities.
Future<FlightDraft> readFlight(String text)async{
 final all=await Airports.load();
 return FlightLinks.parse(text,
  isAirport:(c)=>Airports.byCode(c)!=null,
  cityCode:(name){
   final hits=Airports.search(all,name,limit:1);
   return hits.isEmpty?null:hits.first.code;
  });
}

/// R67: the flight option page (add, edit, or fill from a shared flight).
/// Saves to the database itself; returns true when something was saved.
Future<bool> editFlightOption(BuildContext context,{required String tripId,
  required Map<String,dynamic> trip,Map<String,dynamic>? prior,FlightDraft? draft})async{
 final db=Supabase.instance.client;
 final oneWay=trip['trip_type']=='one_way';
 var title=(prior?['title']??'').toString();
 var link=(prior?['booking_link']??draft?.link??'').toString();
 var airline=(prior?['airline']??draft?.airline??'').toString();
 String? origin=(prior?['origin']??draft?.origin??trip['origin'])?.toString();
 String? destination=(prior?['destination']??draft?.destination??trip['destination'])?.toString();
 var departure=DateTime.tryParse((prior?['departure_on']??'').toString())??draft?.departure??
  DateTime.tryParse((trip['start_on']??'').toString());
 var back=DateTime.tryParse((prior?['return_on']??'').toString())??draft?.returnOn??
  (oneWay?null:DateTime.tryParse((trip['end_on']??'').toString()));
 int? stops=(prior?['stops'] as num?)?.toInt()??draft?.stops;
 var cabin=(prior?['cabin_bags'] as num?)?.toInt()??1;
 var checked=(prior?['checked_bags'] as num?)?.toInt()??0;
 var seat=prior?['seat_included']==true;
 var seatNumber=(prior?['seat_number']??'').toString();
 final oldBaggage=(prior?['baggage_details']??'').toString();
 var price=(prior?['price']??draft?.price??'').toString();
 var currency=(prior?['currency']??draft?.currency??'SAR').toString();
 var score=(prior?['preference_score'] as num?)?.toInt();
 var notes=(prior?['notes']??'').toString();
 var status=(prior?['status']??'considering').toString();
 String? problem;
 final linkCtl=TextEditingController(text:link);
 final airlineCtl=TextEditingController(text:airline);
 final priceCtl=TextEditingController(text:price);

 Future<void> fillFromLink(void Function(void Function()) change)async{
  final d=await readFlight(linkCtl.text);
  change((){
   if(d.origin!=null)origin=d.origin;
   if(d.destination!=null)destination=d.destination;
   if(d.departure!=null)departure=d.departure;
   if(d.returnOn!=null&&!oneWay)back=d.returnOn;
   if(d.airline!=null){airline=d.airline!;airlineCtl.text=d.airline!;}
   if(d.stops!=null)stops=d.stops;
   if(d.price!=null){price=d.price!.toStringAsFixed(d.price!%1==0?0:2);priceCtl.text=price;}
   if(d.currency!=null)currency=d.currency!;
   problem=d.isEmpty?'Nothing could be read from this link. Fill the details by hand.':null;
  });
 }

 final saved=await Navigator.of(context).push<Map<String,dynamic>>(MaterialPageRoute(fullscreenDialog:true,
  builder:(ctx)=>StatefulBuilder(builder:(ctx,change)=>EditorPage(
   title:Text(tt(prior==null?'Add a flight option':'Edit flight option')),
   content:SizedBox(width:540,child:SingleChildScrollView(child:Column(
    crossAxisAlignment:CrossAxisAlignment.stretch,mainAxisSize:MainAxisSize.min,children:[
     TextField(controller:linkCtl,maxLength:1800,keyboardType:TextInputType.url,
      onChanged:(v)=>link=v,
      decoration:InputDecoration(labelText:tt('Link (Google Flights, airline or booking site)'),
       prefixIcon:const Icon(Icons.link),
       suffixIcon:IconButton(tooltip:tt('Fill from link'),icon:const Icon(Icons.auto_fix_high_outlined),
        onPressed:()=>fillFromLink(change)),
       border:const OutlineInputBorder())),
     TextFormField(initialValue:title,maxLength:160,onChanged:(v)=>title=v,
      decoration:InputDecoration(labelText:tt('Option name'),
       hintText:tt('Leave empty to use the airports and airline'),border:const OutlineInputBorder())),
     TextField(controller:airlineCtl,maxLength:140,onChanged:(v)=>airline=v,
      decoration:InputDecoration(labelText:tt('Airline'),prefixIcon:const Icon(Icons.airlines_outlined),
       border:const OutlineInputBorder())),
     AirportField(label:tt('From'),value:origin,onChanged:(v)=>change(()=>origin=v)),
     AirportField(label:tt('To'),value:destination,icon:Icons.flight_land_outlined,
      onChanged:(v)=>change(()=>destination=v)),
     DateField(label:tt('Depart'),value:departure,first:DateTime(2020),last:DateTime(2100),
      onChanged:(v)=>change(()=>departure=v)),
     if(!oneWay)DateField(label:tt('Return'),value:back,first:departure??DateTime(2020),last:DateTime(2100),
      onChanged:(v)=>change(()=>back=v)),
     ChoiceRow<int>(label:tt('Stops'),options:const {0:'Nonstop',1:'1 stop',2:'2+ stops'},
      selected:stops==null?null:(stops!>2?2:stops),allowNone:true,
      onSelected:(v)=>change(()=>stops=v)),
     FormSection(tt('Baggage and seat')),
     CountStepper(label:tt('Cabin bags'),value:cabin,icon:Icons.work_outline,
      onChanged:(v)=>change(()=>cabin=v)),
     CountStepper(label:tt('Checked bags'),value:checked,icon:Icons.luggage_outlined,
      onChanged:(v)=>change(()=>checked=v)),
     Align(alignment:AlignmentDirectional.centerStart,child:OptionChip(label:tt('Seat chosen'),
      icon:Icons.airline_seat_recline_normal_outlined,value:seat,
      onChanged:(v)=>change(()=>seat=v))),
     if(seat)Padding(padding:const EdgeInsets.only(top:8),child:TextFormField(initialValue:seatNumber,
      maxLength:40,onChanged:(v)=>seatNumber=v,
      decoration:InputDecoration(labelText:tt('Seat number'),hintText:tt('14A'),
       border:const OutlineInputBorder()))),
     if(oldBaggage.isNotEmpty)Padding(padding:const EdgeInsets.only(top:6),
      child:Text(tt('Earlier note: ')+oldBaggage,style:Theme.of(ctx).textTheme.bodySmall)),
     FormSection(tt('Price')),
     Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Expanded(flex:3,child:TextField(controller:priceCtl,
       keyboardType:const TextInputType.numberWithOptions(decimal:true),onChanged:(v)=>price=v,
       decoration:InputDecoration(labelText:tt('Price seen'),border:const OutlineInputBorder()))),
      const SizedBox(width:10),
      Expanded(flex:2,child:TextFormField(key:ValueKey(currency),initialValue:currency,maxLength:3,
       textCapitalization:TextCapitalization.characters,onChanged:(v)=>currency=v,
       decoration:InputDecoration(labelText:tt('Currency'),border:const OutlineInputBorder()))),
     ]),
     Text(tt('My preference'),style:Theme.of(ctx).textTheme.labelLarge),
     StarRating(value:score,onChanged:(v)=>change(()=>score=v)),
     const SizedBox(height:10),
     ChoiceRow<String>(label:tt('Status'),options:flightOptionStatuses,
      icons:const {'considering':Icons.help_outline,'proposed':Icons.thumb_up_outlined,
       'booked':Icons.confirmation_number_outlined,'rejected':Icons.block},
      selected:status,onSelected:(v)=>change(()=>status=v??status)),
     TextFormField(initialValue:notes,maxLength:2200,maxLines:3,onChanged:(v)=>notes=v,
      decoration:InputDecoration(labelText:tt('Pros, cons and notes'),border:const OutlineInputBorder())),
     if(problem!=null)Text(tt(problem!),style:TextStyle(color:Theme.of(ctx).colorScheme.error)),
   ]))),
   actions:[
    TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(tt('Cancel'))),
    FilledButton(onPressed:(){
     final numeric=price.trim().isEmpty?null:double.tryParse(price.trim().replaceAll(',',''));
     final code=currency.trim().toUpperCase();
     final uri=Uri.tryParse(link.trim());
     String? why;
     if(price.trim().isNotEmpty&&(numeric==null||numeric<0||numeric>999999999.99))why='Check the price.';
     if(!RegExp(r'^[A-Z]{3}$').hasMatch(code))why='Use a 3-letter currency, for example SAR or USD.';
     if(link.trim().isNotEmpty&&(uri==null||!['https','http'].contains(uri.scheme)||uri.host.isEmpty))why='Check the link.';
     if(departure!=null&&back!=null&&back!.isBefore(departure!))why='The return cannot be before the departure.';
     if(why!=null){change(()=>problem=why);return;}
     final autoTitle=FlightDraft(origin:origin,destination:destination,
      airline:airline.trim().isEmpty?null:airline.trim()).title;
     final name=title.trim().isNotEmpty?title.trim():(autoTitle.isNotEmpty?autoTitle:'Flight option');
     Navigator.pop(ctx,<String,dynamic>{
      'title':name,'provider':FlightLinks.providerFor(link.trim())??'',
      'airline':airline.trim(),'origin':(origin??'').trim(),'destination':(destination??'').trim(),
      'departure_on':departure==null?null:_sqlDate(departure!),
      'return_on':back==null||oneWay?null:_sqlDate(back!),
      'stops':stops,'cabin_bags':cabin,'checked_bags':checked,
      'seat_included':seat,'seat_number':seat?seatNumber.trim():'',
      'price':numeric,'currency':code,'preference_score':score,
      'booking_link':link.trim(),'status':status,'notes':notes.trim(),
     });
    },child:Text(tt('Save'))),
   ],
  )))));
 linkCtl.dispose();airlineCtl.dispose();priceCtl.dispose();
 if(saved==null||!context.mounted)return false;
 final messenger=ScaffoldMessenger.of(context);
 try{
  Map<String,dynamic> row;
  if(prior==null){
   row=await db.from('trip_flight_options').insert({...saved,'trip_id':tripId}).select().single();
  }else{
   row=await db.from('trip_flight_options').update(saved)
    .eq('id',prior['id']).eq('trip_id',tripId).select().single();
  }
  // A booked flight gives the trip its dates when it has none yet.
  if(saved['status']=='booked'&&trip['start_on']==null&&saved['departure_on']!=null){
   await db.from('shared_trips').update({'start_on':saved['departure_on'],
    if(saved['return_on']!=null&&trip['end_on']==null)'end_on':saved['return_on']}).eq('id',tripId);
  }
  if(saved['status']=='booked'&&prior?['status']!='booked'&&context.mounted){
   await addFlightToItinerary(context,tripId,row);
  }
  return true;
 }on PostgrestException catch(e){
  messenger.showSnackBar(SnackBar(content:Text(e.message)));
 }catch(_){
  messenger.showSnackBar(SnackBar(content:Text(tt('Flight option could not be saved.'))));
 }
 return false;
}

/// A booked option becomes a flight in the itinerary (asks first).
Future<void> addFlightToItinerary(BuildContext context,String tripId,Map<String,dynamic> row)async{
 final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
  title:Text(tt('Add this flight to the itinerary?')),
  content:Text(tt('The booked details are copied into the trip. Nothing is bought or checked in.')),
  actions:[
   TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(tt('Not now'))),
   FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(tt('Add to itinerary'))),
  ]));
 if(ok!=true||!context.mounted)return;
 final messenger=ScaffoldMessenger.of(context);
 String bags(){
  final c=(row['cabin_bags'] as num?)?.toInt(),k=(row['checked_bags'] as num?)?.toInt();
  return [if(c!=null)'Cabin bags: $c',if(k!=null)'Checked bags: $k',
   if(row['seat_included']==true)'Seat: ${(row['seat_number']??'').toString().isEmpty?'chosen':row['seat_number']}'].join(' · ');
 }
 try{
  await Supabase.instance.client.from('trip_items').insert({
   'trip_id':tripId,'kind':'flight','title':row['title'],
   'location':row['origin']??'','destination':row['destination']??'',
   'local_date':row['departure_on'],
   'provider':(row['airline']??'').toString().isNotEmpty?row['airline']:row['provider']??'',
   'source_url':row['booking_link']??'',
   'estimated_cost':row['price'],'currency':row['currency']??'USD',
   'details':[
    if(bags().isNotEmpty)bags(),
    if((row['notes']??'').toString().isNotEmpty)row['notes'].toString(),
   ].join('\n'),
  });
  messenger.showSnackBar(SnackBar(content:Text(tt('Added to the itinerary.'))));
 }on PostgrestException catch(e){
  messenger.showSnackBar(SnackBar(content:Text(e.message)));
 }catch(_){
  messenger.showSnackBar(SnackBar(content:Text(tt('Could not add it to the itinerary.'))));
 }
}

/// A research shortlist for comparing possible flights before booking.
/// Prices are saved snapshots, not live airline prices.
class TripFlightOptionsSection extends StatefulWidget {
 const TripFlightOptionsSection({super.key,required this.tripId,required this.trip});
 final String tripId;
 final Map<String,dynamic> trip;
 @override State<TripFlightOptionsSection> createState()=>_TripFlightOptionsSectionState();
}
class _TripFlightOptionsSectionState extends State<TripFlightOptionsSection>{
 final db=Supabase.instance.client;
 late Stream<List<Map<String,dynamic>>> changes;
 final picked=<String>{};
 bool busy=false,showArchived=false;
 String? error;
 @override void initState(){
  super.initState();changes=_stream();
  Airports.load().then((_){if(mounted)setState((){});});
 }
 Stream<List<Map<String,dynamic>>> _stream()=>db.from('trip_flight_options')
  .stream(primaryKey:['id']).eq('trip_id',widget.tripId)
  .order('updated_at',ascending:false);
 @override void didUpdateWidget(covariant TripFlightOptionsSection old){
  super.didUpdateWidget(old);
  if(widget.tripId!=old.tripId){picked.clear();changes=_stream();}
 }
 Future<void> open(String target)async{
  final uri=Uri.tryParse(target);
  if(uri==null||!['https','http'].contains(uri.scheme)||uri.host.isEmpty)return;
  try{await launchUrl(uri,mode:LaunchMode.externalApplication);}
  catch(_){if(mounted)setState(()=>error='Could not open this link.');}
 }
 Future<void> pasteFlight()async{
  final clip=(await Clipboard.getData('text/plain'))?.text??'';
  if(!mounted)return;
  if(clip.trim().isEmpty){
   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(
    tt('Copy a flight link first (in Google Flights: Share › Copy link).'))));
   return;
  }
  final draft=await readFlight(clip);
  if(!mounted)return;
  await editFlightOption(context,tripId:widget.tripId,trip:widget.trip,draft:draft);
 }
 Future<void> archive(Map<String,dynamic> row)async{
  if(busy)return;
  setState((){busy=true;error=null;});
  try{
   await db.from('trip_flight_options').update({
    'archived_at':row['archived_at']==null?DateTime.now().toUtc().toIso8601String():null,
   }).eq('id',row['id']).eq('trip_id',widget.tripId);
  }on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Flight option could not be saved.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 String _money(Map<String,dynamic> row)=>row['price']==null?'':
  '${row['currency']} ${(row['price'] as num).toStringAsFixed((row['price'] as num)%1==0?0:2)}';
 String _stops(Object? s)=>switch((s as num?)?.toInt()){null=>'',0=>'Nonstop',1=>'1 stop',_=>'2+ stops'};

 Widget card(Map<String,dynamic> row){
  final theme=Theme.of(context);
  final removed=row['archived_at']!=null;
  final bags=[
   if(row['cabin_bags']!=null)'${row['cabin_bags']} cabin',
   if(row['checked_bags']!=null)'${row['checked_bags']} checked',
  ].join(' + ');
  return Card(elevation:0,child:Padding(padding:const EdgeInsets.fromLTRB(4,6,4,8),
   child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[
     Checkbox(value:picked.contains(row['id'].toString()),
      onChanged:(v)=>setState((){
       if(v==true){picked.add(row['id'].toString());}else{picked.remove(row['id'].toString());}
      })),
     Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(tt(row['title'].toString()),style:theme.textTheme.titleMedium),
      Text(tt([
       flightOptionStatuses[row['status']]??'Considering',
       if(_money(row).isNotEmpty)_money(row),
       if(row['preference_score']!=null)'★ ${row['preference_score']}',
       if(removed)'Removed',
      ].join(' · ')),style:theme.textTheme.bodySmall),
     ])),
     AnchoredMenuButton<String>(tooltip:tt('More'),
      onSelected:(v)async{
       if(v=='itinerary'){await addFlightToItinerary(context,widget.tripId,row);}
       else if(v=='link'){open(row['booking_link'].toString());}
       else if(v=='edit'){await editFlightOption(context,tripId:widget.tripId,trip:widget.trip,prior:row);}
       else if(v=='remove'){archive(row);}
      },
      itemBuilder:(_)=>[
       if(row['status']=='booked'&&!removed)iconMenuItem('itinerary',Icons.playlist_add,'Add to itinerary'),
       if((row['booking_link']??'').toString().isNotEmpty)iconMenuItem('link',Icons.open_in_new,'Open link'),
       if(!removed)iconMenuItem('edit',MenuIcons.edit,'Edit'),
       iconMenuItem('remove',removed?MenuIcons.restore:MenuIcons.remove,removed?'Restore':'Remove'),
      ]),
    ]),
    Padding(padding:const EdgeInsetsDirectional.only(start:12,end:12),child:Wrap(spacing:12,runSpacing:2,children:[
     if((row['origin']??'').toString().isNotEmpty||(row['destination']??'').toString().isNotEmpty)
      Text('${Airports.label(row['origin']?.toString())} → ${Airports.label(row['destination']?.toString())}'),
     if(row['departure_on']!=null)Text(tt('Depart ')+row['departure_on'].toString()+
      (row['return_on']==null?'':tt(' · Return ')+row['return_on'].toString())),
     if(_stops(row['stops']).isNotEmpty)Text(tt(_stops(row['stops']))),
     if((row['airline']??'').toString().isNotEmpty)Text(tt(row['airline'].toString())),
     if(bags.isNotEmpty)Text(tt('Bags: ')+bags),
     if(row['seat_included']==true)Text(tt('Seat ')+(row['seat_number']??'').toString()),
     if((row['provider']??'').toString().isNotEmpty)Text(tt('via ')+row['provider'].toString(),
      style:theme.textTheme.bodySmall),
    ])),
    if((row['notes']??'').toString().isNotEmpty)Padding(padding:const EdgeInsetsDirectional.fromSTEB(12,4,12,0),
     child:Text(tt(row['notes'].toString()),maxLines:3,overflow:TextOverflow.ellipsis)),
   ])));
 }

 @override Widget build(BuildContext context)=>StreamBuilder<List<Map<String,dynamic>>>(
  stream:changes,builder:(context,snapshot){
   final rows=List<Map<String,dynamic>>.from(snapshot.data??const []);
   final shown=rows.where((r)=>showArchived||r['archived_at']==null).toList();
   final selected=shown.where((r)=>picked.contains(r['id'].toString())).toList();
   final priceRanges=<String,List<double>>{};
   for(final row in selected){
    final amount=(row['price'] as num?)?.toDouble();
    if(amount!=null)priceRanges.putIfAbsent(row['currency'].toString(),()=>[]).add(amount);
   }
   return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Wrap(spacing:8,runSpacing:6,children:[
     FilledButton.tonalIcon(onPressed:()=>open(tripGoogleFlights(widget.trip).toString()),
      icon:const Icon(Icons.travel_explore),label:Text(tt('Search on Google Flights'))),
     OutlinedButton.icon(onPressed:busy?null:pasteFlight,
      icon:const Icon(Icons.content_paste_go_outlined),label:Text(tt('Paste a flight'))),
     OutlinedButton.icon(onPressed:busy?null:()=>editFlightOption(context,tripId:widget.tripId,trip:widget.trip),
      icon:const Icon(Icons.add),label:Text(tt('Add by hand'))),
    ]),
    const SizedBox(height:6),
    Text(tt('Found one you like? In Google Flights tap Share › OneSpace (or copy the link and tap Paste a flight).'),
     style:Theme.of(context).textTheme.bodySmall),
    if(rows.any((r)=>r['archived_at']!=null))Align(alignment:AlignmentDirectional.centerStart,
     child:OptionChip(label:tt('Show removed'),icon:Icons.delete_outline,
      value:showArchived,onChanged:(v)=>setState(()=>showArchived=v))),
    if(snapshot.hasError)Text(tt('Flight options could not load.')),
    if(!snapshot.hasData)const LinearProgressIndicator(),
    for(final row in shown)card(row),
    if(selected.length>1)Card(child:Padding(padding:const EdgeInsets.all(12),
     child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(tt('Comparing ')+selected.length.toString()+tt(' flights'),
       style:Theme.of(context).textTheme.titleMedium),
      for(final row in selected)ListTile(dense:true,contentPadding:EdgeInsets.zero,
       title:Text(tt(row['title'].toString())),
       subtitle:Text(tt([
        if(_money(row).isNotEmpty)_money(row),
        if(_stops(row['stops']).isNotEmpty)_stops(row['stops']),
        if(row['checked_bags']!=null)'${row['checked_bags']} checked',
        if(row['preference_score']!=null)'★ ${row['preference_score']}',
       ].join(' · ')))),
      for(final entry in priceRanges.entries)Text(
       tt(entry.key+' price range: '+(entry.value.reduce((a,b)=>a<b?a:b)).toStringAsFixed(0)+
       ' – '+(entry.value.reduce((a,b)=>a>b?a:b)).toStringAsFixed(0))),
      Text(tt('Prices are what you saw when saving, not live prices.'),
       style:Theme.of(context).textTheme.bodySmall),
     ]))),
    if(error!=null)Text(tt(error!),style:TextStyle(color:Theme.of(context).colorScheme.error)),
    if(busy)const LinearProgressIndicator(),
   ]);
  },
 );
}
