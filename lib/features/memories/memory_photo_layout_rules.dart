/// The scrapbook layout is a view preference; it never edits the photo data.
class MemoryPhotoLayoutRules{
 const MemoryPhotoLayoutRules._();
 static const allowed=['grid','feature','polaroid','overlap','carousel','mosaic','film','scatter','timeline'];
 /// R70: the names people see.
 static const names=<String,String>{
  'grid':'Grid','feature':'One large','polaroid':'Polaroids','overlap':'Stack (swipe)',
  'carousel':'Slideshow','mosaic':'Mosaic','film':'Film strip','scatter':'Scattered','timeline':'Timeline',
 };
 static String safe(Object? value){
  final text=value?.toString()??'';
  return allowed.contains(text)?text:'grid';
 }
}
