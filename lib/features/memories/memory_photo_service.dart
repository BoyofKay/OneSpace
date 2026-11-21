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
 static const privateBucket='onespace-private-memory-photos';

 /// Resolve from a visible parent; never infer ownership from a filename.
 Future<String> _bucketForMemory(String memoryId) async {
  if(OneSpaceEnv.usesLegacyBackend)return bucket;
  final m=await db.from('memories')
   .select('private_space_id,created_by,space_id,visibility')
   .eq('id',memoryId).single();
  if(m['private_space_id']!=null){
   final me=db.auth.currentUser?.id;
   if(me==null||m['private_space_id']!=me||
      m['created_by']!=me||m['space_id']!=null||
      m['visibility']!='private'){
    throw StateError('This personal memory belongs to another account.');
   }
   return privateBucket;
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
  var saved=0;
  final targetBucket=await _bucketForMemory(memoryId);
  for(final photo in chosen){
   final bytes=await photo.readAsBytes();
   ActivityImageRules.validate(bytes);
   final mime=ActivityImageRules.mimeType(bytes)!;
   final unique=const Uuid().v4();
   final objectPath=memoryId+'/'+user+'/'+unique+'.'+
     ActivityImageRules.extension(mime);
   final storage=db.storage.from(targetBucket);
   await storage.uploadBinary(objectPath,bytes,
    fileOptions:FileOptions(contentType:mime,upsert:false));
   try{
    await db.from('memory_photos').insert({
     'memory_id':memoryId,'caption':'','mime_type':mime,
     'byte_size':bytes.length,'object_path':objectPath,
     'display_order':startOrder+saved,
     if(!OneSpaceEnv.usesLegacyBackend) 'storage_bucket_id':targetBucket,
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
  final targetBucket=await _bucketForMemory(memoryId);
  final bytes=await photo.readAsBytes();
  ActivityImageRules.validate(bytes);
  final mime=ActivityImageRules.mimeType(bytes)!;
  final path=memoryId+'/'+user+'/'+const Uuid().v4()+'.'+
   ActivityImageRules.extension(mime);
  final storage=db.storage.from(targetBucket);
  await storage.uploadBinary(path,bytes,
   fileOptions:FileOptions(contentType:mime,upsert:false));
  try{
   final row=await db.from('memory_photos').insert({
    'memory_id':memoryId,'caption':'','mime_type':mime,
    'byte_size':bytes.length,'object_path':path,
    if(!OneSpaceEnv.usesLegacyBackend) 'storage_bucket_id':targetBucket,
   }).select('id').single();
   return row['id'].toString();
  }catch(_){
   try{await storage.remove([path]);}catch(_){}
   rethrow;
  }
 }

 Future<String> signedUrl(String path) async {
  if(OneSpaceEnv.usesLegacyBackend){
   return db.storage.from(bucket).createSignedUrl(path,120);
  }
  // Read the bucket on its RLS-visible photo row; an owner's former
  // partner cannot sign a private photo by guessing its object path.
  final photo=await db.from('memory_photos')
   .select('storage_bucket_id').eq('object_path',path).single();
  final selected=photo['storage_bucket_id']?.toString();
  if(selected!=bucket&&selected!=privateBucket){
   throw StateError('Unrecognized memory photo storage scope.');
  }
  return db.storage.from(selected!).createSignedUrl(path,120);
 }
}
