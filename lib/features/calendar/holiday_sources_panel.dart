import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'holiday_calendar_service.dart';

/// Holiday calendars are overlays, not copied or duplicated as editable events.
class HolidaySourcesPanel extends StatefulWidget{
 const HolidaySourcesPanel({super.key,required this.spaceId,required this.onChanged});
 final String spaceId;
 final VoidCallback onChanged;
 @override State<HolidaySourcesPanel> createState()=>_HolidaySourcesPanelState();
}
class _HolidaySourcesPanelState extends State<HolidaySourcesPanel>{
 final db=Supabase.instance.client;
 Map<String,bool> enabled={};
 bool busy=false,loading=true;
 String? error;
 @override void initState(){super.initState();load();}
 Future<void> load()async{
  try{
   final rows=await db.from('space_holiday_sources').select('country_code,enabled')
    .eq('space_id',widget.spaceId);
   if(mounted)setState((){
    enabled={for(final row in rows)row['country_code'].toString():row['enabled']==true};
    loading=false;error=null;
   });
  }catch(_){if(mounted)setState((){
   error='Could not load holiday sources.';loading=false;
  });}
 }
 Future<void> setCountry(String code,bool on)async{
  if(busy)return;
  setState((){busy=true;error=null;});
  try{
   final exists=enabled.containsKey(code);
   if(exists){
    await db.from('space_holiday_sources').update({'enabled':on})
      .eq('space_id',widget.spaceId).eq('country_code',code);
   }else{
    await db.from('space_holiday_sources').insert({
     'space_id':widget.spaceId,'country_code':code,'enabled':on,
    });
   }
   if(mounted)setState(()=>enabled[code]=on);
   widget.onChanged();
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){if(mounted)setState(()=>error='Could not update holiday selection.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context)=>Card(elevation:0,
  child:ExpansionTile(
   leading:const Icon(Icons.public_outlined),
   title:const Text('Regional holidays'),
   subtitle:const Text('Choose which country calendars we see together'),
   childrenPadding:const EdgeInsets.fromLTRB(12,0,12,12),
   children:[
    if(loading)const LinearProgressIndicator()
    else for(final code in HolidayCatalog.countryNames.keys)
     CheckboxListTile(
      contentPadding:EdgeInsets.zero,
      title:Text(HolidayCatalog.label(code)),
      subtitle:Text(code=='SA'?'Founding Day and National Day only':
       'National public holidays · from Nager.Date'),
      value:enabled[code]??false,
      onChanged:busy?null:(value)=>setCountry(code,value??false)),
    const Text('Holiday overlays are informational. Local/state observances and announced lunar-calendar holidays may differ. Add your own important dates below.',
     style:TextStyle(fontSize:12)),
    if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
   ]));
}
