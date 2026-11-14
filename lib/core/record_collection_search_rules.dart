/// Search and recoverable-history presentation across OneSpace
/// collections. This function NEVER bypasses backend source-table RLS.
class RecordCollectionSearchRules {
 const RecordCollectionSearchRules._();

 static bool matches(Map<String,dynamic> record,String query,
     {required List<String> fields}) {
  final words=query.trim().toLowerCase().split(RegExp(r'\s+'))
   .where((word)=>word.isNotEmpty);
  final content=fields.map((field)=>
   (record[field]??'').toString().toLowerCase()).join(' ');
  return words.every(content.contains);
 }

 /// Archive/restore is distinct from server-recorded action history.
 static bool inHistory(Map<String,dynamic> record,bool historyOnly)=>
  (record['archived_at']!=null)==historyOnly;
}
