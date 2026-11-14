/// OneSpace Notes 2.0 links. No target title is stored in the link:
/// it must be read live under the current user's source RLS.
class NoteReferenceRules{
 const NoteReferenceRules._();
 static const tables=<String,String>{
  'task':'tasks',
  'event':'space_events',
  'occasion':'occasion_plans',
  'experience':'shared_experiences',
 };
 static const labels=<String,String>{
  'task':'To-do and Checklists',
  'event':'Calendar event',
  'occasion':'Occasion or surprise',
  'experience':'Shared experience',
 };
 static String? table(Object? kind)=>tables[kind?.toString()];
 static String label(Object? kind)=>labels[kind?.toString()]??'Linked item';

 static List<Map<String,dynamic>> available(
  Iterable<Map<String,dynamic>> rows,{
   required String noteVisibility,required String kind,
  }){
  final results=<Map<String,dynamic>>[];
  for(final row in rows){
   if(row['id'] is! String||row['title'] is! String ||
      row['title'].toString().trim().isEmpty ||
      row['archived_at']!=null)continue;
   // This only improves picker UX. Server RLS and note_reference_visible
   // are ALWAYS the authority and validate both objects independently.
   if(noteVisibility=='shared'&&kind!='experience'&&
    row['visibility']!='shared')continue;
   results.add(row);
  }
  return results;
 }

 static bool canOpen(Map<String,dynamic>? source)=>
  source!=null&&source['id'] is String;
}
