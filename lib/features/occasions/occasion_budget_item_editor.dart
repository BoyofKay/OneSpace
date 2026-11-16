import '../../core/preferred_currency.dart';
import '../../core/editor_scaffold.dart';
import '../../core/form_kit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'occasion_budget_rules.dart';
import 'package:onespace/l10n/phrases.dart';

/// R68: an idea is only Wishlist or Considering; Reserve, Mark as purchased
/// and Exclude live in the gift's ⋮ menu.
const occasionItemStages={'wish':'Wishlist','shortlisted':'Considering'};

String _day(DateTime d)=>'${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

/// A gift option: what it is, what it costs and where to get it.
class OccasionBudgetItemEditor extends StatefulWidget{
 const OccasionBudgetItemEditor({super.key,required this.plan,
  this.existing,this.initialStatus='wish'});
 final Map<String,dynamic> plan;
 final Map<String,dynamic>? existing;
 final String initialStatus;
 @override State<OccasionBudgetItemEditor> createState()=>_OccasionBudgetItemEditorState();
}
class _OccasionBudgetItemEditorState extends State<OccasionBudgetItemEditor> with FormChangeTracker<OccasionBudgetItemEditor>{
 @override String get signature=>[title.text,qty.text,price.text,currency.text,notes.text,url.text,
  merchant.text,rating,preference,status].join('|');
 final db=Supabase.instance.client;
 late final TextEditingController title,qty,price,currency,notes,url,merchant;
 double? rating;
 int? preference;
 late String status;
 bool busy=false;
 String? error;
 @override void initState(){
  super.initState();
  final p=widget.existing??{};
  title=TextEditingController(text:(p['title']??'').toString());
  qty=TextEditingController(text:(p['quantity']??1).toString());
  price=TextEditingController(text:(p['unit_price']??'').toString());
  currency=TextEditingController(text:(p['currency']??widget.plan['currency']??PreferredCurrency.code).toString());
  notes=TextEditingController(text:(p['notes']??'').toString());
  url=TextEditingController(text:(p['source_url']??'').toString());
  merchant=TextEditingController(text:(p['merchant']??'').toString());
  rating=(p['product_rating'] as num?)?.toDouble();
  preference=(p['preference_score'] as num?)?.toInt();
  status=(p['status']??widget.initialStatus).toString();
 }
 @override void dispose(){
  for(final c in [title,qty,price,currency,notes,url,merchant]){c.dispose();}
  super.dispose();
 }
 Future<void> save()async{
  if(busy)return;
  final count=int.tryParse(qty.text.trim());
  final estimated=price.text.trim().isEmpty?null:OccasionBudgetRules.amount(price.text.replaceAll(',',''));
  final code=currency.text.trim().toUpperCase();
  if(title.text.trim().isEmpty||title.text.trim().length>200){
   setState(()=>error='Name the gift (up to 200 characters).');return;
  }
  if(count==null||count<1||count>999){setState(()=>error='Quantity must be between 1 and 999.');return;}
  if((price.text.trim().isNotEmpty&&estimated==null)||(estimated!=null&&estimated>9999999999)){
   setState(()=>error='Use a valid price or leave it empty.');return;
  }
  if(!RegExp(r'^[A-Z]{3}$').hasMatch(code)){setState(()=>error='Use a three-letter currency.');return;}
  if(!OccasionBudgetRules.isHttpUrl(url.text)){setState(()=>error='Enter a valid product link (http/https).');return;}
  setState((){busy=true;error=null;});
  try{
   final values=<String,dynamic>{
    'title':title.text.trim(),'quantity':count,'unit_price':estimated,
    'currency':code,'status':status,'source_url':url.text.trim(),
    'notes':notes.text.trim(),'merchant':merchant.text.trim(),
    'product_rating':rating,'preference_score':preference,
   };
   if(widget.existing==null){
    await db.from('occasion_budget_items').insert({...values,'plan_id':widget.plan['id']});
   }else{
    await db.from('occasion_budget_items').update(values)
     .eq('id',widget.existing!['id']).eq('plan_id',widget.plan['id']);
   }
   if(mounted)Navigator.of(context).pop(true);
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){
   if(mounted)setState(()=>error='Could not save this gift. Try again.');
  }finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context){
  final theme=Theme.of(context);
  final idea=occasionItemStages.containsKey(status);
  return EditorScaffold(
   title:widget.existing==null?tt('Add a gift option'):tt('Edit gift'),
   isNew:widget.existing==null,isChanged:()=>changed,isComplete:()=>title.text.trim().isNotEmpty,
   listenTo:[title,qty,price,currency,notes,url,merchant],saving:busy,onSave:save,
   body:ListView(padding:const EdgeInsets.all(18),children:[
     TextField(controller:title,maxLength:200,autofocus:widget.existing==null,
      textCapitalization:TextCapitalization.sentences,
      decoration:InputDecoration(labelText:tt('Gift, item or experience *'),border:const OutlineInputBorder())),
     if(idea)ChoiceRow<String>(label:tt('Status'),options:occasionItemStages,selected:status,
      icons:const {'wish':Icons.lightbulb_outline,'shortlisted':Icons.compare_arrows},
      onSelected:(v)=>setState(()=>status=v??status))
     else Padding(padding:const EdgeInsets.only(bottom:12),child:Text(
      tt(status=='planned'?'Reserved · use ⋮ › Mark as purchased when you order it.'
       :status=='purchased'?'Purchased · order details are in ⋮ › Order and delivery.':'Excluded'),
      style:theme.textTheme.bodySmall)),
     FormSection(tt('Cost')),
     Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Expanded(flex:2,child:TextField(controller:qty,keyboardType:TextInputType.number,
       decoration:InputDecoration(labelText:tt('Quantity'),border:const OutlineInputBorder()))),
      const SizedBox(width:8),
      Expanded(flex:4,child:TextField(controller:price,
       keyboardType:const TextInputType.numberWithOptions(decimal:true),
       decoration:InputDecoration(labelText:tt('Price'),border:const OutlineInputBorder()))),
      const SizedBox(width:8),
      Expanded(flex:3,child:TextField(controller:currency,maxLength:3,
       textCapitalization:TextCapitalization.characters,
       decoration:InputDecoration(labelText:tt('Currency'),counterText:'',border:const OutlineInputBorder()))),
     ]),
     FormSection(tt('Where to get it')),
     TextField(controller:merchant,maxLength:140,
      decoration:InputDecoration(labelText:tt('Shop'),hintText:tt('Amazon, Noon, Jarir…'),
       prefixIcon:const Icon(Icons.storefront_outlined),border:const OutlineInputBorder())),
     const SizedBox(height:6),
     TextField(controller:url,maxLength:1800,keyboardType:TextInputType.url,
      decoration:InputDecoration(labelText:tt('Product link'),prefixIcon:const Icon(Icons.link),
       border:const OutlineInputBorder())),
     const SizedBox(height:6),
     Text(tt('How much we like it'),style:theme.textTheme.labelLarge),
     Padding(padding:const EdgeInsets.only(bottom:12),
      child:StarRating(value:preference,onChanged:(v)=>setState(()=>preference=v))),
     ChoicePickerField<double>(label:tt('Shop rating'),icon:Icons.star_outline,noneLabel:tt('Not rated'),
      options:{for(final n in [1.0,2.0,3.0,3.5,4.0,4.5,5.0])n:'$n out of 5'},
      selected:rating,onSelected:(v)=>setState(()=>rating=v)),
     Text(tt('Useful when you compare similar gifts.'),style:theme.textTheme.bodySmall),
     FormSection(tt('Notes')),
     TextField(controller:notes,maxLength:2500,minLines:2,maxLines:5,
      decoration:InputDecoration(labelText:tt('Why this one? Ideas, details'),
       alignLabelWithHint:true,border:const OutlineInputBorder())),
     if(error!=null)Padding(padding:const EdgeInsets.only(top:9),
      child:Text(tt(error!),style:TextStyle(color:theme.colorScheme.error))),
   ]));
 }
}

/// R68: ⋮ › Mark as purchased (and later Order and delivery): what was paid,
/// the order number and tracking, and when it arrives. The cost moves from
/// Reserved to Spent.
class OccasionPurchaseEditor extends StatefulWidget{
 const OccasionPurchaseEditor({super.key,required this.plan,required this.item});
 final Map<String,dynamic> plan;
 final Map<String,dynamic> item;
 @override State<OccasionPurchaseEditor> createState()=>_OccasionPurchaseEditorState();
}
class _OccasionPurchaseEditorState extends State<OccasionPurchaseEditor> with FormChangeTracker<OccasionPurchaseEditor>{
 @override String get signature=>[paid.text,orderNumber.text,trackingUrl.text,returnReason.text,arrival,orderStatus].join('|');
 final db=Supabase.instance.client;
 late final TextEditingController paid,orderNumber,trackingUrl,returnReason;
 DateTime? arrival;
 late String orderStatus;
 bool busy=false;
 String? error;
 bool get buying=>widget.item['status']!='purchased';
 @override void initState(){
  super.initState();
  final p=widget.item;
  paid=TextEditingController(text:(p['actual_unit_price']??p['unit_price']??'').toString());
  orderNumber=TextEditingController(text:(p['order_number']??'').toString());
  trackingUrl=TextEditingController(text:(p['tracking_url']??'').toString());
  returnReason=TextEditingController(text:(p['return_reason']??'').toString());
  arrival=DateTime.tryParse(p['estimated_delivery']?.toString()??'');
  final o=(p['order_status']??'not_ordered').toString();
  orderStatus=o=='not_ordered'?'ordered':o;
 }
 @override void dispose(){
  for(final c in [paid,orderNumber,trackingUrl,returnReason]){c.dispose();}
  super.dispose();
 }
 Future<void> save()async{
  if(busy)return;
  final actual=paid.text.trim().isEmpty?null:OccasionBudgetRules.amount(paid.text.replaceAll(',',''));
  if(paid.text.trim().isNotEmpty&&(actual==null||actual>9999999999)){
   setState(()=>error='Enter what you paid, or leave it empty.');return;
  }
  if(!OccasionBudgetRules.isHttpUrl(trackingUrl.text)){
   setState(()=>error='Enter a valid tracking link or leave it empty.');return;
  }
  setState((){busy=true;error=null;});
  try{
   await db.from('occasion_budget_items').update({
    'status':'purchased','actual_unit_price':actual,'order_status':orderStatus,
    'order_number':orderNumber.text.trim(),'tracking_url':trackingUrl.text.trim(),
    'estimated_delivery':arrival==null?null:_day(arrival!),
    'return_reason':returnReason.text.trim(),
   }).eq('id',widget.item['id']).eq('plan_id',widget.plan['id']);
   if(mounted)Navigator.of(context).pop(true);
  }on PostgrestException catch(e){
   if(mounted)setState(()=>error=e.message);
  }catch(_){
   if(mounted)setState(()=>error='Could not save. Try again.');
  }finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context){
  final theme=Theme.of(context);
  final occasionDay=DateTime.tryParse(widget.plan['occasion_on']?.toString()??'');
  final currency=(widget.item['currency']??widget.plan['currency']??'').toString();
  return EditorScaffold(
   title:buying?tt('Mark as purchased'):tt('Order and delivery'),
   isNew:buying,isChanged:()=>changed,isComplete:()=>true,
   listenTo:[paid,orderNumber,trackingUrl,returnReason],saving:busy,onSave:save,
   body:ListView(padding:const EdgeInsets.all(18),children:[
    Text(tt(widget.item['title'].toString()),style:theme.textTheme.titleLarge),
    const SizedBox(height:4),
    if(buying)Text(tt('The cost moves from Reserved to Spent.'),style:theme.textTheme.bodySmall),
    const SizedBox(height:14),
    TextField(controller:paid,keyboardType:const TextInputType.numberWithOptions(decimal:true),
     decoration:InputDecoration(labelText:tt('Paid (each)'),suffixText:currency,
      helperText:tt('Change it if you got a discount.'),border:const OutlineInputBorder())),
    FormSection(tt('Order and delivery')),
    ChoicePickerField<String>(label:tt('Order status'),icon:Icons.local_shipping_outlined,
     options:const {'ordered':'Ordered','shipped':'Shipped','delivered':'Delivered',
      'return_requested':'Return requested','returned':'Returned','cancelled':'Order cancelled'},
     selected:orderStatus,onSelected:(v)=>setState(()=>orderStatus=v??orderStatus)),
    TextField(controller:orderNumber,maxLength:160,
     decoration:InputDecoration(labelText:tt('Order number'),prefixIcon:const Icon(Icons.tag),
      border:const OutlineInputBorder())),
    const SizedBox(height:6),
    TextField(controller:trackingUrl,maxLength:1800,keyboardType:TextInputType.url,
     decoration:InputDecoration(labelText:tt('Tracking link'),prefixIcon:const Icon(Icons.link),
      border:const OutlineInputBorder())),
    const SizedBox(height:6),
    DateField(label:tt('Expected delivery'),value:arrival,
     first:DateTime(DateTime.now().year-2),last:DateTime(DateTime.now().year+10),
     onChanged:(v)=>setState(()=>arrival=v)),
    if(arrival!=null&&occasionDay!=null&&arrival!.isAfter(occasionDay))Padding(
     padding:const EdgeInsets.only(bottom:10),
     child:Text(tt('Arrives after the occasion date.'),style:TextStyle(color:theme.colorScheme.error))),
    if(orderStatus=='return_requested'||orderStatus=='returned')TextField(controller:returnReason,
     maxLength:600,minLines:2,maxLines:4,
     decoration:InputDecoration(labelText:tt('Why return it? Alternatives?'),border:const OutlineInputBorder())),
    if(error!=null)Padding(padding:const EdgeInsets.only(top:9),
     child:Text(tt(error!),style:TextStyle(color:theme.colorScheme.error))),
   ]));
 }
}
