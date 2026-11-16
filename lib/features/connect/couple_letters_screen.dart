import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/current_space_cache.dart';
import 'couple_letter_rules.dart';
import 'package:onespace/l10n/phrases.dart';

class CoupleLettersScreen extends StatefulWidget {
  const CoupleLettersScreen({super.key});
  @override
  State<CoupleLettersScreen> createState()=>_CoupleLettersScreenState();
}

class _CoupleLettersScreenState extends State<CoupleLettersScreen> {
  final db=Supabase.instance.client;
  String? spaceId;
  // R55: a plain load, not a realtime stream. couple_letters is not in the
  // realtime publication, so the stream failed a little after opening
  // ("Unable to load letters"). Reloads on return and pull-to-refresh.
  List<Map<String,dynamic>>? letters;
  /// R72: letters waiting for their day (no title or words, just the date).
  List<Map<String,dynamic>> sealed=const [];
  String view='inbox';
  String? error;
  bool loading=true;

  @override
  void initState(){super.initState();load();}
  Future<void> load() async {
    try{
      final id=await CurrentSpaceCache.instance.get();
      final rows=id==null?null:List<Map<String,dynamic>>.from(
        await db.from('couple_letters').select().eq('space_id',id)
          .order('updated_at',ascending:false).limit(300));
      var waiting=const <Map<String,dynamic>>[];
      try{
        waiting=List<Map<String,dynamic>>.from(await db.rpc('sealed_letters') as List);
      }catch(_){}
      if(!mounted)return;
      setState((){
        sealed=waiting;
        spaceId=id;
        loading=false;
        error=null;
        letters=rows;
      });
    }catch(_){
      if(mounted){setState((){
        loading=false;error='Could not load your letters.';
      });}
    }
  }

  /// "Received Sun 15 Nov, 2:30 PM" / "Sent …" / "Edited …".
  String _stamp(Map<String,dynamic> letter){
    final draft=letter['status']=='draft';
    final at=DateTime.tryParse((draft?letter['updated_at']:(letter['sent_at']??letter['updated_at']))
      ?.toString()??'')?.toLocal();
    if(at==null)return '';
    final days=OneSpacePhrases.weekdaysShort;
    final months=OneSpacePhrases.monthsShort;
    final h=at.hour%12==0?12:at.hour%12;
    final when='${days[at.weekday-1]} ${at.day} ${months[at.month-1]} ${at.year}, '
      '$h:${at.minute.toString().padLeft(2,'0')} ${at.hour>=12?tt('PM'):tt('AM')}';
    final mine=letter['author_id']==db.auth.currentUser?.id;
    return draft?'Edited $when':mine?'Sent $when':'Received $when';
  }

  Future<void> compose({Map<String,dynamic>? draft}) async {
    if(spaceId==null)return;
    await Navigator.push<void>(context,MaterialPageRoute(
      builder:(_)=>CoupleLetterEditor(
        spaceId:spaceId!,existing:draft,
      ),
    ));
    if(mounted)await load();
  }

  Future<void> read(Map<String,dynamic> letter) async {
    await Navigator.push<void>(context,MaterialPageRoute(
      builder:(_)=>CoupleLetterDetail(letter:letter),
    ));
    if(mounted)await load();
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(tt('Letters'))),
    floatingActionButton:spaceId==null?null:FloatingActionButton.extended(heroTag:'fab-couple-letters',
      icon:const Icon(Icons.edit_outlined),
      label:Text(tt('Write')),
      onPressed:compose,
    ),
    body:RefreshIndicator(
      onRefresh:load,
      child:ListView(
        padding:const EdgeInsetsDirectional.fromSTEB(15,10,15,95),
        physics:const AlwaysScrollableScrollPhysics(),
        children:[
          Text(tt('Words worth keeping'),
            style:Theme.of(context).textTheme.titleLarge),
          const SizedBox(height:5),
          Text(tt('Send a letter to your partner, save a private draft, '
            'or write back. Sent letters cannot be edited.')),
          const SizedBox(height:14),
          SegmentedButton<String>(
            segments:[
              ButtonSegment(value:'inbox',label:Text(tt('Received'),maxLines:1,softWrap:false)),
              ButtonSegment(value:'sent',label:Text(tt('Sent'),maxLines:1)),
              ButtonSegment(value:'drafts',label:Text(tt('Drafts'),maxLines:1)),
            ],
            showSelectedIcon:false,
            selected:{view},
            onSelectionChanged:(next)=>setState(()=>view=next.first),
          ),
          const SizedBox(height:12),
          if(loading)const Center(child:CircularProgressIndicator())
          else if(error!=null)Text(tt(error!))
          else if(spaceId==null)Text(tt('Connect your shared space first.'))
          else Builder(
            builder:(ctx){
              final data=CoupleLetterRules.filter(
                letters??const [],view,db.auth.currentUser?.id??'',
              );
              if(data.isEmpty){return Padding(
                padding:const EdgeInsets.symmetric(vertical:35),
                child:Text(
                  tt(view=='inbox'?'No letters received yet.':
                  view=='drafts'?'No private drafts yet.':
                  'No letters sent yet.'),
                  textAlign:TextAlign.center,
                ),
              );}
              final loc=MaterialLocalizations.of(context);
              return Column(children:[
                if(view=='inbox')for(final s in sealed)Card(elevation:0,
                  color:Theme.of(context).colorScheme.tertiaryContainer,
                  child:ListTile(
                    leading:const Icon(Icons.mark_email_unread_outlined),
                    title:Text(tt('A letter is waiting for you')),
                    subtitle:Text(tt('It opens on ')+loc.formatFullDate(DateTime.parse(s['open_on'].toString()))),
                    trailing:const Icon(Icons.lock_clock_outlined))),
                for(final letter in data)
                  Card(elevation:0,child:ListTile(
                    leading:Icon(letter['status']=='draft'
                      ? Icons.edit_note:Icons.mail_outline),
                    title:Text(tt(letter['title']?.toString()??'Letter'),
                      maxLines:2,overflow:TextOverflow.ellipsis),
                    subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                      Text(tt(CoupleLetterRules.snippet(
                        letter['body']?.toString()??'')),
                        maxLines:2,overflow:TextOverflow.ellipsis),
                      const SizedBox(height:3),
                      Text(tt(_stamp(letter))+(letter['open_on']!=null&&letter['status']=='sent'
                        ?' · '+tt('Opens on ')+loc.formatMediumDate(DateTime.parse(letter['open_on'].toString())):''),
                        style:Theme.of(context).textTheme.labelSmall),
                    ]),
                    isThreeLine:true,
                    trailing:const Icon(Icons.chevron_right),
                    onTap:()=>letter['status']=='draft'
                      ? compose(draft:letter):read(letter),
                  )),
              ]);
            },
          ),
          const SizedBox(height:15),
          Text(tt('Your drafts are visible only to you. Sent letters '
            'are private to your shared space.'),
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
  /// R72: deliver on a chosen day (null = now).
  DateTime? openOn;
  bool saving=false;
  String? error;

  @override
  void initState(){
    super.initState();
    title=TextEditingController(text:widget.existing?['title']?.toString()
        ?? (widget.parent==null?'':CoupleLetterRules.replyTitle(
          widget.parent!['title']?.toString()??'Letter')));
    body=TextEditingController(text:widget.existing?['body']?.toString()??'');
    openOn=DateTime.tryParse(widget.existing?['open_on']?.toString()??'');
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
        'open_on':openOn==null?null:'${openOn!.year.toString().padLeft(4,'0')}-${openOn!.month.toString().padLeft(2,'0')}-${openOn!.day.toString().padLeft(2,'0')}',
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
    appBar:AppBar(title:Text(tt(widget.parent!=null?'Write a reply':
      widget.existing!=null?'Edit private draft':'Write a letter'))),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      if(widget.parent!=null)
        Padding(padding:const EdgeInsets.only(bottom:12),
          child:Text(tt('Replying to: ${widget.parent!['title']}'))),
      TextField(controller:title,maxLength:160,
        textCapitalization:TextCapitalization.sentences,
        decoration:InputDecoration(
          labelText:tt('Title'),border:OutlineInputBorder())),
      const SizedBox(height:10),
      TextField(controller:body,maxLength:16000,
        minLines:8,maxLines:20,textCapitalization:TextCapitalization.sentences,
        decoration:InputDecoration(
          labelText:tt('Your letter'),hintText:tt('What do you want them to know?'),
          alignLabelWithHint:true,border:OutlineInputBorder())),
      // R72: a letter can wait for a special day.
      Card(elevation:0,child:ListTile(
        leading:Icon(openOn==null?Icons.schedule_send_outlined:Icons.lock_clock_outlined),
        title:Text(openOn==null?tt('Open on a special day (optional)')
          :tt('Opens on ')+MaterialLocalizations.of(context).formatFullDate(openOn!)),
        subtitle:Text(tt(openOn==null?'Your partner sees a sealed envelope until that day.'
          :'Until then your partner sees only a sealed envelope with the date.')),
        trailing:openOn==null?const Icon(Icons.chevron_right):IconButton(tooltip:tt('Clear'),
          icon:const Icon(Icons.close),onPressed:()=>setState(()=>openOn=null)),
        onTap:()async{
          final now=DateTime.now();
          final d=await showDatePicker(context:context,initialDate:openOn??now.add(const Duration(days:1)),
            firstDate:now.add(const Duration(days:1)),lastDate:now.add(const Duration(days:3650)));
          if(d!=null)setState(()=>openOn=d);
        })),
      if(error!=null)Text(tt(error!),
        style:TextStyle(color:Theme.of(context).colorScheme.error)),
      const SizedBox(height:12),
      FilledButton.icon(
        icon:Icon(openOn==null?Icons.send_outlined:Icons.schedule_send_outlined),
        onPressed:saving?null:()=>save(send:true),
        label:Text(tt(saving?tt('Saving…'):openOn==null?tt('Send to my partner'):tt('Send for that day')))),
      const SizedBox(height:7),
      OutlinedButton.icon(
        icon:const Icon(Icons.save_outlined),
        onPressed:saving?null:()=>save(send:false),
        label:Text(tt('Save privately as draft'))),
      if(widget.existing!=null)
        TextButton.icon(icon:const Icon(Icons.delete_outline),
          onPressed:saving?null:deleteDraft,
          label:Text(tt('Delete draft'))),
      const SizedBox(height:12),
      Text(tt('Sent letters are permanent, shared with your partner '
        'and cannot be silently changed afterward.'),
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
  Map<String,dynamic>? fresh;
  bool reading=true;
  String? error;
  String get me=>db.auth.currentUser?.id??'';
  bool get mine=>widget.letter['author_id']==me;

  @override
  void initState(){super.initState();load();}
  Future<void> load() async {
    final id=widget.letter['id']?.toString();
    if(id==null)return;
    if(mounted)setState((){
      reading=true;error=null;
    });
    try{
      // Always load the letter by ID with its original RLS. Stream list
      // snapshots may be incomplete or stale after inbox/sent navigation.
      final row=await db.from('couple_letters')
        .select('id,space_id,author_id,title,body,status,sent_at,reply_to')
        .eq('id',id).single();
      if(!mounted)return;
      setState(()=>fresh=Map<String,dynamic>.from(row));
      // The read receipt is independent; a failure must never block a letter.
      if(!mine){
        try{
          await db.from('couple_letter_reads').insert({
            'letter_id':id,'reader_id':me,
          });
        }on PostgrestException catch(e){
          if(e.code!='23505'){
            // A read-receipt problem must not block the letter itself.
          }
        }catch(_){/* Reading remains available even without a receipt. */}
      }else{
        try{
          final receipts=await db.from('couple_letter_reads')
            .select('reader_id').eq('letter_id',id).limit(5);
          if(mounted)setState(()=>partnerRead=receipts.isNotEmpty);
        }catch(_){if(mounted)setState(()=>partnerRead=null);}
      }
      try{
        final children=await db.from('couple_letters')
          .select('id,title,body,status,author_id,space_id,sent_at,reply_to')
          .eq('reply_to',id).eq('status','sent')
          .order('sent_at',ascending:true).limit(100);
        if(mounted)setState(()=>replies=[
          for(final child in children)Map<String,dynamic>.from(child)]);
      }catch(_){
        // Replies may be inaccessible without preventing the main letter read.
      }
    }on PostgrestException catch(e){
      if(mounted)setState(()=>error='Could not open this letter: '+e.message);
    }catch(_){
      if(mounted)setState(()=>error='Could not open this letter. Refresh to retry.');
    }finally{
      if(mounted)setState(()=>reading=false);
    }
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
    final letter=fresh??widget.letter;
    return Scaffold(
      appBar:AppBar(title:Text(tt('Letter'))),
      body:RefreshIndicator(
        onRefresh:load,
        child:ListView(padding:const EdgeInsets.all(18),
          physics:const AlwaysScrollableScrollPhysics(),
          children:[
            if(reading)const LinearProgressIndicator(),
            if(error!=null)...[
              Card(child:Padding(padding:const EdgeInsets.all(12),
                child:Text(tt(error!),style:TextStyle(
                  color:Theme.of(context).colorScheme.error)))),
              TextButton.icon(onPressed:load,
                icon:const Icon(Icons.refresh),
                label:Text(tt('Retry opening letter'))),
            ],
            Text(tt(letter['title']?.toString()??'Letter'),
              style:Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height:8),
            Text(tt(mine?tt('From You'):tt('From your partner')),
              style:Theme.of(context).textTheme.labelMedium),
            Text(tt(() {
              final sent=DateTime.tryParse(letter['sent_at']?.toString()??'');
              return sent==null?'Date unavailable':
                MaterialLocalizations.of(context).formatMediumDate(sent.toLocal())+
                ' · '+MaterialLocalizations.of(context).formatTimeOfDay(
                  TimeOfDay.fromDateTime(sent.toLocal()));
            }()),style:Theme.of(context).textTheme.bodySmall),
            const SizedBox(height:18),
            SelectableText(letter['body']?.toString()??'',
              style:Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height:16),
            if(mine&&partnerRead!=null)Row(children:[
              Icon(partnerRead!?Icons.done_all:Icons.done,size:17),
              const SizedBox(width:6),
              Text(tt(partnerRead!?'Read by your partner':
                'Sent · not marked read yet')),
            ]),
            const SizedBox(height:18),
            FilledButton.icon(
              onPressed:reply,
              icon:const Icon(Icons.reply_outlined),
              label:Text(tt('Write a reply'))),
            if(replies.isNotEmpty)...[
              const Divider(height:30),
              Text(tt('Replies'),style:Theme.of(context).textTheme.titleMedium),
              for(final item in replies)
                Card(elevation:0,child:ListTile(
                  title:Text(tt(item['title']?.toString()??'Reply')),
                  subtitle:Text(tt(CoupleLetterRules.snippet(
                    item['body']?.toString()??'')),maxLines:2),
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
