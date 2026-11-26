import 'occasion_budget_rules.dart';
import 'occasion_rules.dart';
import 'package:onespace/l10n/phrases.dart';

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
  if(budget.overBudget){
   suggestions.add(OccasionPlanningInsight(
    code:'over_budget',
    message:tt('Reservations and purchases are above the occasion budget. Review your shopping priorities before committing more.'),
    actionLabel:tt('Review items'),action:'review',priority:0));
  }
  if(days!=null&&days>=0&&days<=14&&reserved+purchased==0){
   suggestions.add(OccasionPlanningInsight(
    code:'approaching',
    message:tt(days==1?'Only 1 day until the occasion, and nothing is reserved or purchased yet.'
      :'Only {} days until the occasion, and nothing is reserved or purchased yet.').replaceFirst('{}',days.toString()),
    actionLabel:tt('Plan a purchase'),action:'purchase',priority:1));
  }
  if(budget.unpriced>0){
   suggestions.add(OccasionPlanningInsight(
    code:'missing_prices',
    message:tt('{} committed item(s) have no price. Add estimates so the remaining balance is trustworthy.')
      .replaceFirst('{}',budget.unpriced.toString()),
    actionLabel:tt('Review items'),action:'review',priority:2));
  }
  if(budget.foreignCurrency>0){
   suggestions.add(OccasionPlanningInsight(
    code:'currency',
    message:tt('{} item(s) use different currencies. They are not automatically subtracted from this budget.')
      .replaceFirst('{}',budget.foreignCurrency.toString()),
    actionLabel:tt('Review items'),action:'review',priority:3));
  }
  if(active.isEmpty){
   suggestions.add(OccasionPlanningInsight(
    code:'empty',
    message:tt('Start with a gift idea or two. Compare them, then reserve your favorites.'),
    actionLabel:tt('Add a gift option'),action:'purchase',priority:5));
  }
  if(budget.budget==null){
   suggestions.add(OccasionPlanningInsight(
    code:'set_budget',
    message:tt('Set an occasion budget to see the remaining amount after every reserved or purchased item.'),
    actionLabel:tt('Set a budget'),action:'budget',priority:6));
  }
  return suggestions..sort((a,b)=>a.priority.compareTo(b.priority));
 }
}
