import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/current_space_cache.dart';

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
      if(mounted)await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>
        ActivityScreen(id:row['id'] as String)));
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
      if(s.data!.isEmpty)return const Padding(padding:EdgeInsets.all(25),
        child:Text('Your shared workspace begins with an idea.'));
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

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key,required this.id});
  final String id;
  @override State<ActivityScreen> createState()=>_ActivityScreenState();
}
class _ActivityScreenState extends State<ActivityScreen> {
  final db=Supabase.instance.client;
  final comment=TextEditingController();
  late final Stream<List<Map<String,dynamic>>> activity,components,comments,revisions,reactions;
  String? replyTo,issue;
  @override void initState(){
    super.initState();
    final id=widget.id;
    activity=db.from('activities').stream(primaryKey:['id']).eq('id',id);
    components=db.from('activity_components').stream(primaryKey:['id'])
      .eq('activity_id',id).order('created_at');
    comments=db.from('activity_comments').stream(primaryKey:['id'])
      .eq('activity_id',id).order('created_at');
    revisions=db.from('activity_revisions').stream(primaryKey:['id'])
      .eq('activity_id',id).order('changed_at',ascending:false);
    reactions=db.from('activity_component_reactions').stream(primaryKey:['component_id','user_id'])
      .eq('activity_id',id);
  }
  @override void dispose(){comment.dispose();super.dispose();}
  String when(dynamic v){final d=DateTime.tryParse('$v')?.toLocal();
    if(d==null)return '';return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';}
  Future<void> execute(Future<void> Function() work) async {
    try{await work();if(mounted)setState(()=>issue=null);}
    catch(e){if(mounted)setState(()=>issue='$e');}
  }
  Future<String?> ask(String heading,{String initial='',int max=4000}) async {
    final input=TextEditingController(text:initial);
    try{return await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(heading),content:TextField(controller:input,maxLength:max,minLines:1,maxLines:6),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,input.text.trim()),child:const Text('Save'))]));
    }finally{input.dispose();}
  }
  Future<void> edit(Map<String,dynamic> a) async {
    final title=await ask('Edit title',initial:a['title'] as String? ?? '',max:120);
    if(title==null||title.isEmpty||!mounted)return;
    final body=await ask('Edit details',initial:a['body'] as String? ?? '',max:12000);
    if(body==null)return;
    await execute(() async {
      final changed=await db.from('activities').update({'title':title,'body':body})
        .eq('id',widget.id).eq('updated_at',a['updated_at'] as String).select('id');
      if(changed.isEmpty)throw StateError('Your partner updated this activity; reopen and review before editing.');
    });
  }
  Future<void> addComponent(String kind) async {
    final title=await ask('Add $kind',max:180);
    if(title==null||title.isEmpty||!mounted)return;
    final details=await ask('Details / value (optional)');
    if(details==null)return;
    await execute(() async { await db.from('activity_components').insert({
      'activity_id':widget.id,'kind':kind,'label':title,
      'payload':{'value':details,'status':'open'},
    }); });
  }
  Future<void> send() async {
    if(comment.text.trim().isEmpty)return;
    final body=comment.text.trim();
    await execute(() async {
      await db.from('activity_comments').insert({'activity_id':widget.id,
        'body':body,'reply_to':replyTo});
      comment.clear();if(mounted)setState(()=>replyTo=null);
    });
  }
  Widget section(String title,Widget child)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const SizedBox(height:20),Text(title,style:Theme.of(context).textTheme.titleLarge),
    const SizedBox(height:8),child,
  ]);
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Shared activity')),
    body:StreamBuilder<List<Map<String,dynamic>>>(stream:activity,builder:(ctx,s){
      if(s.hasError)return const Center(child:Text('Unable to load this activity'));
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      if(s.data!.isEmpty)return const Center(child:Text('Activity unavailable'));
      final a=s.data!.first;
      return ListView(padding:const EdgeInsets.all(18),children:[
        Text(a['title'] as String? ?? '',style:Theme.of(context).textTheme.headlineSmall),
        Text('Created ${when(a['created_at'])} · ${a['visibility']}'),
        const SizedBox(height:10),
        Wrap(spacing:8,children:[
          Chip(label:Text('Priority: ${a['priority']}')),
          PopupMenuButton<String>(tooltip:'Update status',
            onSelected:(v)=>execute(() async { await db.from('activities').update({'stage':v}).eq('id',widget.id); }),
            itemBuilder:(_)=>['exploring','comparing','decided','purchased','registered','completed','on_hold','cancelled']
                .map((x)=>PopupMenuItem(value:x,child:Text(x))).toList(),
            child:Chip(label:Text('Status: ${a['stage']} ▾'))),
        ]),
        if(issue!=null)Text(issue!,style:const TextStyle(color:Colors.red)),
        Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[const Expanded(child:Text('Details',style:TextStyle(fontWeight:FontWeight.bold))),
            IconButton(onPressed:()=>edit(a),icon:const Icon(Icons.edit_outlined))]),
          Text(a['body'] as String? ?? ''),
        ]))),
        section('Add what you need',Wrap(spacing:7,runSpacing:5,children:[
          for(final k in ['link','note','option','step','date','price','spec','reminder','tag','mention'])
            ActionChip(label:Text('+ $k'),onPressed:()=>addComponent(k)),
        ])),
        section('Research, steps & details',StreamBuilder<List<Map<String,dynamic>>>(
          stream:components,builder:(ctx,s){
            if(!s.hasData)return const LinearProgressIndicator();
            if(s.data!.isEmpty)return const Text('Add a link, option, note, step, specification or other component.');
            return StreamBuilder<List<Map<String,dynamic>>>(stream:reactions,builder:(ctx,votes){
              final all=votes.data??[];
              return Column(children:[for(final item in s.data!)
                Card(child:ListTile(
                  title:Text('[${item['kind']}] ${item['label']}'),
                  subtitle:Text('${(item['payload'] as Map?)?['value']??''}\n${when(item['created_at'])}'),
                  isThreeLine:true,
                  trailing:Wrap(mainAxisSize:MainAxisSize.min,children:[
                    IconButton(tooltip:'Like',icon:Icon(Icons.thumb_up_outlined,
                      color:all.any((r)=>r['component_id']==item['id']&&r['user_id']==db.auth.currentUser?.id&&r['opinion']==1)
                        ?Theme.of(context).colorScheme.primary:null),
                      onPressed:()=>execute(() async {await db.from('activity_component_reactions').upsert({
                        'activity_id':widget.id,'component_id':item['id'],
                        'user_id':db.auth.currentUser!.id,'opinion':1},onConflict:'component_id,user_id');}),
                    IconButton(tooltip:'Dislike',icon:const Icon(Icons.thumb_down_outlined),
                      onPressed:()=>execute(() async {await db.from('activity_component_reactions').upsert({
                        'activity_id':widget.id,'component_id':item['id'],
                        'user_id':db.auth.currentUser!.id,'opinion':-1},onConflict:'component_id,user_id');}),
                  ]),
                )),
              ]);
            });
          })),
        section('Conversation',StreamBuilder<List<Map<String,dynamic>>>(
          stream:comments,builder:(ctx,s){
            if(!s.hasData)return const LinearProgressIndicator();
            return Column(children:[for(final c in s.data!)
              Card(child:ListTile(
                title:Text(c['author_id']==db.auth.currentUser?.id?'You':'Partner'),
                subtitle:Text('${c['body']}\n${when(c['created_at'])}'),
                trailing:IconButton(icon:const Icon(Icons.reply_outlined),
                  onPressed:()=>setState(()=>replyTo=c['id'] as String)),
              )),
            ]);
          })),
        if(replyTo!=null)TextButton(onPressed:()=>setState(()=>replyTo=null),
          child:const Text('Replying to comment · Cancel reply')),
        Row(children:[Expanded(child:TextField(controller:comment,maxLines:3,minLines:1,
          maxLength:5000,decoration:const InputDecoration(hintText:'Write a comment…'))),
          IconButton(icon:const Icon(Icons.send),onPressed:send)]),
        section('Edit & status history',StreamBuilder<List<Map<String,dynamic>>>(
          stream:revisions,builder:(ctx,s)=>ExpansionTile(title:const Text('View audit trail'),
            children:[ListTile(title:const Text('Original'),subtitle:Text(
              '${a['original_title']}\n${a['original_body']}\n${when(a['created_at'])}')),
              for(final rev in s.data??<Map<String,dynamic>>[])
                ListTile(title:Text('Changed ${when(rev['changed_at'])}'),
                  subtitle:Text('${rev['old_title']} → ${rev['new_title']}\n${rev['old_body']} → ${rev['new_body']}\n${rev['old_stage']} → ${rev['new_stage']}')),
            ]))),
      ]);
    }),
  );
}
