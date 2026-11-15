import '../../core/editor_scaffold.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// A research shortlist for comparing possible flights before booking.
/// Prices are manually saved snapshots; not real-time airline availability.
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
 }
 Stream<List<Map<String,dynamic>>> _stream()=>db.from('trip_flight_options')
  .stream(primaryKey:['id']).eq('trip_id',widget.tripId)
  .order('updated_at',ascending:false);
 @override void didUpdateWidget(covariant TripFlightOptionsSection old){
  super.didUpdateWidget(old);
  if(widget.tripId!=old.tripId){picked.clear();changes=_stream();}
 }
 String date(Object? x)=>x==null?'Flexible / to decide':x.toString();
 Future<void> open(String target)async{
  final uri=Uri.tryParse(target);
  if(uri==null||!['https','http'].contains(uri.scheme)||uri.host.isEmpty)return;
  try{await launchUrl(uri,mode:LaunchMode.externalApplication);}
  catch(_){if(mounted)setState(()=>error='Unable to open that airline link.');}
 }
 Future<void> editor([Map<String,dynamic>? prior])async{
  var title=(prior?['title']??'').toString();
  var provider=(prior?['provider']??'').toString();
  var airline=(prior?['airline']??'').toString();
  var origin=(prior?['origin']??widget.trip['origin']??'').toString();
  var destination=(prior?['destination']??widget.trip['destination']??'').toString();
  var departure=DateTime.tryParse((prior?['departure_on']??'').toString());
  var arrival=DateTime.tryParse((prior?['return_on']??'').toString());
  var flexible=prior?['flexible_dates']==true;
  var stops=(prior?['stops']??'').toString();
  var baggage=(prior?['baggage_details']??'').toString();
  var price=(prior?['price']??'').toString();
  var currency=(prior?['currency']??'USD').toString();
  var score=(prior?['preference_score'] as num?)?.toInt();
  var link=(prior?['booking_link']??'').toString();
  var notes=(prior?['notes']??'').toString();
  var status=(prior?['status']??'considering').toString();
  final result=await Navigator.of(context).push<Map<String,dynamic>>(MaterialPageRoute<Map<String,dynamic>>(fullscreenDialog:true,builder:(ctx)=>StatefulBuilder(builder:(ctx,change)=>EditorPage(
    title:Text(prior==null?'Add new flight option':'Edit flight option'),
    content:SizedBox(width:530,child:SingleChildScrollView(child:Column(
     mainAxisSize:MainAxisSize.min,children:[
      TextFormField(initialValue:title,maxLength:160,
       onChanged:(v)=>title=v,decoration:const InputDecoration(labelText:'Option name *')),
      TextFormField(initialValue:provider,maxLength:140,
       onChanged:(v)=>provider=v,decoration:const InputDecoration(labelText:'Website / search source')),
      TextFormField(initialValue:airline,maxLength:140,
       onChanged:(v)=>airline=v,decoration:const InputDecoration(labelText:'Airline')),
      TextFormField(initialValue:origin,maxLength:180,onChanged:(v)=>origin=v,
       decoration:const InputDecoration(labelText:'From / departure airport')),
      TextFormField(initialValue:destination,maxLength:180,onChanged:(v)=>destination=v,
       decoration:const InputDecoration(labelText:'To / destination airport')),
      Wrap(spacing:8,children:[
       OutlinedButton.icon(
        icon:const Icon(Icons.event),label:Text('Depart: '+date(departure?.toIso8601String().substring(0,10))),
        onPressed:()async{
         final d=await showDatePicker(context:ctx,initialDate:departure??DateTime.now(),
          firstDate:DateTime(2020),lastDate:DateTime(2100));
         if(d!=null)change(()=>departure=d);
        }),
       OutlinedButton.icon(
        icon:const Icon(Icons.event),label:Text('Return: '+date(arrival?.toIso8601String().substring(0,10))),
        onPressed:()async{
         final d=await showDatePicker(context:ctx,initialDate:arrival??departure??DateTime.now(),
          firstDate:DateTime(2020),lastDate:DateTime(2100));
         if(d!=null)change(()=>arrival=d);
        }),
      ]),
      CheckboxListTile(value:flexible,contentPadding:EdgeInsets.zero,
       title:const Text('Dates are flexible'),
       onChanged:(v)=>change(()=>flexible=v??false)),
      TextFormField(initialValue:stops,
       keyboardType:TextInputType.number,onChanged:(v)=>stops=v,
       decoration:const InputDecoration(labelText:'Number of stops (optional)')),
      TextFormField(initialValue:baggage,maxLines:2,maxLength:800,
       onChanged:(v)=>baggage=v,decoration:const InputDecoration(
        labelText:'Cabin / checked baggage and seat details')),
      TextFormField(initialValue:price,
       keyboardType:const TextInputType.numberWithOptions(decimal:true),
       onChanged:(v)=>price=v,decoration:const InputDecoration(
        labelText:'Saved price (optional; not live)')),
      TextFormField(initialValue:currency,maxLength:3,
       onChanged:(v)=>currency=v,decoration:const InputDecoration(labelText:'Currency (USD/SAR)')),
      DropdownButtonFormField<int?>(
       initialValue:score,decoration:const InputDecoration(labelText:'My preference score'),
       items:[const DropdownMenuItem<int?>(value:null,child:Text('No score')),
        for(var s=1;s<=5;s++)DropdownMenuItem<int?>(value:s,
         child:Text(s.toString()+'/5'))],
       onChanged:(v)=>change(()=>score=v)),
      TextFormField(initialValue:link,maxLength:1800,
       keyboardType:TextInputType.url,
       onChanged:(v)=>link=v,decoration:const InputDecoration(
        labelText:'Google Flights / airline / booking URL')),
      DropdownButtonFormField<String>(
       initialValue:status,decoration:const InputDecoration(labelText:'Decision'),
       items:const [
        DropdownMenuItem(value:'considering',child:Text('Considering')),
        DropdownMenuItem(value:'proposed',child:Text('Proposed option')),
        DropdownMenuItem(value:'booked',child:Text('Booked / purchased')),
        DropdownMenuItem(value:'rejected',child:Text('Not selected'))],
       onChanged:(v)=>change(()=>status=v??status)),
      TextFormField(initialValue:notes,maxLength:2200,maxLines:3,
       onChanged:(v)=>notes=v,decoration:const InputDecoration(labelText:'Pros, cons and notes')),
    ]))),
    actions:[
     TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
     FilledButton(onPressed:(){
      if(title.trim().isEmpty){Navigator.pop(ctx,{'error':'Give this option a title.'});return;}
      final numeric=price.trim().isEmpty?null:double.tryParse(price.trim());
      final stopCount=stops.trim().isEmpty?null:int.tryParse(stops.trim());
      final code=currency.trim().toUpperCase();
      final uri=Uri.tryParse(link.trim());
      if((numeric!=null&&(numeric<0||numeric>999999999.99))||
        (price.trim().isNotEmpty&&numeric==null)||
        (stops.trim().isNotEmpty&&(stopCount==null||stopCount<0||stopCount>8))||
        !RegExp(r'^[A-Z]{3}$').hasMatch(code)||
        (link.trim().isNotEmpty&&(uri==null||
          !['https','http'].contains(uri.scheme)||uri.host.isEmpty))||
        (departure!=null&&arrival!=null&&arrival!.isBefore(departure!))){
       Navigator.pop(ctx,{'error':'Check dates, stops, currency, link and price.'});return;
      }
      Navigator.pop(ctx,<String,dynamic>{
       'title':title.trim(),'provider':provider.trim(),
       'airline':airline.trim(),'origin':origin.trim(),
       'destination':destination.trim(),
       'departure_on':departure?.toIso8601String().substring(0,10),
       'return_on':arrival?.toIso8601String().substring(0,10),
       'flexible_dates':flexible,'stops':stopCount,'baggage_details':baggage.trim(),
       'price':numeric,'currency':code,'preference_score':score,
       'booking_link':link.trim(),'status':status,'notes':notes.trim(),
      });
     },child:const Text('Save option')),
    ],
   ))));
  if(result==null||!mounted)return;
  if(result.containsKey('error')){
   setState(()=>error=result['error'].toString());return;
  }
  await action(()async{
   if(prior==null){
    await db.from('trip_flight_options').insert({...result,'trip_id':widget.tripId});
   }else{
    await db.from('trip_flight_options').update(result)
     .eq('id',prior['id']).eq('trip_id',widget.tripId);
   }
  });
 }
 Future<void> action(Future<void> Function() fn)async{
  if(busy)return;
  setState((){busy=true;error=null;});
  try{await fn();}
  on PostgrestException catch(e){if(mounted)setState(()=>error=e.message);}
  catch(_){if(mounted)setState(()=>error='Flight option could not be saved.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> archive(Map<String,dynamic> row)async{
  await action(()async{
   await db.from('trip_flight_options').update({
    'archived_at':row['archived_at']==null?
     DateTime.now().toUtc().toIso8601String():null,
   }).eq('id',row['id']).eq('trip_id',widget.tripId);
  });
 }
 Future<void> toItinerary(Map<String,dynamic> row)async{
  if(row['status']!='booked')return;
  final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
   title:const Text('Add booked flight to itinerary?'),
   content:const Text('This copies the saved booking details into your trip. It does not purchase a ticket or check in.'),
   actions:[
    TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
    FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Add itinerary item')),
   ]));
  if(ok!=true)return;
  await action(()async{
   await db.from('trip_items').insert({
    'trip_id':widget.tripId,'kind':'flight','title':row['title'],
    'location':row['origin'],'destination':row['destination'],
    'local_date':row['departure_on'],'provider':
      (row['airline']??'').toString().isNotEmpty?row['airline']:row['provider'],
    'source_url':row['booking_link'],
    'estimated_cost':row['price'],'currency':row['currency'],
    'details':[
     if((row['baggage_details']??'').toString().isNotEmpty)'Baggage: '+row['baggage_details'].toString(),
     if((row['notes']??'').toString().isNotEmpty)row['notes'].toString(),
    ].join('\n'),
   });
  });
 }
 @override Widget build(BuildContext context)=>StreamBuilder<List<Map<String,dynamic>>>(
  stream:changes,builder:(context,snapshot){
   final rows=List<Map<String,dynamic>>.from(snapshot.data??const []);
   final shown=rows.where((r)=>showArchived||r['archived_at']==null).toList();
   final selected=shown.where((r)=>picked.contains(r['id'].toString())).toList();
   final priceRanges=<String,List<double>>{};
   for(final row in selected){
    final amount=(row['price'] as num?)?.toDouble();
    if(amount!=null){
     final currency=row['currency'].toString();
     priceRanges.putIfAbsent(currency,()=>[]).add(amount);
    }
   }
   return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Row(children:[
     Expanded(child:Text('Flight research & comparison',
      style:Theme.of(context).textTheme.titleLarge)),
     TextButton.icon(onPressed:busy?null:()=>editor(),
      icon:const Icon(Icons.add),label:const Text('Save option')),
    ]),
    const Text('Compare links, price snapshots, stops, baggage and flexible travel dates before booking.'),
    Align(alignment:Alignment.centerLeft,child:TextButton.icon(
     onPressed:()=>open('https://www.google.com/travel/flights'),
     icon:const Icon(Icons.open_in_new),
     label:const Text('Search Google Flights externally'))),
    SwitchListTile(
     contentPadding:EdgeInsets.zero,value:showArchived,
     title:const Text('Show removed flight options'),
     onChanged:(v)=>setState(()=>showArchived=v)),
    if(snapshot.hasError)const Text('Flight options could not load.'),
    if(!snapshot.hasData)const LinearProgressIndicator(),
    if(snapshot.hasData&&shown.isEmpty)const Card(child:Padding(
     padding:EdgeInsets.all(16),child:Text('Save several flight ideas to compare price, baggage and dates.'))),
    for(final row in shown)Card(child:Padding(
     padding:const EdgeInsets.all(11),
     child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
       Checkbox(value:picked.contains(row['id'].toString()),
        onChanged:(v)=>setState((){
         if(v==true){picked.add(row['id'].toString());}
         else{picked.remove(row['id'].toString());}
        })),
       Expanded(child:Text(row['title'].toString(),
        style:Theme.of(context).textTheme.titleMedium)),
       IconButton(onPressed:busy?null:()=>editor(row),
        icon:const Icon(Icons.edit_outlined),tooltip:'Edit flight option'),
      ]),
      Text([
       if((row['provider']??'').toString().isNotEmpty)row['provider'].toString(),
       if((row['airline']??'').toString().isNotEmpty)row['airline'].toString(),
       if(row['price']!=null)row['currency'].toString()+' '+row['price'].toString(),
       if(row['preference_score']!=null)'My score '+row['preference_score'].toString()+'/5',
      ].join(' · ')),
      if(row['departure_on']!=null)
       Text('Depart '+date(row['departure_on'])+
        (row['return_on']==null?'':' · Return '+date(row['return_on']))),
      if(row['flexible_dates']==true)const Text('Flexible dates considered'),
      if(row['stops']!=null)Text('Stops: '+row['stops'].toString()),
      if((row['baggage_details']??'').toString().isNotEmpty)
       Text('Baggage: '+row['baggage_details'].toString()),
      Text('Status: '+row['status'].toString().replaceAll('_',' ')),
      if((row['notes']??'').toString().isNotEmpty)
       Text(row['notes'].toString(),maxLines:3,overflow:TextOverflow.ellipsis),
      Wrap(spacing:8,children:[
       if((row['booking_link']??'').toString().isNotEmpty)
        TextButton.icon(onPressed:()=>open(row['booking_link'].toString()),
         icon:const Icon(Icons.link),label:const Text('Open link')),
       if(row['status']=='booked')
        TextButton.icon(onPressed:busy?null:()=>toItinerary(row),
         icon:const Icon(Icons.flight_takeoff_outlined),
         label:const Text('Add to itinerary')),
       TextButton.icon(onPressed:busy?null:()=>archive(row),
        icon:Icon(row['archived_at']==null?Icons.archive_outlined:Icons.unarchive_outlined),
        label:Text(row['archived_at']==null?'Remove':'Restore')),
      ]),
     ]),
    )),
    if(selected.isNotEmpty)Card(child:Padding(padding:const EdgeInsets.all(12),
     child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('Compare '+selected.length.toString()+' possible flights',
       style:Theme.of(context).textTheme.titleMedium),
      for(final row in selected)ListTile(
       dense:true,contentPadding:EdgeInsets.zero,
       title:Text(row['title'].toString()),
       subtitle:Text([
        if(row['price']!=null)row['currency'].toString()+' '+row['price'].toString(),
        if(row['preference_score']!=null)'Preference '+row['preference_score'].toString()+'/5',
        if(row['stops']!=null)row['stops'].toString()+' stops',
       ].join(' · '))),
      for(final entry in priceRanges.entries)Text(
       entry.key+' price range: '+(entry.value.reduce((a,b)=>a<b?a:b)).toStringAsFixed(2)+
       ' – '+(entry.value.reduce((a,b)=>a>b?a:b)).toStringAsFixed(2)),
      const Text('These are competing options, not a combined purchase total. Prices are saved snapshots, not live quotes.'),
     ]))),
    if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
    if(busy)const LinearProgressIndicator(),
   ]);
  },
 );
}
