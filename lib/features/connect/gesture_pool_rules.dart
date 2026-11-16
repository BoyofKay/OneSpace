/// Pure gesture-message pool rules shared by the sender and regression tests.
class GesturePoolRules {
 const GesturePoolRules._();

 /// R75 (Ahmed): words that only make sense when you live apart. When the
 /// couple lives together, built-in messages with these words are never
 /// picked (by the Send button or by the automatic morning/evening/night
 /// messages). Mirrors private.gesture_mentions_distance in the database.
 static final distance=RegExp(r"\bmiles\b|distance|from afar|far away|time zones?\b|"
   r"see you again|wish you were here|will be home|until I can see",caseSensitive:false);
 static bool mentionsDistance(String text)=>distance.hasMatch(text);

 /// Gesture types that only make sense apart (hidden from Send when together).
 static const apartOnly={'miss_together','miss_home','miss_kids','miss_pets'};

 static List<String> activeMessages({
   required String kind,
   required List<String> builtIn,
   required List<Map<String,dynamic>> overrides,
   required List<Map<String,dynamic>> custom,
   bool together=false,
 }) {
   final result=<String>[];
   for(var i=0;i<builtIn.length;i++){
     final matches=overrides.where((o)=>
       o['kind']==kind&&o['message_index']==i);
     final override=matches.isEmpty?null:matches.first;
     if(override?['disabled']==true)continue;
     final text=(override?['message']?.toString()??builtIn[i]).trim();
     if(together&&mentionsDistance(text))continue;
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
