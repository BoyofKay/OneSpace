/// Optional acknowledgments are visible to both participants, but only the
/// original sender of an answered request can create or edit the reaction.
/// The database's RLS policies remain the actual authority.
class CheckinAcknowledgementRules {
 const CheckinAcknowledgementRules._();

 static const labels=<String,String>{
  'heart':'Sending love',
  'thank_you':'Thank you for sharing',
  'hug':'Sending a hug',
 };

 static bool canAcknowledge(
  Map<String,dynamic> request,String? userId,
 )=>userId!=null&&request['sender_id']==userId&&
  request['responded_at']!=null;

 static Map<String,dynamic>? forRequest(
  Iterable<Map<String,dynamic>> acknowledgements,
  Object? requestId,
 ){
  for(final row in acknowledgements){
   if(row['request_id']==requestId)return row;
  }
  return null;
 }

 static String? label(Object? choice)=>labels[choice?.toString()];
}
