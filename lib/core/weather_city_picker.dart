import 'package:material_ui/material_ui.dart';
import 'device_weather_service.dart';

/// Explicit city selection. Never touches the phone's location settings.
class WeatherCityPicker extends StatefulWidget {
  const WeatherCityPicker({super.key});
  @override
  State<WeatherCityPicker> createState()=>_WeatherCityPickerState();
}

class _WeatherCityPickerState extends State<WeatherCityPicker> {
  final input=TextEditingController();
  List<WeatherCity> results=const [];
  bool searching=false;
  String? error;
  int sequence=0;

  @override
  void dispose(){sequence++;input.dispose();super.dispose();}

  Future<void> search() async {
    final text=input.text.trim();
    if(text.length<2){
      setState(()=>error='Enter at least two letters of the city name.');
      return;
    }
    final request=++sequence;
    setState(() {searching=true;error=null;results=const [];});
    try{
      final found=await DeviceWeatherService.search(text);
      if(!mounted||request!=sequence)return;
      setState(()=>results=found);
    }catch(_){
      if(mounted&&request==sequence){
        setState(()=>error='Could not search cities. Check your connection.');
      }
    }finally{
      if(mounted&&request==sequence)setState(()=>searching=false);
    }
  }

  @override
  Widget build(BuildContext context)=>SafeArea(
    top:false,
    child:FractionallySizedBox(
      heightFactor:0.79,
      child:Padding(
        padding:EdgeInsets.fromLTRB(16,8,16,
          MediaQuery.viewInsetsOf(context).bottom+12),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[
            const Icon(Icons.location_city_outlined),
            const SizedBox(width:8),
            Expanded(child:Text('Choose a weather city',
              style:Theme.of(context).textTheme.titleLarge)),
            IconButton(tooltip:'Close',icon:const Icon(Icons.close),
              onPressed:()=>Navigator.pop(context)),
          ]),
          const Text('Search for any city. Choose the correct region/country '
            'and OneSpace will remember it. No GPS permission.'),
          const SizedBox(height:12),
          TextField(
            controller:input,
            autofocus:true,
            textInputAction:TextInputAction.search,
            onSubmitted:(_)=>search(),
            decoration:InputDecoration(
              labelText:'City or city, country',
              hintText:'e.g. Riyadh or Norristown, Pennsylvania',
              prefixIcon:const Icon(Icons.search),
              suffixIcon:IconButton(
                tooltip:'Search cities',
                onPressed:searching?null:search,
                icon:const Icon(Icons.arrow_forward)),
              border:const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height:7),
          if(searching) const LinearProgressIndicator(),
          if(error!=null) Text(error!,
            style:TextStyle(color:Theme.of(context).colorScheme.error)),
          if(!searching&&error==null&&results.isEmpty)
            const Padding(padding:EdgeInsets.all(16),
              child:Text('Enter a city name and search.')),
          Expanded(child:ListView.builder(
            itemCount:results.length,
            itemBuilder:(context,index){
              final city=results[index];
              return ListTile(
                leading:const Icon(Icons.place_outlined),
                title:Text(city.name),
                subtitle:Text([
                  if(city.region!=null)city.region!,city.country,
                ].join(' · ')),
                trailing:const Icon(Icons.chevron_right),
                onTap:()=>Navigator.pop(context,city),
              );
            },
          )),
          const Text('City search: GeoNames / Open-Meteo',
            style:TextStyle(fontSize:11)),
        ]),
      ),
    ),
  );
}
