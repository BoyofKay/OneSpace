/// Personal intentions to send love. These rules never transmit gestures,
/// and they never inspect private partner feelings or activity.
class LovePromptRules{
 const LovePromptRules._();
 static const slots=<String,int>{
  'morning':9,'after_work':18,'evening':21,
 };
 static DateTime nextTime(DateTime now,int hour){
  var result=DateTime(now.year,now.month,now.day,hour);
  if(!result.isAfter(now.add(const Duration(minutes:2)))){
   result=DateTime(now.year,now.month,now.day+1,hour);
  }
  return result;
 }
 static String label(String kind)=>switch(kind){
  'any'=>'Any loving gesture',
  'hug'=>'Send a hug',
  'miss_you'=>'I miss you',
  'thinking'=>'Thinking of you',
  'smile'=>'You made me smile',
  'morning'=>'Good morning',
  'goodnight'=>'Sweet dreams',
  'proud'=>'Proud of you',
  'support'=>'You have got this',
  'thanks'=>'Thank you',
  'lucky'=>'Lucky to have you',
  'miss_together'=>'I miss us together',
  'miss_home'=>'I miss our home',
  'miss_kids'=>'I miss our kids',
  'miss_pets'=>'I miss our furry ones',
  'love_you'=>'I love you',
  'kiss'=>'Send a kiss',
  'sorry'=>'I am sorry',
  'celebrate'=>'Congratulations!',
  'get_well'=>'Feel better soon',
  'safe_travels'=>'Safe travels',
  'call_me'=>'Call me when you can',
  'date_night'=>'Cannot wait for our date',
  _=>'Any loving gesture',
 };
 static String message(String kind)=>
  kind=='any'?'Open A little love and choose a thoughtful gesture.':
  'Open A little love and choose a message from the '+
   label(kind)+' collection.';
 static String? lastSentSummary(String? stamp,DateTime now){
  final time=DateTime.tryParse(stamp??'')?.toLocal();
  if(time==null)return null;
  final ago=now.difference(time);
  if(ago.isNegative)return 'Sent recently';
  if(ago.inMinutes<60)return 'Last sent less than an hour ago';
  if(ago.inHours<24)return 'Last sent '+ago.inHours.toString()+' hours ago';
  return 'Last sent '+ago.inDays.toString()+' days ago';
 }
}
