import 'package:material_ui/material_ui.dart';

/// All templates are entirely local assets: no remote theme service and
/// no technology-heavy design customization required from either partner.
class ScrapbookDesign{
 const ScrapbookDesign({
  required this.key,required this.name,required this.subtitle,
  required this.photoCount,required this.paper,required this.ink,
  required this.accent,required this.icon});
 final String key,name,subtitle;
 final int photoCount;
 final Color paper,ink,accent;
 final IconData icon;
}
class ScrapbookTemplates {
 const ScrapbookTemplates._();
 static const designs=<ScrapbookDesign>[
  ScrapbookDesign(key:'polaroid_letters',name:'Love Letters',
   subtitle:'Warm keepsakes, two photos and a little note',
   photoCount:2,paper:Color(0xFFFFF5E8),
   ink:Color(0xFF4A3540),accent:Color(0xFFCC7285),
   icon:Icons.favorite_border),
  ScrapbookDesign(key:'our_adventures',name:'Our Adventures',
   subtitle:'Travel postcards, three photos and a story',
   photoCount:3,paper:Color(0xFFECF3F0),
   ink:Color(0xFF21464B),accent:Color(0xFF4D9688),
   icon:Icons.explore_outlined),
  ScrapbookDesign(key:'little_moments',name:'Little Moments',
   subtitle:'An editorial photo diary for ordinary magic',
   photoCount:2,paper:Color(0xFFFFF9EF),
   ink:Color(0xFF514B48),accent:Color(0xFFD99950),
   icon:Icons.auto_awesome_outlined),
  ScrapbookDesign(key:'milestone_story',name:'Milestone Story',
   subtitle:'A dramatic timeline for life-changing days',
   photoCount:3,paper:Color(0xFFECEEF5),
   ink:Color(0xFF272E4B),accent:Color(0xFF7179C3),
   icon:Icons.celebration_outlined),
 ];
 static ScrapbookDesign get(String? key){
  for(final d in designs){if(d.key==key)return d;}
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
