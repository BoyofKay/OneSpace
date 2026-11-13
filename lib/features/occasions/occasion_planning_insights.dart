import 'occasion_budget_rules.dart';
import 'occasion_rules.dart';

class OccasionPlanningInsight {
 const OccasionPlanningInsight({
  required this.code,required this.message,required this.actionLabel,
  required this.action,required this.priority});
 final String code,message,actionLabel,action;
 final int priority;
}

/// Transparent, local decision support. No user content is sent to an AI model.
class OccasionPlanningInsights{
 const OccasionPlanningInsights._();
 static List<OccasionPlanningInsight> suggest({
  required Map<String,dynamic> plan,
  required OccasionBudgetSummary budget,
  required List<Map<String,dynamic>> items,
  required DateTime today,
 }){
  final suggestions=<OccasionPlanningInsight>[];
  final original=DateTime.tryParse(plan['occasion_on']?.toString()??'');
  final next=original==null?null:OccasionRules.nextDate(
   original:original,annual:plan['annual']==true,today:today);
  final days=OccasionRules.daysUntil(next,today);
  final active=items.where((e)=>e['archived_at']==null&&
    e['status']!='cancelled').toList();
  final reserved=active.where((e)=>e['status']=='planned').length;
  final purchased=active.where((e)=>e['status']=='purchased').length;
  final wishes=active.where((e)=>e['status']=='wish'||
   e['status']=='shortlisted').length;
  if(budget.overBudget){
   suggestions.add(const OccasionPlanningInsight(
    code:'over_budget',
    message:'Reservations and purchases are above the occasion budget. Review your shopping priorities before committing more.',
    actionLabel:'Review items',action:'review',priority:0));
  }
  if(days!=null&&days>=0&&days<=14&&reserved+purchased==0){
   suggestions.add(OccasionPlanningInsight(
    code:'approaching',
    message:'Only '+days.toString()+' day(s) until the occasion, and nothing is reserved or purchased yet.',
    actionLabel:'Plan a purchase',action:'purchase',priority:1));
  }
  if(budget.unpriced>0){
   suggestions.add(OccasionPlanningInsight(
    code:'missing_prices',
    message:budget.unpriced.toString()+
     ' committed item(s) have no price. Add estimates so the remaining balance is trustworthy.',
    actionLabel:'Review items',action:'review',priority:2));
  }
  if(budget.foreignCurrency>0){
   suggestions.add(OccasionPlanningInsight(
    code:'currency',
    message:budget.foreignCurrency.toString()+
     ' item(s) use different currencies. They are not automatically subtracted from this budget.',
    actionLabel:'Review items',action:'review',priority:3));
  }
  if(wishes>0&&reserved+purchased==0){
   suggestions.add(const OccasionPlanningInsight(
    code:'promote_wish',
    message:'You have ideas waiting in the wishlist. Reserve your favorite choice to start tracking its cost.',
    actionLabel:'Review wishes',action:'review',priority:4));
  }
  if(active.isEmpty){
   suggestions.add(const OccasionPlanningInsight(
    code:'empty',
    message:'Start with a meaningful gift idea, or import an option you already compared in Coordinate.',
    actionLabel:'Browse Activity ideas',action:'import',priority:5));
  }
  if(budget.budget==null){
   suggestions.add(const OccasionPlanningInsight(
    code:'set_budget',
    message:'Set an occasion budget to see the remaining amount after every reserved or purchased item.',
    actionLabel:'Set a budget',action:'budget',priority:6));
  }
  return suggestions..sort((a,b)=>a.priority.compareTo(b.priority));
 }
}
