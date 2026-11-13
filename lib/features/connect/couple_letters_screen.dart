import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/current_space_cache.dart';
import 'couple_letter_rules.dart';

class CoupleLettersScreen extends StatefulWidget {
  const CoupleLettersScreen({super.key});
  @override
  State<CoupleLettersScreen> createState()=>_CoupleLettersScreenState();
}

class _CoupleLettersScreenState extends State<CoupleLettersScreen> {
  final db=Supabase.instance.client;
  String? spaceId;
  Stream<List<Map<String,dynamic>>>? letters;
  String view='inbox';
  String? error;
  bool loading=true;

  @override
  void initState(){super.initState();load();}
  Future<void> load() async {
    try{
      final id=await CurrentSpaceCache.instance.get();
      if(!mounted)return;
      setState((){
        spaceId=id;
        loading=false;
        error=null;
        letters=id==null?null:db.from('couple_letters')
          .stream(primaryKey:['id']).eq('space_id',id)
          .order('updated_at',ascending:false);
      });
    }catch(_){
      if(mounted){setState((){
        loading=false;error='Could not load your letters.';
      });}
    }
  }

  Future<void> compose({Map<String,dynamic>? draft}) async {
    if(spaceId==null)return;
    await Navigator.push<void>(context,MaterialPageRoute(
      builder:(_)=>CoupleLetterEditor(
        spaceId:spaceId!,existing:draft,
      ),
    ));
  }

  Future<void> read(Map<String,dynamic> letter) async {
    await Navigator.push<void>(context,MaterialPageRoute(
      builder:(_)=>CoupleLetterDetail(letter:letter),
    ));
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Letters')),
    floatingActionButton:spaceId==null?null:FloatingActionButton.extended(
      icon:const Icon(Icons.edit_outlined),
      label:const Text('Write'),
      onPressed:compose,
    ),
    body:RefreshIndicator(
      onRefresh:load,
      child:ListView(
        padding:const EdgeInsets.fromLTRB(15,10,15,95),
        physics:const AlwaysScrollableScrollPhysics(),
        children:[
          Text('Words worth keeping',
            style:Theme.of(context).textTheme.titleLarge),
          const SizedBox(height:5),
          Text('Send a letter to your partner, save a private draft, '
            'or write back. Sent letters cannot be edited.'),
          const SizedBox(height:14),
          SegmentedButton<String>(
            segments:const [
              ButtonSegment(value:'inbox',label:Text('Received'),
                icon:Icon(Icons.mark_email_unread_outlined)),
              ButtonSegment(value:'sent',label:Text('Sent'),
                icon:Icon(Icons.outbox_outlined)),
              ButtonSegment(value:'drafts',label:Text('Drafts'),
                icon:Icon(Icons.edit_note)),
            ],
            selected:{view},
            onSelectionChanged:(next)=>setState(()=>view=next.first),
          ),
          const SizedBox(height:12),
          if(loading)const Center(child:CircularProgressIndicator())
          else if(error!=null)Text(error!)
          else if(spaceId==null)const Text('Connect your shared space first.')
          else StreamBuilder<List<Map<String,dynamic>>>(
            stream:letters,
            builder:(ctx,snapshot){
              if(snapshot.hasError)return const Text('Unable to load letters.');
              if(!snapshot.hasData)return const LinearProgressIndicator();
              final data=CoupleLetterRules.filter(
                snapshot.data!,view,db.auth.currentUser?.id??'',
              );
              if(data.isEmpty){return Padding(
                padding:const EdgeInsets.symmetric(vertical:35),
                child:Text(
                  view=='inbox'?'No letters received yet.':
                  view=='drafts'?'No private drafts yet.':
                  'No letters sent yet.',
                  textAlign:TextAlign.center,
                ),
              );}
              return Column(children:[
                for(final letter in data)
                  Card(elevation:0,child:ListTile(
                    leading:Icon(letter['status']=='draft'
                      ? Icons.edit_note:Icons.mail_outline),
                    title:Text(letter['title']?.toString()??'Letter',
                      maxLines:2,overflow:TextOverflow.ellipsis),
                    subtitle:Text(CoupleLetterRules.snippet(
                      letter['body']?.toString()??''),
                      maxLines:2,overflow:TextOverflow.ellipsis),
                    trailing:const Icon(Icons.chevron_right),
                    onTap:()=>letter['status']=='draft'
                      ? compose(draft:letter):read(letter),
                  )),
              ]);
            },
          ),
          const SizedBox(height:15),
          Text('Your drafts are visible only to you. Sent letters '
            'are private to your shared space.',
            style:Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

class CoupleLetterEditor extends StatefulWidget {
  const CoupleLetterEditor({super.key,required this.spaceId,this.existing,
    this.parent});
  final String spaceId;
  final Map<String,dynamic>? existing;
  final Map<String,dynamic>? parent;
  @override
  State<CoupleLetterEditor> createState()=>_CoupleLetterEditorState();
}

class _CoupleLetterEditorState extends State<CoupleLetterEditor> {
  late final TextEditingController title;
  late final TextEditingController body;
  bool saving=false;
  String? error;

  @override
  void initState(){
    super.initState();
    title=TextEditingController(text:widget.existing?['title']?.toString()
        ?? (widget.parent==null?'':CoupleLetterRules.replyTitle(
          widget.parent!['title']?.toString()??'Letter')));
    body=TextEditingController(text:widget.existing?['body']?.toString()??'');
  }
  @override
  void dispose(){title.dispose();body.dispose();super.dispose();}

  Future<void> save({required bool send}) async {
    if(saving)return;
    final failure=CoupleLetterRules.validate(
      title.text,body.text,sending:send);
    if(failure!=null){setState(()=>error=failure);return;}
    setState((){saving=true;error=null;});
    try {
      final db=Supabase.instance.client;
      final fields={
        'title':title.text.trim(),
        'body':body.text.trim(),
        'status':send?'sent':'draft',
      };
      final old=widget.existing;
      if(old!=null){
        final updated=await db.from('couple_letters').update(fields)
          .eq('id',old['id'] as String)
          .eq('status','draft').select('id');
        if(updated.isEmpty)throw StateError('Draft changed elsewhere.');
      }else{
        await db.from('couple_letters').insert({
          ...fields,'space_id':widget.spaceId,
          'reply_to':widget.parent?['id'],
        });
      }
      if(mounted)Navigator.pop(context);
    }catch(_){
      if(mounted){setState(()=>error='Unable to save this letter. '
        'Your text is still here. Try again.');}
    }finally{if(mounted)setState(()=>saving=false);}
  }

  Future<void> deleteDraft() async {
    final id=widget.existing?['id'];
    if(id==null)return;
    setState(()=>saving=true);
    try{
      await Supabase.instance.client.from('couple_letters')
        .delete().eq('id',id as String).eq('status','draft');
      if(mounted)Navigator.pop(context);
    }catch(_){
      if(mounted)setState(()=>error='Unable to delete this draft.');
    }finally{if(mounted)setState(()=>saving=false);}
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(widget.parent!=null?'Write a reply':
      widget.existing!=null?'Edit private draft':'Write a letter')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      if(widget.parent!=null)
        Padding(padding:const EdgeInsets.only(bottom:12),
          child:Text('Replying to: ${widget.parent!['title']}')),
      TextField(controller:title,maxLength:160,
        textCapitalization:TextCapitalization.sentences,
        decoration:const InputDecoration(
          labelText:'Title',border:OutlineInputBorder())),
      const SizedBox(height:10),
      TextField(controller:body,maxLength:16000,
        minLines:8,maxLines:20,textCapitalization:TextCapitalization.sentences,
        decoration:const InputDecoration(
          labelText:'Your letter',hintText:'What do you want them to know?',
          alignLabelWithHint:true,border:OutlineInputBorder())),
      if(error!=null)Text(error!,
        style:TextStyle(color:Theme.of(context).colorScheme.error)),
      const SizedBox(height:12),
      FilledButton.icon(
        icon:const Icon(Icons.send_outlined),
        onPressed:saving?null:()=>save(send:true),
        label:Text(saving?'Saving…':'Send to my partner')),
      const SizedBox(height:7),
      OutlinedButton.icon(
        icon:const Icon(Icons.save_outlined),
        onPressed:saving?null:()=>save(send:false),
        label:const Text('Save privately as draft')),
      if(widget.existing!=null)
        TextButton.icon(icon:const Icon(Icons.delete_outline),
          onPressed:saving?null:deleteDraft,
          label:const Text('Delete draft')),
      const SizedBox(height:12),
      Text('Sent letters are permanent, shared with your partner '
        'and cannot be silently changed afterward.',
        style:Theme.of(context).textTheme.bodySmall),
    ]),
  );
}

class CoupleLetterDetail extends StatefulWidget {
  const CoupleLetterDetail({super.key,required this.letter});
  final Map<String,dynamic> letter;
  @override
  State<CoupleLetterDetail> createState()=>_CoupleLetterDetailState();
}
class _CoupleLetterDetailState extends State<CoupleLetterDetail> {
  final db=Supabase.instance.client;
  bool? partnerRead;
  List<Map<String,dynamic>> replies=const [];
  String? error;
  String get me=>db.auth.currentUser?.id??'';
  bool get mine=>widget.letter['author_id']==me;

  @override
  void initState(){super.initState();load();}
  Future<void> load() async {
    final id=widget.letter['id']?.toString();
    if(id==null)return;
    try{
      if(!mine){
        try{
          await db.from('couple_letter_reads').insert({
            'letter_id':id,
          });
        }on PostgrestException catch(e){
          if(e.code!='23505')rethrow;
        }
      }else{
        final receipts=await db.from('couple_letter_reads')
          .select('reader_id').eq('letter_id',id).limit(5);
        if(mounted)setState(()=>partnerRead=receipts.isNotEmpty);
      }
      final children=await db.from('couple_letters')
        .select('id,title,body,status,author_id,space_id,sent_at,reply_to')
        .eq('reply_to',id).eq('status','sent')
        .order('sent_at',ascending:true).limit(100);
      if(mounted){setState(()=>replies=[
        for(final child in children)Map<String,dynamic>.from(child),
      ]);}
    }catch(_){if(mounted)setState(()=>error='Could not load all letter details.');}
  }

  Future<void> reply() async {
    await Navigator.push<void>(context,MaterialPageRoute(
      builder:(_)=>CoupleLetterEditor(
        spaceId:widget.letter['space_id'].toString(),
        parent:widget.letter,
      ),
    ));
    if(mounted)await load();
  }

  @override
  Widget build(BuildContext context){
    final letter=widget.letter;
    return Scaffold(
      appBar:AppBar(title:const Text('Letter')),
      body:RefreshIndicator(
        onRefresh:load,
        child:ListView(padding:const EdgeInsets.all(18),
          physics:const AlwaysScrollableScrollPhysics(),
          children:[
            Text(letter['title']?.toString()??'Letter',
              style:Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height:8),
            Text(mine?'From You':'From your partner',
              style:Theme.of(context).textTheme.labelMedium),
            Text(letter['sent_at']?.toString()??'',
              style:Theme.of(context).textTheme.bodySmall),
            const SizedBox(height:18),
            SelectableText(letter['body']?.toString()??'',
              style:Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height:16),
            if(mine&&partnerRead!=null)Row(children:[
              Icon(partnerRead!?Icons.done_all:Icons.done,size:17),
              const SizedBox(width:6),
              Text(partnerRead!?'Read by your partner':
                'Sent · not marked read yet'),
            ]),
            const SizedBox(height:18),
            FilledButton.icon(
              onPressed:reply,
              icon:const Icon(Icons.reply_outlined),
              label:const Text('Write a reply')),
            if(error!=null)Text(error!),
            if(replies.isNotEmpty)...[
              const Divider(height:30),
              Text('Replies',style:Theme.of(context).textTheme.titleMedium),
              for(final item in replies)
                Card(elevation:0,child:ListTile(
                  title:Text(item['title']?.toString()??'Reply'),
                  subtitle:Text(CoupleLetterRules.snippet(
                    item['body']?.toString()??''),maxLines:2),
                  onTap:()=>Navigator.push<void>(context,
                    MaterialPageRoute(builder:(_)=>
                      CoupleLetterDetail(letter:item))),
                )),
            ],
          ]),
      ),
    );
  }
}
