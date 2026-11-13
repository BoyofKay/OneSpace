class OccasionBudgetSummary {
 const OccasionBudgetSummary({
  required this.budget,required this.planned,
  required this.spent,required this.wishlist,required this.currency,
  required this.unpriced,required this.foreignCurrency,
 });
 final double? budget;
 final double planned,spent,wishlist;
 final String currency;
 final int unpriced,foreignCurrency;
 double get committed=>planned+spent;
 double? get available=>budget==null?null:budget!-committed;
 bool get overBudget=>available!=null&&available! < 0;
 double get progress=>budget==null||budget!<=0?0:
  (committed/budget!).clamp(0.0,1.0).toDouble();
}

class OccasionBudgetRules {
 const OccasionBudgetRules._();
 static double? amount(Object? raw){
  if(raw==null)return null;
  final value=raw is num?raw.toDouble():double.tryParse(raw.toString());
  return value==null||!value.isFinite||value<0?null:value;
 }
 static OccasionBudgetSummary summarize(Map<String,dynamic> plan,
   List<Map<String,dynamic>> items){
  final code=(plan['currency']??'USD').toString().toUpperCase();
  final budget=amount(plan['budget']);
  double planned=0,spent=0,wishlist=0;
  var unpriced=0,foreign=0;
  for(final item in items){
   if(item['archived_at']!=null||item['status']=='cancelled')continue;
   final price=amount(item['unit_price']);
   final actual=amount(item['actual_unit_price']);
   final quantity=(item['quantity'] is num)
      ? (item['quantity'] as num).toInt():1;
   final n=quantity<1?1:quantity;
   if((item['currency']??code).toString().toUpperCase()!=code){
    foreign++;continue;
   }
   final stage=(item['status']??'wish').toString();
   if(stage=='purchased'){
    if(actual==null&&price==null){unpriced++;continue;}
    spent+=(actual??price!)*n;
   }else if(stage=='planned'){
    if(price==null){unpriced++;continue;}
    planned+=price*n;
   }else if(stage=='wish'||stage=='shortlisted'){
    if(price!=null)wishlist+=price*n;
   }
  }
  return OccasionBudgetSummary(budget:budget,planned:planned,
   spent:spent,wishlist:wishlist,currency:code,unpriced:unpriced,
   foreignCurrency:foreign);
 }
 static bool isHttpUrl(String value){
  if(value.trim().isEmpty)return true;
  final uri=Uri.tryParse(value.trim());
  return uri!=null&&(uri.scheme=='https'||uri.scheme=='http')&&uri.hasAuthority;
 }
}
