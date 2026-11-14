import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../coordinate/activity_contact.dart';
import 'world_contact_entry.dart';

/// One editor for standalone contacts and existing Activity contact components.
class SavedContactEditor extends StatefulWidget{
 const SavedContactEditor({super.key,required this.spaceId,this.existing,this.imported});
 final String spaceId;
 final WorldContactEntry? existing;
 final ActivityContact? imported;
 @override State<SavedContactEditor> createState()=>_SavedContactEditorState();
}
class _SavedContactEditorState extends State<SavedContactEditor>{
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
   TextInputType? type})=>Padding(
     padding:const EdgeInsets.only(bottom:12),
     child:TextField(
       controller:c,maxLength:max,maxLines:lines,keyboardType:type,
       decoration:InputDecoration(labelText:label,
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
     if(entry==null && (contact.phone.isNotEmpty||contact.email.isNotEmpty)){
       final existingRows=await db.from('saved_contacts')
        .select('id,label,payload').eq('space_id',widget.spaceId).limit(300);
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
         title:const Text('Possible duplicate contact'),
         content:Text('You already have a saved card matching this phone number or email: '+
          matching.first['label'].toString()+
          '. Save a separate card anyway?'),
         actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Review')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save separately')),
         ]));
        if(confirm!=true)return;
       }
     }
     if(entry==null){
       await db.from('saved_contacts').insert({
         'space_id':widget.spaceId,'created_by':db.auth.currentUser!.id,
         'label':label,'payload':contact.toPayload(),
         'visibility':onlyMe?'private':'shared',
       });
     }else if(entry.direct){
       await db.from('saved_contacts').update({
         'label':label,'payload':contact.toPayload(),
         'visibility':onlyMe?'private':'shared',
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
   return Scaffold(
     appBar:AppBar(title:Text(widget.existing==null?'Remember someone':
       'Edit contact card')),
     body:SafeArea(child:ListView(
       padding:const EdgeInsets.all(18),children:[
       const Text('Contact card',style:TextStyle(
         fontSize:19,fontWeight:FontWeight.w700)),
       const SizedBox(height:6),
       if(widget.imported!=null)const Padding(
        padding:EdgeInsets.only(bottom:8),
        child:Text('Imported from your phone. Review the details and choose privacy before saving.')),
       Text(fromActivity?'This contact belongs to its original Activity.':
         'Save a person or place directly, without creating an Activity.',
         style:Theme.of(context).textTheme.bodySmall),
       const SizedBox(height:16),
       field(name,'Contact card name'),
       field(person,'Contact person'),
       field(phone,'Phone number',max:80,type:TextInputType.phone),
       field(email,'Email',max:254,type:TextInputType.emailAddress),
       field(address,'Address',max:1000,lines:2),
       field(hours,'Working hours',max:800,lines:2),
       field(company,'Company'),
       field(role,'Job title / role'),
       field(website,'Website',max:500,type:TextInputType.url),
       field(notes,'Notes',max:3000,lines:4),
       if(!fromActivity)SwitchListTile(
         title:const Text('Only me'),
         subtitle:const Text('Off: both partners can see this card.'),
         value:onlyMe,
         onChanged:busy?null:(value)=>setState(()=>onlyMe=value)),
       if(fromActivity)const Text(
         'Visibility is inherited from the Activity.',
       ),
       if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:8),
         child:Text(error!,style:TextStyle(
           color:Theme.of(context).colorScheme.error))),
       const SizedBox(height:12),
       FilledButton.icon(
         onPressed:busy?null:save,
         icon:const Icon(Icons.save_outlined),
         label:Text(busy?'Saving…':'Save contact')),
       const SizedBox(height:30),
     ])),
   );
 }
}
