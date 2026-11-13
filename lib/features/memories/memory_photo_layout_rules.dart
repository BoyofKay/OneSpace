/// The scrapbook layout is a view preference; it never edits the photo data.
class MemoryPhotoLayoutRules{
 const MemoryPhotoLayoutRules._();
 static const allowed=['grid','feature','polaroid','overlap'];
 static String safe(Object? value){
  final text=value?.toString()??'';
  return allowed.contains(text)?text:'grid';
 }
}
