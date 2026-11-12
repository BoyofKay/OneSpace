import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/current_space_cache.dart';
import 'activity_detail_screen.dart';
export 'activity_detail_screen.dart' show ActivityScreen;

class CoordinateScreen extends StatefulWidget {
  const CoordinateScreen({super.key});
  @override
  State<CoordinateScreen> createState() => _CoordinateScreenState();
}
class _CoordinateScreenState extends State<CoordinateScreen> {
  final db=Supabase.instance.client;
  String? space;
  Stream<List<Map<String,dynamic>>>? items;
  String? error;
  @override
  void initState(){super.initState();load();}
  Future<void> load() async {
    try {
      final id=await CurrentSpaceCache.instance.get();
      if(!mounted)return;
      setState((){
        space=id;
        items=id==null?null:db.from('activities').stream(primaryKey:['id'])
          .eq('space_id',id).order('updated_at',ascending:false);
      });
    }catch(e){if(mounted)setState(()=>error='Unable to load workspace: $e');}
  }
  Future<void> create() async {
    final title=TextEditingController(),body=TextEditingController();
    String priority='normal',visibility='shared';
    try {
      final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(
        builder:(ctx,update)=>AlertDialog(title:const Text('New activity'),
          content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
            TextField(controller:title,maxLength:120,decoration:const InputDecoration(labelText:'Title')),
            TextField(controller:body,maxLength:12000,maxLines:4,decoration:const InputDecoration(labelText:'Details (optional)')),
            DropdownButtonFormField<String>(initialValue:priority,
              items:['low','normal','high','urgent'].map((x)=>DropdownMenuItem(value:x,child:Text('Priority: $x'))).toList(),
              onChanged:(v)=>update(()=>priority=v??priority)),
            DropdownButtonFormField<String>(initialValue:visibility,
              items:['shared','private'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),
              onChanged:(v)=>update(()=>visibility=v??visibility)),
          ])),actions:[
            TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
            FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Create')),
          ])));
      if(ok!=true||space==null||title.text.trim().isEmpty)return;
      final row=await db.from('activities').insert({'space_id':space,'title':title.text.trim(),
        'body':body.text.trim(),'priority':priority,'visibility':visibility})
        .select('id').single();
      if(mounted) { await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>
        ActivityScreen(id:row['id'] as String))); }
    }catch(e){if(mounted)setState(()=>error='Unable to create activity: $e');}
    finally{title.dispose();body.dispose();}
  }
  @override
  Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(18),children:[
    Text('Coordinate',style:Theme.of(context).textTheme.headlineMedium),
    const Text('A shared space to explore, compare, discuss, decide and remember.'),
    const SizedBox(height:16),
    if(error!=null)Text(error!,style:const TextStyle(color:Colors.red)),
    FilledButton.icon(onPressed:space==null?null:create,icon:const Icon(Icons.add),
      label:const Text('Create activity')),
    if(space==null)TextButton(onPressed:load,child:const Text('Load shared space')),
    if(items!=null)StreamBuilder<List<Map<String,dynamic>>>(stream:items,builder:(ctx,s){
      if(s.hasError)return const Text('Could not load activities. Pull to retry.');
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      if(s.data!.isEmpty) { return const Padding(padding:EdgeInsets.all(25),
        child:Text('Your shared workspace begins with an idea.')); }
      return Column(children:[for(final a in s.data!)
        Card(child:ListTile(title:Text(a['title'] as String? ?? ''),
          subtitle:Text('${a['stage']} · ${a['priority']} priority\n${a['body']??''}',
            maxLines:3,overflow:TextOverflow.ellipsis),
          trailing:const Icon(Icons.chevron_right),
          onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(
            builder:(_)=>ActivityScreen(id:a['id'] as String))))),
      ]);
    }),
  ]);
}
