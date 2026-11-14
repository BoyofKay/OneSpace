/// R39 backlink presentation. All records must already be authorized by
/// the note_references and notes row-level security policies.
class RelatedNotesRules{
 const RelatedNotesRules._();
 static List<Map<String,dynamic>> visible(
  Iterable<Map<String,dynamic>> notes,
  Iterable<String> linkedIds,
 ){
  final ids=linkedIds.toSet();
  final result=notes.where((note)=>
   note['id'] is String && ids.contains(note['id']) &&
   (note['title']??'').toString().trim().isNotEmpty).toList();
  result.sort((a,b){
   final pinned=(b['pinned']==true?1:0)-(a['pinned']==true?1:0);
   if(pinned!=0)return pinned;
   final updated=(b['updated_at']??'').toString()
    .compareTo((a['updated_at']??'').toString());
   if(updated!=0)return updated;
   return (a['id']??'').toString().compareTo((b['id']??'').toString());
  });
  return result;
 }
}
