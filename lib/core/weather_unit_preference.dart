import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Temperature display is local to each phone; backend readings remain Celsius.
class WeatherUnitPreference extends ChangeNotifier{
 WeatherUnitPreference._();
 static final instance=WeatherUnitPreference._();
 static const key='weather_temperature_unit_v1';
 bool fahrenheit=false;
 Future<void> load()async{
  try{
   fahrenheit=(await SharedPreferencesAsync().getString(key))=='fahrenheit';
  }catch(_){}
  notifyListeners();
 }
 Future<void> setFahrenheit(bool value)async{
  fahrenheit=value;notifyListeners();
  try{await SharedPreferencesAsync().setString(
   key,value?'fahrenheit':'celsius');}catch(_){}
 }
 static double convert(num c,bool fahrenheit)=>fahrenheit?c.toDouble()*9/5+32:c.toDouble();
 String format(num value,{bool suffix=true}){
  final unit=fahrenheit?'°F':'°C';
  return convert(value,fahrenheit).toStringAsFixed(0)+(suffix?unit:'°');
 }
}
