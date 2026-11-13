/// Query shaping only; Supabase RLS still decides which records are visible.
class GlobalSearchRules {
 const GlobalSearchRules._();
 static const maxQueryLength=100;
 static const maxPerSection=12;
 static String normalize(String value){
  final trimmed=value.trim();
  return trimmed.length>maxQueryLength
    ?trimmed.substring(0,maxQueryLength):trimmed;
 }
 static bool canSearch(String value)=>normalize(value).runes.length>=2;
 static String pattern(String value){
  final term=normalize(value);
  return '%'+term.replaceAll('\\',r'\\')
   .replaceAll('%',r'\%').replaceAll('_',r'\_')+'%';
 }
 static String? destinationId(Map<String,dynamic> row,String field){
  final text=row[field]?.toString().trim();
  return text==null||text.isEmpty?null:text;
 }
}
