import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../coordinate/activity_image_rules.dart';

class MemoryPhotoService{
 MemoryPhotoService(this.db,{ImagePicker? picker}):picker=picker??ImagePicker();
 final SupabaseClient db;
 final ImagePicker picker;
 static const bucket='onespace-memory-photos';

 Future<int> addFromGallery(String memoryId,{int startOrder=0})async{
  final chosen=await picker.pickMultiImage(
   imageQuality:82,maxWidth:1600,maxHeight:1600);
  return addFiles(memoryId,chosen,startOrder:startOrder);
 }

 Future<int> addFromCamera(String memoryId,{int startOrder=0})async{
  final photo=await picker.pickImage(source:ImageSource.camera,
   imageQuality:82,maxWidth:1600,maxHeight:1600);
  if(photo==null)return 0;
  return addFiles(memoryId,[photo],startOrder:startOrder);
 }

 /// Also used for a camera-first Daily selfie. Never stores the source URI.
 Future<int> addFiles(String memoryId,List<XFile> chosen,
  {int startOrder=0})async{
  final user=db.auth.currentUser?.id;
  if(user==null)throw StateError('Sign in before adding photos.');
  if(chosen.isEmpty)return 0;
  var saved=0;
  for(final photo in chosen){
   final bytes=await photo.readAsBytes();
   ActivityImageRules.validate(bytes);
   final mime=ActivityImageRules.mimeType(bytes)!;
   final unique=const Uuid().v4();
   final objectPath=memoryId+'/'+user+'/'+unique+'.'+
     ActivityImageRules.extension(mime);
   final storage=db.storage.from(bucket);
   await storage.uploadBinary(objectPath,bytes,
    fileOptions:FileOptions(contentType:mime,upsert:false));
   try{
    await db.from('memory_photos').insert({
     'memory_id':memoryId,'caption':'','mime_type':mime,
     'byte_size':bytes.length,'object_path':objectPath,
     'display_order':startOrder+saved,
    });
    saved++;
   }catch(_){
    try{await storage.remove([objectPath]);}catch(_){}
    rethrow;
   }
  }
  return saved;
 }
 Future<String> signedUrl(String path)=>db.storage.from(bucket).createSignedUrl(path,120);
}
