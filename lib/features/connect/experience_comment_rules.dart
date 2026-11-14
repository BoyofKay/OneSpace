/// Shared-experience comment display and action rules.
///
/// Database RLS must independently enforce these rules; this helper only
/// prevents exposing inappropriate actions in the client interface.
class ExperienceCommentRules {
 const ExperienceCommentRules._();

 static bool isAuthor(Map<String,dynamic> row,String? viewerId)=>
  viewerId!=null && row['created_by']?.toString()==viewerId;

 static bool isRetracted(Map<String,dynamic> row)=>
  row['archived_at']!=null;

 static bool canEdit(Map<String,dynamic> row,String? viewerId)=>
  isAuthor(row,viewerId)&&!isRetracted(row);

 static bool canRetract(Map<String,dynamic> row,String? viewerId)=>
  canEdit(row,viewerId);

 static bool canRestore(Map<String,dynamic> row,String? viewerId)=>
  isAuthor(row,viewerId)&&isRetracted(row);

 static List<Map<String,dynamic>> visible(
  List<Map<String,dynamic>> rows,String? viewerId,{
  bool showMyRetracted=false,String query='',
 }){
  final terms=query.trim().toLowerCase().split(RegExp(r'\\s+'))
   .where((term)=>term.isNotEmpty).toList();
  return rows.where((row){
   final retracted=isRetracted(row);
   if(retracted&&(!showMyRetracted||!isAuthor(row,viewerId)))return false;
   final searchable=(row['body']??'').toString().toLowerCase();
   return terms.every(searchable.contains);
  }).toList();
 }
}
