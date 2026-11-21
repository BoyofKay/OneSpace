import '../../core/form_kit.dart';
import '../../core/editor_scaffold.dart';
import '../../core/account_content_scope.dart';
import '../../core/app_env.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../coordinate/activity_contact.dart';
import 'world_contact_entry.dart';
import 'package:onespace/l10n/phrases.dart';

/// One editor for standalone contacts and existing Activity contact components.
class SavedContactEditor extends StatefulWidget{
 const SavedContactEditor({super.key,required this.spaceId,this.existing,this.imported});
 final String spaceId;
 final WorldContactEntry? existing;
 final ActivityContact? imported;
 @override State<SavedContactEditor> createState()=>_SavedContactEditorState();
}
class _SavedContactEditorState extends State<SavedContactEditor> with FormChangeTracker<SavedContactEditor>{
 /// R55: current form values; Save turns on only when they change.
 @override String get signature=>[name.text,person.text,phone.text,email.text,address.text,hours.text,notes.text,company.text,role.text,website.text,onlyMe].join('|');

 final db=Supabase.instance.client;
 late final TextEditingController name,person,phone,email,address,hours,notes,company,role,website;
 late bool onlyMe;
 bool busy=false;
 String? error;
 @override void initState(){
   super.initState();
   final c=widget.existing?.contact??widget.imported??const ActivityContact();
   name=TextEditingController(text:widget.existing?.label??c.person);
   person=TextEditingController(text:c.person);
   phone=TextEditingController(text:c.phone);
   email=TextEditingController(text:c.email);
   address=TextEditingController(text:c.address);
   hours=TextEditingController(text:c.workingHours);
   company=TextEditingController(text:c.company);
   role=TextEditingController(text:c.role);
   website=TextEditingController(text:c.website);
   notes=TextEditingController(text:c.note);
   onlyMe=widget.existing==null||widget.existing?.visibility=='private';
 }
 @override void dispose(){
   for(final c in [name,person,phone,email,address,hours,company,role,website,notes]){c.dispose();}
   super.dispose();
 }
 Widget field(TextEditingController c,String label,{int max=180,int lines=1,
   TextInputType? type,IconData? icon,String? hint})=>Padding(
     padding:const EdgeInsets.only(bottom:12),
     child:TextField(
       controller:c,maxLength:max,minLines:lines,maxLines:lines==1?1:lines+3,keyboardType:type,
       textCapitalization:type==null?TextCapitalization.sentences:TextCapitalization.none,
       decoration:InputDecoration(labelText:label,hintText:hint,
         prefixIcon:icon==null?null:Icon(icon),
         border:const OutlineInputBorder(),counterText:''),
     ));
 Future<void> save()async{
   if(busy)return;
   final label=name.text.trim();
   if(label.isEmpty){setState(()=>error='Give the contact a name.');return;}
   final contact=ActivityContact(
     person:person.text.trim().isEmpty?label:person.text.trim(),
     phone:phone.text.trim(),
     email:email.text.trim(),address:address.text.trim(),
     workingHours:hours.text.trim(),
     company:company.text.trim(),role:role.text.trim(),
     website:website.text.trim(),note:notes.text.trim(),
   );
   final invalid=contact.validate();
   if(invalid!=null){setState(()=>error=invalid);return;}
   setState((){busy=true;error=null;});
   try{
     final entry=widget.existing;
     final scopes=entry==null
         ? await AccountContentScope.load(db,
             legacySpaceId:widget.spaceId.isEmpty?null:widget.spaceId)
         : null;
     if(entry==null && (contact.phone.isNotEmpty||contact.email.isNotEmpty)){
       var candidateQuery=db.from('saved_contacts').select('id,label,payload');
       if(OneSpaceEnv.isProduction){
         candidateQuery=candidateQuery.eq('space_id',widget.spaceId);
       }
       final existingRows=await candidateQuery.limit(300);
       final normalizedPhone=contact.dialableNumber;
       final matching=existingRows.where((row){
        final payload=Map<String,dynamic>.from(row['payload'] as Map? ??const {});
        final known=ActivityContact.fromPayload(payload);
        return (normalizedPhone.isNotEmpty&&known.dialableNumber==normalizedPhone)||
         (contact.email.isNotEmpty&&known.email.toLowerCase()==contact.email.toLowerCase());
       }).toList();
       if(matching.isNotEmpty){
        if(!mounted)return;
        final confirm=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
         title:Text(tt('Possible duplicate contact')),
         content:Text(tt('You already have a saved card matching this phone number or email: ')+
          matching.first['label'].toString()+
          '. Save a separate card anyway?'),
         actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(tt('Review'))),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(tt('Save separately'))),
         ]));
        if(confirm!=true)return;
       }
     }
     if(entry==null){
       await db.from('saved_contacts').insert({
         ...scopes!.fieldsForNew(shared:!onlyMe),
         'created_by':db.auth.currentUser!.id,
         'label':label,'payload':contact.toPayload(),
       });
     }else if(entry.direct){
       await db.from('saved_contacts').update({
         'label':label,'payload':contact.toPayload(),
         // QA: immutable account vs couple ownership; scope changes must be
         // an explicit audited server operation, never a simple edit.
         if(OneSpaceEnv.isProduction) 'visibility':onlyMe?'private':'shared',
       }).eq('id',entry.id);
     }else{
       await db.from('activity_components').update({
         'label':label,'payload':contact.toPayload(),
       }).eq('id',entry.id).eq('activity_id',entry.activityId);
     }
     if(mounted)Navigator.pop(context,true);
   }on PostgrestException catch(e){
     if(mounted)setState(()=>error=e.message);
   }catch(_){
     if(mounted)setState(()=>error='Could not save contact. Retry.');
   }finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context){
   final fromActivity=widget.existing!=null&&!widget.existing!.direct;
   return EditorScaffold(title:widget.existing==null?tt('Add contact card'):tt('Edit contact card'),
   isNew:widget.existing==null,isChanged:()=>changed,isComplete:()=>name.text.trim().isNotEmpty,
   listenTo:[name,person,phone,email,address,hours,notes,company,role,website],saving:busy,onSave:save,
   meta:fromActivity?null:MetaStrip(personal:widget.spaceId.isEmpty,value:MetaValues(shared:!onlyMe),
     showVisibility: true,
     showBelongs:false,showDate:false,
     enabled:!busy && (OneSpaceEnv.isProduction || widget.existing==null),
     onChanged:(v)=>setState(()=>onlyMe=!v.shared)),
   body:SafeArea(child:ListView(
       padding:const EdgeInsets.all(18),children:[
       if(widget.imported!=null)Padding(
        padding:const EdgeInsets.only(bottom:12),
        child:Text(tt('Imported from your phone. Check the details before saving.'),
         style:Theme.of(context).textTheme.bodySmall)),
       if(fromActivity)Padding(padding:const EdgeInsets.only(bottom:12),
        child:Text(tt('This card comes from an Activity, so it follows that Activity’s privacy.'),
         style:Theme.of(context).textTheme.bodySmall)),
       field(name,'Name on the card *',icon:Icons.badge_outlined,hint:tt('Dr. Sara, Kids’ swim club…')),
       field(person,'Contact person',icon:Icons.person_outline),
       FormSection(tt('Reach them')),
       field(phone,'Phone',max:80,type:TextInputType.phone,icon:Icons.phone_outlined),
       field(email,'Email',max:254,type:TextInputType.emailAddress,icon:Icons.mail_outline),
       field(website,'Website',max:500,type:TextInputType.url,icon:Icons.language),
       FormSection(tt('Where and when')),
       field(address,'Address',max:1000,lines:2,icon:Icons.place_outlined),
       field(hours,'Opening or working hours',max:800,lines:2,icon:Icons.schedule),
       // R71: rarely used for clinics and shops, so folded until needed.
       ExpansionTile(tilePadding:EdgeInsets.zero,
        initiallyExpanded:company.text.isNotEmpty||role.text.isNotEmpty,
        leading:const Icon(Icons.work_outline),title:Text(tt('Work (company, job title)')),
        children:[
         field(company,'Company',icon:Icons.business_outlined),
         field(role,'Job title or role',icon:Icons.work_outline),
        ]),
       FormSection(tt('Notes')),
       field(notes,'Notes',max:3000,lines:3),
       if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:8),
         child:Text(tt(error!),style:TextStyle(
           color:Theme.of(context).colorScheme.error))),
     ])),
   );
 }
}
