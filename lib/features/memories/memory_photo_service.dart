import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../coordinate/activity_image_rules.dart';
import '../../core/app_env.dart';

class MemoryPhotoService{
 MemoryPhotoService(this.db,{ImagePicker? picker}):picker=picker??ImagePicker();
 final SupabaseClient db;
 final ImagePicker picker;
 static const bucket='onespace-memory-photos';
 static const personalBucket='onespace-private-memory-photos';
 Future<String> bucketForMemory(String memoryId)async{
  if(OneSpaceEnv.isProduction)return bucket;
  final me=db.auth.currentUser?.id;
  if(me==null)throw StateError('Sign in to add a photo.');
  final m=await db.from('memories')
    .select('space_id,private_space_id,created_by,visibility')
    .eq('id',memoryId).single();
  if(m['private_space_id']!=null){
   if(m['private_space_id']!=me||m['created_by']!=me||
       m['space_id']!=null||m['visibility']!='private'){
     throw StateError('The memory is not in your personal space.');
   }
   return personalBucket;
  }
  if(m['space_id']==null||m['visibility']!='shared'){
   throw StateError('A current shared memory is required.');
  }
  return bucket;
 }

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
  final selectedBucket=await bucketForMemory(memoryId);
  var saved=0;
  for(final photo in chosen){
   final bytes=await photo.readAsBytes();
   ActivityImageRules.validate(bytes);
   final mime=ActivityImageRules.mimeType(bytes)!;
   final unique=const Uuid().v4();
   final objectPath=memoryId+'/'+user+'/'+unique+'.'+
     ActivityImageRules.extension(mime);
   final storage=db.storage.from(selectedBucket);
   await storage.uploadBinary(objectPath,bytes,
    fileOptions:FileOptions(contentType:mime,upsert:false));
   try{
    await db.from('memory_photos').insert({
     'memory_id':memoryId,'caption':'','mime_type':mime,
     'byte_size':bytes.length,'object_path':objectPath,
     'display_order':startOrder+saved,
     if(!OneSpaceEnv.isProduction)'storage_bucket_id':selectedBucket,
    });
    saved++;
   }catch(_){
    try{await storage.remove([objectPath]);}catch(_){}
    rethrow;
   }
  }
  return saved;
 }
 /// Upload one verified camera/gallery image and return its database ID,
 /// so a scrapbook slot cannot accidentally use a partner's concurrent photo.
 Future<String> addFileReturningId(String memoryId,XFile photo)async{
  final user=db.auth.currentUser?.id;
  if(user==null)throw StateError('Sign in to add a scrapbook photo.');
  final selectedBucket=await bucketForMemory(memoryId);
  final bytes=await photo.readAsBytes();
  ActivityImageRules.validate(bytes);
  final mime=ActivityImageRules.mimeType(bytes)!;
  final path=memoryId+'/'+user+'/'+const Uuid().v4()+'.'+
   ActivityImageRules.extension(mime);
  final storage=db.storage.from(selectedBucket);
  await storage.uploadBinary(path,bytes,
   fileOptions:FileOptions(contentType:mime,upsert:false));
  try{
   final row=await db.from('memory_photos').insert({
    'memory_id':memoryId,'caption':'','mime_type':mime,
    'byte_size':bytes.length,'object_path':path,
    if(!OneSpaceEnv.isProduction)'storage_bucket_id':selectedBucket,
   }).select('id').single();
   return row['id'].toString();
  }catch(_){
   try{await storage.remove([path]);}catch(_){}
   rethrow;
  }
 }

 Future<String> signedUrl(String path,{String? bucketId})=>
  db.storage.from(bucketId??bucket).createSignedUrl(path,120);
}
