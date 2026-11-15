import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'partner_time_zones.dart';
import 'shared_weather.dart';
import 'weather_unit_preference.dart';
import 'package:onespace/l10n/phrases.dart';

/// Clocks and weather sit in the same partner columns. No new network requests.
class PartnerClockStrip extends StatefulWidget {
 const PartnerClockStrip({super.key,required this.members,
   required this.relationshipMode,this.onConfigure});
 final List<Map<String,dynamic>> members;
 final String relationshipMode;
 final VoidCallback? onConfigure;
 @override State<PartnerClockStrip> createState()=>_PartnerClockStripState();
}
class _PartnerClockStripState extends State<PartnerClockStrip> {
 Timer? refresh;
 @override void initState(){
   super.initState();
   WeatherUnitPreference.instance.addListener(_refreshUnits);
   refresh=Timer.periodic(const Duration(minutes:1),(_){
     if(mounted)setState((){});
   });
 }
 void _refreshUnits(){if(mounted)setState((){});}
 @override void dispose(){refresh?.cancel();WeatherUnitPreference.instance.removeListener(_refreshUnits);super.dispose();}
 Widget _weather(Map<String,dynamic> member){
   final cs=Theme.of(context).colorScheme;
   if(member['city_weather_shared']!=true){
     return Padding(padding:const EdgeInsets.only(top:12),
       child:Text(tt('Weather city not selected'),
         style:Theme.of(context).textTheme.bodySmall));
   }
   final parts=(member['city_name']?.toString()??'')
     .split(',').map((s)=>s.trim()).where((s)=>s.isNotEmpty).toList();
   final city=parts.isNotEmpty?parts.first:'City unavailable';
   final region=parts.length>2?parts.sublist(1,parts.length-1).join(', '):'';
   final country=parts.length>1?parts.last:'';
   final temperature=member['temperature_c'];
   final rawCode=member['weather_code'];
   final code=rawCode is num?rawCode.toInt():int.tryParse(rawCode?.toString()??'');
   final high=member['weather_high_c'],low=member['weather_low_c'];
   final rain=member['weather_rain_pct'];
   final updated=DateTime.tryParse(member['weather_updated_at']?.toString()??'');
   final stale=updated==null||
     DateTime.now().difference(updated.toLocal())>const Duration(hours:2);
   return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     const SizedBox(height:12),
     Divider(height:1,color:cs.outlineVariant),
     const SizedBox(height:10),
     Text(tt(city),maxLines:2,overflow:TextOverflow.ellipsis,
       style:Theme.of(context).textTheme.titleSmall),
     if(region.isNotEmpty)Text(tt(region),maxLines:2,
       overflow:TextOverflow.ellipsis,
       style:Theme.of(context).textTheme.bodySmall),
     if(country.isNotEmpty)Text(tt(country),maxLines:2,
       overflow:TextOverflow.ellipsis,
       style:Theme.of(context).textTheme.labelSmall),
     const SizedBox(height:10),
     Text(tt(temperature is num?WeatherUnitPreference.instance.format(temperature):'—'),
       style:Theme.of(context).textTheme.headlineSmall),
     const SizedBox(height:3),
     Text(tt(code==null?'Conditions unavailable':SharedWeather.condition(code)),
       maxLines:2,overflow:TextOverflow.ellipsis,
       style:Theme.of(context).textTheme.bodySmall),
     const SizedBox(height:8),
     Row(children:[
       Expanded(child:Text(tt(high is num?
         'H '+WeatherUnitPreference.instance.format(high,suffix:false):'H —'),
         style:Theme.of(context).textTheme.labelMedium)),
       Expanded(child:Text(tt(low is num?
         'L '+WeatherUnitPreference.instance.format(low,suffix:false):'L —'),
         style:Theme.of(context).textTheme.labelMedium)),
     ]),
     const SizedBox(height:6),
     Row(children:[
       Icon(Icons.water_drop_outlined,size:15,color:cs.primary),
       const SizedBox(width:4),
       Expanded(child:Text(tt(rain is num?
         'Rain '+rain.toStringAsFixed(0)+'%':'Rain —'),
         style:Theme.of(context).textTheme.bodySmall)),
     ]),
     if(stale)Padding(padding:const EdgeInsets.only(top:5),
       child:Text(tt('Update pending'),
         style:Theme.of(context).textTheme.labelSmall)),
   ]);
 }
 Widget _column(Map<String,dynamic>? member,DateTime? time,{required bool mine}){
   final actual=mine&&time==null?DateTime.now():time;
   return Expanded(child:Padding(
     padding:const EdgeInsets.symmetric(horizontal:4,vertical:3),
     child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Text(tt(member?['name']?.toString()??(mine?tt('You'):tt('Partner'))),
         maxLines:1,overflow:TextOverflow.ellipsis,
         style:Theme.of(context).textTheme.labelLarge),
       const SizedBox(height:5),
       FittedBox(fit:BoxFit.scaleDown,alignment:AlignmentDirectional.centerStart,
         child:Text(tt(actual==null?'—':PartnerTimeZones.timeLabel(actual)),
           style:Theme.of(context).textTheme.headlineSmall)),
       if(member!=null)_weather(member),
     ]),
   ));
 }
 @override Widget build(BuildContext context){
   if(widget.relationshipMode=='living_together')return const SizedBox.shrink();
   final mine=widget.members.where((m)=>m['is_me']==true).firstOrNull;
   final other=widget.members.where((m)=>m['is_me']!=true).firstOrNull;
   if(mine==null&&other==null)return const SizedBox.shrink();
   final now=DateTime.now();
   final mineTime=PartnerTimeZones.inZone(mine?['time_zone']?.toString(),now);
   final otherTime=PartnerTimeZones.inZone(other?['time_zone']?.toString(),now);
   final attribution=mine?['city_weather_shared']==true||
     other?['city_weather_shared']==true;
   return Padding(padding:const EdgeInsetsDirectional.fromSTEB(2,4,2,5),
     child:Column(children:[
       Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
         _column(mine,mineTime,mine:true),
         if(other!=null)...[
           const SizedBox(width:8),
           _column(other,otherTime,mine:false),
         ],
       ]),
       if(attribution)Align(alignment:AlignmentDirectional.centerEnd,
         child:InkWell(
           onTap:()=>unawaited(launchUrl(
             Uri.parse('https://open-meteo.com/'),
             mode:LaunchMode.externalApplication)),
           child:Text(tt('Weather by Open-Meteo'),
             style:Theme.of(context).textTheme.labelSmall?.copyWith(
               decoration:TextDecoration.underline)),
         ),
       ),
     ]),
   );
 }
}
