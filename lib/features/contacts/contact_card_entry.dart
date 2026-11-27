import '../coordinate/activity_contact.dart';

/// A standalone contact or a contact component inherited from an Activity.
/// The two types share a searchable view, never a duplicate storage record.
class ContactCardEntry{
 const ContactCardEntry({
   required this.id,required this.activityId,required this.activityTitle,
   required this.label,required this.contact,this.direct=false,
   this.createdBy='',this.visibility='shared',this.archivedAt,
   this.updatedAt,
 });
 final String id,activityId,activityTitle,label,createdBy,visibility;
 final ActivityContact contact;
 final bool direct;
 final String? archivedAt,updatedAt;
 bool get isDeleted=>archivedAt!=null;
 factory ContactCardEntry.fromRow(Map<String,dynamic> row){
   final data=row['payload'] is Map?
     Map<String,dynamic>.from(row['payload'] as Map):<String,dynamic>{};
   final relation=row['activities'] is Map?
     Map<String,dynamic>.from(row['activities'] as Map):<String,dynamic>{};
   return ContactCardEntry(
     id:row['id']?.toString()??'',
     activityId:row['activity_id']?.toString()??'',
     activityTitle:relation['title']?.toString()??'Activity',
     label:row['label']?.toString()??'Contact',
     contact:ActivityContact.fromPayload(data),
     createdBy:row['created_by']?.toString()??'',
     archivedAt:row['archived_at']?.toString(),
     updatedAt:row['updated_at']?.toString(),
   );
 }
 factory ContactCardEntry.fromDirect(Map<String,dynamic> row){
   final data=row['payload'] is Map?
     Map<String,dynamic>.from(row['payload'] as Map):<String,dynamic>{};
   return ContactCardEntry(
     id:row['id']?.toString()??'',activityId:'',activityTitle:'',
     label:row['label']?.toString()??'Contact',
     contact:ActivityContact.fromPayload(data),direct:true,
     visibility:row['visibility']?.toString()??'shared',
     createdBy:row['created_by']?.toString()??'',
     archivedAt:row['archived_at']?.toString(),
     updatedAt:row['updated_at']?.toString(),
   );
 }
 bool matches(String text){
   final q=text.trim().toLowerCase();
   if(q.isEmpty)return true;
   return [label,activityTitle,contact.person,contact.phone,
     contact.email,contact.address,contact.workingHours,
     contact.company,contact.role,contact.website,contact.note]
       .any((value)=>value.toLowerCase().contains(q));
 }
 static List<ContactCardEntry> filtered(
   List<ContactCardEntry> all,String query,
 )=>all.where((item)=>item.matches(query)).toList()
   ..sort((a,b)=>a.label.toLowerCase().compareTo(b.label.toLowerCase()));
}
