/// Filtering and display order for RLS-filtered Notes 2.0 results.
/// All privacy decisions remain on the server; this is only presentation.
class NotesLibraryRules {
 const NotesLibraryRules._();
 static List<Map<String,dynamic>> visible(
  Iterable<Map<String,dynamic>> notes,{
  String scope='all',bool showArchived=false,String query='',
 }){
  final needle=query.trim().toLowerCase();
  final found=notes.where((note){
   if(!showArchived&&note['archived_at']!=null)return false;
   if(scope!='all'&&note['visibility']!=scope)return false;
   if(needle.isEmpty)return true;
   final title=(note['title']??'').toString().toLowerCase();
   final body=(note['body']??'').toString().toLowerCase();
   return title.contains(needle)||body.contains(needle);
  }).toList();
  found.sort((a,b){
   final pinned=(b['pinned']==true?1:0)-(a['pinned']==true?1:0);
   if(pinned!=0)return pinned;
   final updated=(b['updated_at']??'').toString().compareTo(
    (a['updated_at']??'').toString());
   if(updated!=0)return updated;
   return (b['id']??'').toString().compareTo((a['id']??'').toString());
  });
  return found;
 }
}
