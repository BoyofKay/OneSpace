import 'package:material_ui/material_ui.dart';

/// All templates are entirely local assets: no remote theme service and
/// no technology-heavy design customization required from either partner.
///
/// R70: 22 designs; 20 offered since 26 Nov 2026 (global app: the Eid and Ramadan
/// designs are retired but still render scrapbooks that already use them). [layout] says how the photos sit on the page:
/// pair_tilted · hero_two · left_three · two_top_one · grid4 · strip4 ·
/// single · miles_apart · hero_three · postcard.
class ScrapbookDesign{
 const ScrapbookDesign({
  required this.key,required this.name,required this.subtitle,
  required this.photoCount,required this.paper,required this.ink,
  required this.accent,required this.icon,this.layout='hero_two',this.dark=false,this.group='Everyday'});
 final String key,name,subtitle,layout,group;
 final int photoCount;
 final Color paper,ink,accent;
 final IconData icon;
 final bool dark;
}
class ScrapbookTemplates {
 const ScrapbookTemplates._();
 static const designs=<ScrapbookDesign>[
  // Love
  ScrapbookDesign(key:'polaroid_letters',name:'Love Letters',group:'Love',
   subtitle:'Warm keepsakes, two photos and a little note',layout:'pair_tilted',
   photoCount:2,paper:Color(0xFFFFF5E8),ink:Color(0xFF4A3540),accent:Color(0xFFCC7285),icon:Icons.favorite_border),
  ScrapbookDesign(key:'first_date',name:'Our First Date',group:'Love',
   subtitle:'Where it all began: the place, the outfit, the nerves',layout:'pair_tilted',
   photoCount:2,paper:Color(0xFFFFF0F3),ink:Color(0xFF5A2E3B),accent:Color(0xFFE0607E),icon:Icons.local_florist_outlined),
  ScrapbookDesign(key:'date_night',name:'Date Night',group:'Love',
   subtitle:'Candlelight colours for an evening out',layout:'hero_two',dark:true,
   photoCount:2,paper:Color(0xFF231B2E),ink:Color(0xFFF7EBDD),accent:Color(0xFFE6B566),icon:Icons.nightlife_outlined),
  ScrapbookDesign(key:'love_note',name:'Love Note',group:'Love',
   subtitle:'One photo and a big quote from the heart',layout:'single',
   photoCount:1,paper:Color(0xFFFFF7F0),ink:Color(0xFF4C2A32),accent:Color(0xFFB4536B),icon:Icons.mail_outline),
  ScrapbookDesign(key:'anniversary_gold',name:'Anniversary',group:'Love',
   subtitle:'Black and gold for the years together',layout:'hero_three',dark:true,
   photoCount:3,paper:Color(0xFF1C1A17),ink:Color(0xFFF5EBD7),accent:Color(0xFFD4AF37),icon:Icons.diamond_outlined),
  ScrapbookDesign(key:'wedding_day',name:'Wedding Day',group:'Love',
   subtitle:'Ivory and sage for the biggest yes',layout:'two_top_one',
   photoCount:3,paper:Color(0xFFFBF9F3),ink:Color(0xFF3F4A3C),accent:Color(0xFF8DA38A),icon:Icons.favorite),
  ScrapbookDesign(key:'miles_apart',name:'Miles Apart',group:'Love',
   subtitle:'You there, me here: two photos with the distance between',layout:'miles_apart',
   photoCount:2,paper:Color(0xFFEFF5FA),ink:Color(0xFF223A4E),accent:Color(0xFF4F8CC9),icon:Icons.connecting_airports),
  // Travel & life
  ScrapbookDesign(key:'our_adventures',name:'Our Adventures',group:'Travel & life',
   subtitle:'Travel postcards, three photos and a story',layout:'left_three',
   photoCount:3,paper:Color(0xFFECF3F0),ink:Color(0xFF21464B),accent:Color(0xFF4D9688),icon:Icons.explore_outlined),
  ScrapbookDesign(key:'postcard',name:'Postcard From…',group:'Travel & life',
   subtitle:'One wide photo, a stamp and a few lines',layout:'postcard',
   photoCount:1,paper:Color(0xFFF7F1E3),ink:Color(0xFF3A3228),accent:Color(0xFFC0582F),icon:Icons.local_post_office_outlined),
  ScrapbookDesign(key:'our_home',name:'Our Home',group:'Travel & life',
   subtitle:'Keys, boxes and the first night in',layout:'hero_two',
   photoCount:2,paper:Color(0xFFF4EFE8),ink:Color(0xFF473B30),accent:Color(0xFFA9774C),icon:Icons.home_outlined),
  ScrapbookDesign(key:'cooked_together',name:'Cooked Together',group:'Travel & life',
   subtitle:'A dish we made, with the recipe in the story',layout:'single',
   photoCount:1,paper:Color(0xFFFFF8EC),ink:Color(0xFF4B3A26),accent:Color(0xFFDE8A2F),icon:Icons.restaurant_outlined),
  ScrapbookDesign(key:'little_moments',name:'Little Moments',group:'Travel & life',
   subtitle:'An editorial photo diary for ordinary magic',layout:'hero_two',
   photoCount:2,paper:Color(0xFFFFF9EF),ink:Color(0xFF514B48),accent:Color(0xFFD99950),icon:Icons.auto_awesome_outlined),
  ScrapbookDesign(key:'film_strip',name:'Film Strip',group:'Travel & life',
   subtitle:'Four frames in a row, like an old photo booth',layout:'strip4',
   photoCount:4,paper:Color(0xFF2A2624),ink:Color(0xFFF2ECE6),accent:Color(0xFFEFC27A),icon:Icons.theaters_outlined,dark:true),
  // Family
  ScrapbookDesign(key:'family_day',name:'Family Day',group:'Family',
   subtitle:'Sunny colours for a day with everyone',layout:'two_top_one',
   photoCount:3,paper:Color(0xFFFFFAE8),ink:Color(0xFF4A4021),accent:Color(0xFFE2B33C),icon:Icons.family_restroom),
  ScrapbookDesign(key:'little_one',name:"Little One's Firsts",group:'Family',
   subtitle:'First steps, first words, first everything',layout:'left_three',
   photoCount:3,paper:Color(0xFFF0F6FF),ink:Color(0xFF2F4058),accent:Color(0xFF7FA8E0),icon:Icons.child_friendly_outlined),
  ScrapbookDesign(key:'graduation',name:'Graduation',group:'Family',
   subtitle:'Caps in the air: proud and pictured',layout:'hero_two',
   photoCount:2,paper:Color(0xFFEEF0F7),ink:Color(0xFF1F2A4D),accent:Color(0xFF3F51B5),icon:Icons.school_outlined),
  // Celebrations
  ScrapbookDesign(key:'birthday_bash',name:'Birthday Bash',group:'Celebrations',
   subtitle:'Confetti, candles and four photos',layout:'grid4',
   photoCount:4,paper:Color(0xFFFFF4FA),ink:Color(0xFF4A2E46),accent:Color(0xFFD25FA4),icon:Icons.cake_outlined),
  ScrapbookDesign(key:'milestone_story',name:'Milestone Story',group:'Celebrations',
   subtitle:'A dramatic timeline for life-changing days',layout:'two_top_one',
   photoCount:3,paper:Color(0xFFECEEF5),ink:Color(0xFF272E4B),accent:Color(0xFF7179C3),icon:Icons.celebration_outlined),
  // Looking back
  ScrapbookDesign(key:'year_in_review',name:'Our Year',group:'Looking back',
   subtitle:'Four photos for the year that was',layout:'grid4',
   photoCount:4,paper:Color(0xFFF5F5F2),ink:Color(0xFF2E2E2E),accent:Color(0xFFE76F51),icon:Icons.calendar_month_outlined),
  ScrapbookDesign(key:'four_seasons',name:'Four Seasons',group:'Looking back',
   subtitle:'Winter, spring, summer, autumn: one photo each',layout:'grid4',
   photoCount:4,paper:Color(0xFFF2F7F1),ink:Color(0xFF2C3E2D),accent:Color(0xFF6A994E),icon:Icons.eco_outlined),
 ];
 /// Not offered for new scrapbooks; kept so existing ones keep their look.
 static const retiredDesigns=<ScrapbookDesign>[
  ScrapbookDesign(key:'eid_joy',name:'Eid Joy',group:'Celebrations',
   subtitle:'Green and gold for Eid mornings',layout:'hero_three',
   photoCount:3,paper:Color(0xFFF1F7F0),ink:Color(0xFF1F4228),accent:Color(0xFFB8963E),icon:Icons.mosque_outlined),
  ScrapbookDesign(key:'ramadan_nights',name:'Ramadan Nights',group:'Celebrations',
   subtitle:'Lanterns and a crescent moon for iftar memories',layout:'pair_tilted',dark:true,
   photoCount:2,paper:Color(0xFF14213D),ink:Color(0xFFF3E9D2),accent:Color(0xFFF2C14E),icon:Icons.nights_stay_outlined),
 ];
 static List<String> get groups=>[for(final d in designs)d.group].toSet().toList();
 static ScrapbookDesign get(String? key){
  for(final d in designs){if(d.key==key)return d;}
  for(final d in retiredDesigns){if(d.key==key)return d;}
  return designs.first;
 }
 static String? validateTitle(String title){
  final value=title.trim();
  if(value.isEmpty)return 'Give your scrapbook a name.';
  if(value.length>120)return 'Keep the scrapbook title under 120 characters.';
  return null;
 }
 static int requiredPhotos(String? key)=>get(key).photoCount;
 static String compactDate(DateTime d)=>
  '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
}
