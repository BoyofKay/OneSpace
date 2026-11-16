import 'package:material_ui/material_ui.dart';
import 'scrapbook_templates.dart';
import 'package:onespace/l10n/phrases.dart';

/// Fixed artboard used for on-screen preview, the view mode and export.
///
/// R70: ten photo arrangements; in edit mode every photo slot and every
/// text on the page can be tapped to change it right there.
class ScrapbookPageCanvas extends StatelessWidget {
 const ScrapbookPageCanvas({
  super.key,required this.page,required this.photos,required this.signedUrls,
  this.onPhotoTap,this.onTextTap});
 final Map<String,dynamic> page;
 final Map<String,Map<String,dynamic>> photos;
 final Map<String,String> signedUrls;
 /// Edit mode: tap a photo slot (1–4) or a text ('title', 'subtitle',
 /// 'highlight_text', 'story_text').
 final void Function(int slot)? onPhotoTap;
 final void Function(String field)? onTextTap;
 bool get editing=>onTextTap!=null;
 String text(String key)=>(page[key]??'').toString();

 Widget photo(int number,ScrapbookDesign d,{double rotation=0,bool frame=true}){
  final id=page['photo_${number}_id']?.toString();
  final url=id==null?null:signedUrls[id];
  final empty=Container(color:d.accent.withAlpha(28),
   child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
    Icon(Icons.add_photo_alternate_outlined,color:d.accent,size:30),
    const SizedBox(height:3),
    Text(tt(editing?'Tap to add a photo':'PHOTO ')+(editing?'':number.toString()),
     textAlign:TextAlign.center,
     style:TextStyle(fontSize:9,fontWeight:FontWeight.bold,color:d.accent)),
   ])));
  final image=url==null?empty:Image.network(url,fit:BoxFit.cover,
   errorBuilder:(_,__,___)=>Center(child:Icon(Icons.broken_image_outlined,color:d.accent)),
   loadingBuilder:(ctx,child,progress)=>progress==null?child:
    Center(child:CircularProgressIndicator(color:d.accent,strokeWidth:2)));
  Widget body=frame?Container(
   decoration:BoxDecoration(color:d.dark?const Color(0xFFF7F2EA):Colors.white,
    borderRadius:BorderRadius.circular(7),
    boxShadow:const [BoxShadow(color:Color(0x22000000),blurRadius:9,offset:Offset(1,4))]),
   padding:const EdgeInsetsDirectional.fromSTEB(6,6,6,15),
   child:ClipRRect(borderRadius:BorderRadius.circular(3),child:SizedBox.expand(child:image)))
   :ClipRRect(borderRadius:BorderRadius.circular(4),child:SizedBox.expand(child:image));
  if(onPhotoTap!=null){
   body=GestureDetector(onTap:()=>onPhotoTap!(number),child:Stack(fit:StackFit.expand,children:[
    body,
    if(url!=null)Positioned(right:8,top:8,child:CircleAvatar(radius:12,backgroundColor:Colors.black45,
     child:const Icon(Icons.edit,size:13,color:Colors.white))),
   ]));
  }
  return Padding(padding:const EdgeInsets.all(5),child:Transform.rotate(angle:rotation,child:body));
 }

 Widget _photos(ScrapbookDesign d){
  switch(d.layout){
   case 'pair_tilted':
    return Row(children:[
     Expanded(child:photo(1,d,rotation:-0.025)),
     Expanded(child:photo(2,d,rotation:0.03)),
    ]);
   case 'left_three':
    return Row(children:[
     Expanded(flex:5,child:photo(1,d)),
     Expanded(flex:4,child:Column(children:[Expanded(child:photo(2,d)),Expanded(child:photo(3,d))])),
    ]);
   case 'two_top_one':
    return Column(children:[
     Expanded(flex:7,child:Row(children:[Expanded(child:photo(1,d)),Expanded(child:photo(2,d))])),
     Expanded(flex:5,child:photo(3,d)),
    ]);
   case 'hero_three':
    return Column(children:[
     Expanded(flex:6,child:photo(1,d)),
     Expanded(flex:4,child:Row(children:[Expanded(child:photo(2,d)),Expanded(child:photo(3,d))])),
    ]);
   case 'grid4':
    return Column(children:[
     Expanded(child:Row(children:[Expanded(child:photo(1,d,rotation:-.012)),Expanded(child:photo(2,d,rotation:.015))])),
     Expanded(child:Row(children:[Expanded(child:photo(3,d,rotation:.01)),Expanded(child:photo(4,d,rotation:-.015))])),
    ]);
   case 'strip4':
    return Center(child:AspectRatio(aspectRatio:.42,child:Container(
     decoration:BoxDecoration(color:const Color(0xFF0F0D0C),borderRadius:BorderRadius.circular(4)),
     padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
     child:Column(children:[for(var n=1;n<=4;n++)Expanded(child:photo(n,d,frame:false))]))));
   case 'single':
    return photo(1,d,rotation:-.01);
   case 'miles_apart':
    return Row(children:[
     Expanded(child:Column(children:[Expanded(child:photo(1,d,rotation:-.02)),
      Text(tt('HERE'),style:TextStyle(fontSize:9,letterSpacing:2,color:d.accent,fontWeight:FontWeight.bold))])),
     SizedBox(width:26,child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
      for(var i=0;i<5;i++)Container(width:2,height:8,margin:const EdgeInsets.symmetric(vertical:3),color:d.accent.withAlpha(150)),
      Icon(Icons.flight,color:d.accent,size:18),
      for(var i=0;i<5;i++)Container(width:2,height:8,margin:const EdgeInsets.symmetric(vertical:3),color:d.accent.withAlpha(150)),
     ])),
     Expanded(child:Column(children:[Expanded(child:photo(2,d,rotation:.02)),
      Text(tt('THERE'),style:TextStyle(fontSize:9,letterSpacing:2,color:d.accent,fontWeight:FontWeight.bold))])),
    ]);
   case 'postcard':
    return Stack(children:[
     Positioned.fill(child:photo(1,d)),
     PositionedDirectional(end:12,top:12,child:Transform.rotate(angle:.08,child:Container(
      width:46,height:56,
      decoration:BoxDecoration(color:Colors.white,border:Border.all(color:d.accent,width:2),
       borderRadius:BorderRadius.circular(3)),
      child:Icon(Icons.favorite,color:d.accent,size:22)))),
    ]);
   default: // hero_two
    return Column(children:[
     Expanded(flex:8,child:photo(1,d)),
     Expanded(flex:5,child:photo(2,d)),
    ]);
  }
 }

 Widget _tap(String field,Widget child)=>onTextTap==null?child:GestureDetector(
  behavior:HitTestBehavior.opaque,onTap:()=>onTextTap!(field),
  child:Container(decoration:BoxDecoration(border:Border.all(color:const Color(0x33888888)),
   borderRadius:BorderRadius.circular(4)),padding:const EdgeInsets.symmetric(horizontal:3,vertical:1),child:child));

 @override Widget build(BuildContext context){
  final d=ScrapbookTemplates.get(text('template_key'));
  final title=text('title'),sub=text('subtitle'),quote=text('highlight_text'),story=text('story_text');
  return AspectRatio(aspectRatio:0.76,child:Container(
   decoration:BoxDecoration(color:d.paper,borderRadius:BorderRadius.circular(8)),
   padding:const EdgeInsetsDirectional.fromSTEB(15,15,15,13),
   child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Row(children:[
     Icon(d.icon,color:d.accent,size:19),
     const SizedBox(width:7),
     Expanded(child:Text(tt(d.name).toUpperCase(),
      style:TextStyle(letterSpacing:2,fontSize:10,color:d.accent,fontWeight:FontWeight.w800))),
     Container(width:38,height:2,color:d.accent),
    ]),
    const SizedBox(height:10),
    _tap('title',Text(title.isEmpty?tt(editing?'Tap to write the title':'A chapter of our story'):title,
     maxLines:2,overflow:TextOverflow.ellipsis,
     style:TextStyle(fontSize:23,fontWeight:FontWeight.bold,color:d.ink.withAlpha(title.isEmpty&&editing?120:255),height:1.0))),
    const SizedBox(height:4),
    _tap('subtitle',Text(sub.isEmpty?tt(editing?'Tap to add a subtitle':'The moments worth keeping'):sub,
     maxLines:2,style:TextStyle(fontSize:11,color:d.ink.withAlpha(180)))),
    const SizedBox(height:9),
    Expanded(child:_photos(d)),
    const SizedBox(height:6),
    Container(height:1,color:d.accent.withAlpha(100)),
    const SizedBox(height:7),
    if(quote.isNotEmpty||editing)_tap('highlight_text',Text(
     quote.isEmpty?tt('Tap to add a favourite quote'):'“$quote”',
     maxLines:2,overflow:TextOverflow.ellipsis,
     style:TextStyle(fontSize:13,fontWeight:FontWeight.bold,fontStyle:FontStyle.italic,
      color:d.accent.withAlpha(quote.isEmpty?140:255)))),
    if(quote.isNotEmpty||editing)const SizedBox(height:5),
    _tap('story_text',Text(story.isEmpty?
     tt(editing?'Tap to write a few words about this day':'Add a few words about what made this day special.'):story,
     maxLines:d.layout=='single'||d.layout=='postcard'?5:3,overflow:TextOverflow.ellipsis,
     style:TextStyle(color:d.ink,fontSize:12,height:1.3))),
    const SizedBox(height:5),
    Row(mainAxisAlignment:MainAxisAlignment.end,children:[
     Icon(Icons.favorite,color:d.accent,size:9),
     const SizedBox(width:4),
     Text(tt('ONE SPACE · OUR STORY'),style:TextStyle(
      letterSpacing:1,fontSize:8,fontWeight:FontWeight.bold,color:d.accent)),
    ]),
   ]),
  ));
 }
}
