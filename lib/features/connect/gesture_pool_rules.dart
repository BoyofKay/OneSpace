/// Pure gesture-message pool rules shared by the sender and regression tests.
class GesturePoolRules {
 const GesturePoolRules._();

 static List<String> activeMessages({
   required String kind,
   required List<String> builtIn,
   required List<Map<String,dynamic>> overrides,
   required List<Map<String,dynamic>> custom,
 }) {
   final result=<String>[];
   for(var i=0;i<builtIn.length;i++){
     final matches=overrides.where((o)=>
       o['kind']==kind&&o['message_index']==i);
     final override=matches.isEmpty?null:matches.first;
     if(override?['disabled']==true)continue;
     final text=(override?['message']?.toString()??builtIn[i]).trim();
     if(text.isNotEmpty&&!result.contains(text))result.add(text);
   }
   for(final row in custom){
     if(row['kind']!=kind)continue;
     final text=row['message']?.toString().trim()??'';
     if(text.isNotEmpty&&!result.contains(text))result.add(text);
   }
   return result;
 }
}
