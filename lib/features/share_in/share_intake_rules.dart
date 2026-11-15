/// Shares from third-party apps are suggestions to file, never auto-posts.
class ShareIntakeRules{
 const ShareIntakeRules._();
 static final _urlPattern=RegExp(r'https?://\S+',caseSensitive:false);
 static const maxText=8000;

 static IncomingShare fromExternal(Map<Object?,Object?> input){
  final text=(input['text']??'').toString().trim();
  final subject=(input['subject']??'').toString().trim();
  return parse(text:text,subject:subject);
 }

 static IncomingShare parse({required String text,String subject=''}) {
  final value=text.trim().length>maxText?
    text.trim().substring(0,maxText):text.trim();
  String url='';
  for(final match in _urlPattern.allMatches(value)){
   var candidate=match.group(0)??'';
   candidate=candidate.replaceFirst(RegExp(r'[.,;!?\)\]>]+$'),'');
   final parsed=Uri.tryParse(candidate);
   if(parsed!=null&&['http','https'].contains(parsed.scheme.toLowerCase())&&
      parsed.host.isNotEmpty){
    url=candidate;
    break;
   }
  }
  final withoutLink=url.isEmpty?value:value.replaceFirst(url,'').trim();
  final cleanTitle=subject.trim().isNotEmpty?
    subject.trim():url.isNotEmpty?(Uri.tryParse(url)?.host??'Saved link'):'Shared idea';
  return IncomingShare(
   title:cleanTitle.length>120?cleanTitle.substring(0,120):cleanTitle,
   link:url,
   note:withoutLink.length>5000?withoutLink.substring(0,5000):withoutLink,
  );
 }

 static bool isWebLink(String value){
  final parsed=Uri.tryParse(value.trim());
  return parsed!=null&&['http','https'].contains(parsed.scheme.toLowerCase())
   &&parsed.host.isNotEmpty;
 }
}
class IncomingShare{
 const IncomingShare({required this.title,required this.link,required this.note});
 final String title,link,note;
 bool get hasContent=>link.isNotEmpty||note.isNotEmpty;
}

/// R55: a photo or PDF shared in from another app.
class SharedFile{
 const SharedFile({required this.name,required this.mime,required this.bytes,this.note=''});
 final String name,mime,note;
 final List<int> bytes;
 bool get isImage=>mime.startsWith('image/');
 static const maxBytes=10*1024*1024;
 static const _ext={'image/jpeg':'jpg','image/png':'png','image/webp':'webp',
  'image/heic':'heic','application/pdf':'pdf'};

 /// Normalises the mime type; null when OneSpace does not accept the file.
 static String? acceptedMime(String raw){
  final m=raw.trim().toLowerCase()=='image/jpg'?'image/jpeg':raw.trim().toLowerCase();
  return _ext.containsKey(m)?m:null;
 }
 String get extension=>_ext[mime]??'bin';

 /// A friendly default title: the file name without its extension.
 String get title{
  final base=name.contains('.')?name.substring(0,name.lastIndexOf('.')):name;
  final t=base.replaceAll(RegExp(r'[_\-]+'),' ').trim();
  return t.isEmpty?(isImage?'Shared photo':'Shared PDF'):(t.length>120?t.substring(0,120):t);
 }

 static SharedFile? fromExternal(Map<Object?,Object?> input){
  final bytes=input['fileBytes'];
  final mime=acceptedMime((input['fileMime']??'').toString());
  if(bytes is! List<int>||mime==null||bytes.isEmpty||bytes.length>maxBytes)return null;
  return SharedFile(name:(input['fileName']??'').toString(),mime:mime,bytes:bytes,
   note:(input['text']??'').toString().trim());
 }
}
