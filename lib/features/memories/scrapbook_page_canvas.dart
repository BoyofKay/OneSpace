import 'package:material_ui/material_ui.dart';
import 'scrapbook_templates.dart';

/// Fixed artboard used for on-screen preview and high-resolution PNG export.
/// Templates are responsive compositions, not photo thumbnails in a list.
class ScrapbookPageCanvas extends StatelessWidget {
 const ScrapbookPageCanvas({
  super.key,required this.page,required this.photos,required this.signedUrls});
 final Map<String,dynamic> page;
 final Map<String,Map<String,dynamic>> photos;
 final Map<String,String> signedUrls;
 String text(String key)=>(page[key]??'').toString();
 Widget photo(int number,Color accent,{double rotation=0}){
  final id=page['photo_'+number.toString()+'_id']?.toString();
  final row=id==null?null:photos[id];
  final url=id==null?null:signedUrls[id];
  return Padding(padding:const EdgeInsets.all(5),
   child:Transform.rotate(angle:rotation,child:Container(
    decoration:BoxDecoration(color:Colors.white,
     borderRadius:BorderRadius.circular(7),
     boxShadow:const [BoxShadow(color:Color(0x22000000),blurRadius:9,offset:Offset(1,4))]),
    padding:const EdgeInsets.fromLTRB(6,6,6,15),
    child:ClipRRect(borderRadius:BorderRadius.circular(3),
     child:url==null?Container(color:accent.withAlpha(28),
      child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
       Icon(Icons.add_photo_alternate_outlined,color:accent,size:30),
       const SizedBox(height:3),
       Text('PHOTO '+number.toString(),style:TextStyle(
        fontSize:9,fontWeight:FontWeight.bold,color:accent)),
      ]))):
      Image.network(url,fit:BoxFit.cover,
       errorBuilder:(_,__,___)=>Center(child:Icon(Icons.broken_image_outlined,color:accent)),
       loadingBuilder:(ctx,child,progress)=>progress==null?child:
         Center(child:CircularProgressIndicator(color:accent,strokeWidth:2))),
    ),
   )));
 }
 @override Widget build(BuildContext context){
  final design=ScrapbookTemplates.get(text('template_key'));
  final key=design.key;
  Widget imageSection;
  if(key=='our_adventures'){
   imageSection=Row(children:[
    Expanded(flex:5,child:photo(1,design.accent)),
    Expanded(flex:4,child:Column(children:[
     Expanded(child:photo(2,design.accent)),
     Expanded(child:photo(3,design.accent)),
    ])),
   ]);
  }else if(key=='milestone_story'){
   imageSection=Column(children:[
    Expanded(flex:7,child:Row(children:[
     Expanded(child:photo(1,design.accent)),
     Expanded(child:photo(2,design.accent)),
    ])),
    Expanded(flex:5,child:photo(3,design.accent)),
   ]);
  }else if(key=='polaroid_letters'){
   imageSection=Row(children:[
    Expanded(child:photo(1,design.accent,rotation:-0.025)),
    Expanded(child:photo(2,design.accent,rotation:0.03)),
   ]);
  }else{
   imageSection=Column(children:[
    Expanded(flex:8,child:photo(1,design.accent)),
    Expanded(flex:5,child:photo(2,design.accent)),
   ]);
  }
  return AspectRatio(aspectRatio:0.76,child:Container(
   decoration:BoxDecoration(color:design.paper,
    borderRadius:BorderRadius.circular(8)),
   padding:const EdgeInsets.fromLTRB(15,15,15,13),
   child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Row(children:[
     Icon(design.icon,color:design.accent,size:19),
     const SizedBox(width:7),
     Expanded(child:Text(design.name.toUpperCase(),
      style:TextStyle(letterSpacing:2,fontSize:10,
       color:design.accent,fontWeight:FontWeight.w800))),
     Container(width:38,height:2,color:design.accent),
    ]),
    const SizedBox(height:10),
    Text(text('title').isEmpty?'A chapter of our story':text('title'),
     maxLines:2,overflow:TextOverflow.ellipsis,
     style:TextStyle(fontSize:23,fontWeight:FontWeight.bold,
      color:design.ink,height:1.0)),
    const SizedBox(height:4),
    Text(text('subtitle').isEmpty?'The moments worth keeping':text('subtitle'),
     maxLines:2,style:TextStyle(fontSize:11,color:design.ink.withAlpha(180))),
    const SizedBox(height:9),
    Expanded(child:imageSection),
    const SizedBox(height:6),
    Container(height:1,color:design.accent.withAlpha(100)),
    const SizedBox(height:7),
    if(text('highlight_text').isNotEmpty)
     Text('“'+text('highlight_text')+'”',
      maxLines:2,overflow:TextOverflow.ellipsis,
      style:TextStyle(fontSize:13,fontWeight:FontWeight.bold,
       fontStyle:FontStyle.italic,color:design.accent)),
    if(text('highlight_text').isNotEmpty)const SizedBox(height:5),
    Text(text('story_text').isEmpty?
     'Add a few words about what made this day special.':text('story_text'),
     maxLines:key=='little_moments'?4:3,overflow:TextOverflow.ellipsis,
     style:TextStyle(color:design.ink,fontSize:12,height:1.3)),
    const SizedBox(height:5),
    Row(mainAxisAlignment:MainAxisAlignment.end,children:[
     Icon(Icons.favorite,color:design.accent,size:9),
     const SizedBox(width:4),
     Text('ONE SPACE · OUR STORY',style:TextStyle(
      letterSpacing:1,fontSize:8,fontWeight:FontWeight.bold,color:design.accent)),
    ]),
   ]),
  ));
 }
}
