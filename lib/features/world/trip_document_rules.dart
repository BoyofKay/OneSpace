import 'dart:typed_data';

/// No public URL, local file path or untrusted MIME from the OS is persisted.
class TripDocumentRules {
 const TripDocumentRules._();
 static const bucket='onespace-trip-documents';
 static const maxBytes=10*1024*1024;
 static final uuid=RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
 );

 static String? detectMime(Uint8List bytes){
  if(bytes.length>=5&&bytes[0]==0x25&&bytes[1]==0x50&&
     bytes[2]==0x44&&bytes[3]==0x46&&bytes[4]==0x2d){
   return 'application/pdf';
  }
  if(bytes.length>=3&&bytes[0]==0xff&&bytes[1]==0xd8&&bytes[2]==0xff){
   return 'image/jpeg';
  }
  if(bytes.length>=8&&bytes[0]==0x89&&bytes[1]==0x50&&
    bytes[2]==0x4e&&bytes[3]==0x47&&bytes[4]==0x0d&&
    bytes[5]==0x0a&&bytes[6]==0x1a&&bytes[7]==0x0a){
   return 'image/png';
  }
  if(bytes.length>=12&&String.fromCharCodes(bytes.sublist(0,4))=='RIFF'&&
    String.fromCharCodes(bytes.sublist(8,12))=='WEBP')return 'image/webp';
  return null;
 }
 static String extension(String mime)=>switch(mime){
  'application/pdf'=>'pdf',
  'image/jpeg'=>'jpg',
  'image/png'=>'png',
  'image/webp'=>'webp',
  _=>throw const FormatException('Unsupported document type'),
 };
 static String validatedMime(Uint8List data){
  if(data.isEmpty||data.length>maxBytes){
   throw const FormatException('Choose a document smaller than 10 MB.');
  }
  final mime=detectMime(data);
  if(mime==null)throw const FormatException('Choose a PDF, JPEG, PNG or WebP document.');
  return mime;
 }
 static String safeTitle(String original){
  final base=original.trim().replaceAll(RegExp(r'[\\/]'),'-')
     .replaceAll(RegExp(r'[\x00-\x1f]'),'').trim();
  if(base.isEmpty)return 'Travel document';
  return base.length>160?base.substring(0,160):base;
 }
 static String safeFileName(String original){
  final s=original.trim().replaceAll(RegExp(r'[\\/]'),'-')
     .replaceAll(RegExp(r'[\x00-\x1f]'),'');
  if(s.isEmpty)return 'document';
  return s.length>200?s.substring(0,200):s;
 }
 static String path({required String tripId,required String userId,
  required String documentId,required String mime}){
  if(!uuid.hasMatch(tripId)||!uuid.hasMatch(userId)||!uuid.hasMatch(documentId)){
   throw const FormatException('Invalid document destination.');
  }
  return '$tripId/$userId/$documentId.${extension(mime)}';
 }
}
