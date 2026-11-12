import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../../l10n/onespace_strings.dart';
import '../sharing/private_share_button.dart';

/// Each person may make one personal check-in per local calendar date. The
/// partner can view shared entries, but only the author can edit their entry.
class CheckinsScreen extends StatefulWidget {
  const CheckinsScreen({super.key});
  @override
  State<CheckinsScreen> createState()=>_CheckinsScreenState();
}

class _CheckinsScreenState extends State<CheckinsScreen> {
  final _client=Supabase.instance.client;
  String? _space;
  Stream<List<Map<String,dynamic>>>? _stream;
  String? _error;
  bool _loading=true;
  String _filter='all';

  @override
  void initState(){super.initState();_load();}

  Future<void> _load() async {
    if(mounted)setState(() { _loading=_space==null;_error=null;});
    try{
      final id=await CurrentSpaceCache.instance.get();
      if(!mounted)return;
      setState(() {
        _space=id;
        _stream=id==null?null:_client.from('daily_checkins')
          .stream(primaryKey:['id']).eq('space_id',id)
          .order('checkin_date',ascending:false);
        _loading=false;
      });
    }catch(_){
      if(mounted)setState((){_error=tr(context,'loadFailed');_loading=false;});
    }
  }

  Future<void> _edit([Map<String,dynamic>? record]) async {
    final id=_space;
    if(id==null)return;
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder:(_)=>CheckinEditor(spaceId:id,existing:record)));
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(tr(context,'checkinTitle'))),
    body:RefreshIndicator(onRefresh:_load,child:ListView(
      padding:const EdgeInsets.all(20),children:[
      Text(tr(context,'checkinSubtitle')),
      const SizedBox(height:12),
      if(_error!=null)Text(_error!,style:const TextStyle(color:Colors.red)),
      if(_loading)
        const Padding(padding:EdgeInsets.all(30),
          child:Center(child:CircularProgressIndicator()))
      else if(_space==null)Text(tr(context,'noSpace'))
      else ...[
        FilledButton.icon(
          onPressed:()=>_edit(),
          icon:const Icon(Icons.favorite_outline),
          label:Text(tr(context,'dailyCheckin'))),
        const SizedBox(height:12),
        Wrap(spacing:8,children:['all','shared','private'].map((v)=>ChoiceChip(
          label:Text(tr(context,v)),selected:_filter==v,
          onSelected:(_)=>setState(()=>_filter=v))).toList()),
        StreamBuilder<List<Map<String,dynamic>>>(
          stream:_stream,builder:(context,snapshot){
          if(snapshot.hasError)return Text(tr(context,'loadFailed'));
          if(!snapshot.hasData)
            return const Center(child:CircularProgressIndicator());
          final entries=snapshot.data!.where((x)=>
            _filter=='all'||x['visibility']==_filter).toList();
          if(entries.isEmpty)return Padding(
            padding:const EdgeInsets.all(36),
            child:Text(tr(context,'noCheckins'),textAlign:TextAlign.center));
          final me=_client.auth.currentUser?.id ?? '';
          return Column(children:entries.map((entry){
            final owner=entry['created_by'] as String? ?? '';
            final own=owner==me;
            final private=entry['visibility']=='private';
            final mood=(entry['mood'] as num).toInt();
            const moodIcons=[
              Icons.sentiment_very_dissatisfied_outlined,
              Icons.sentiment_dissatisfied_outlined,
              Icons.sentiment_neutral_outlined,
              Icons.sentiment_satisfied_outlined,
              Icons.sentiment_very_satisfied_outlined,
            ];
            return Card(elevation:0,child:Column(children:[
              ListTile(
                leading:Icon(moodIcons[mood.clamp(1,5)-1]),
                title:Text(entry['checkin_date'] as String? ?? ''),
                subtitle:Text([
                  tr(context,entry['visibility'] as String? ?? 'shared'),
                  if(own)tr(context,'me') else tr(context,'partner'),
                  if((entry['message'] as String? ?? '').isNotEmpty)
                    entry['message'] as String,
                  if((entry['gratitude'] as String? ?? '').isNotEmpty)
                    '${tr(context,'gratitude')}: ${entry['gratitude']}',
                ].join(' • '),maxLines:4,overflow:TextOverflow.ellipsis),
                trailing:own?const Icon(Icons.edit_outlined):
                  const Icon(Icons.visibility_outlined),
                onTap:()=>_edit(entry)),
              if(own && private) Align(
                alignment:AlignmentDirectional.centerEnd,
                child:PrivateShareButton(
                  objectType:'checkin',objectId:entry['id'] as String)),
            ]));
          }).toList());
        }),
      ],
    ])),
  );
}

class CheckinEditor extends StatefulWidget {
  const CheckinEditor({super.key,required this.spaceId,this.existing});
  final String spaceId;
  final Map<String,dynamic>? existing;
  @override
  State<CheckinEditor> createState()=>_CheckinEditorState();
}
class _CheckinEditorState extends State<CheckinEditor> {
  final _client=Supabase.instance.client;
  late final TextEditingController _message,_gratitude;
  late DateTime _date;
  late int _mood;
  late String _visibility;
  bool _saving=false;
  String? _error;

  bool get _canEdit=>widget.existing==null ||
      widget.existing!['created_by']==_client.auth.currentUser?.id;
  @override
  void initState(){
    super.initState();
    _message=TextEditingController(text:widget.existing?['message'] as String? ?? '');
    _gratitude=TextEditingController(text:widget.existing?['gratitude'] as String? ?? '');
    _date=DateTime.tryParse(widget.existing?['checkin_date'] as String? ?? '')??DateTime.now();
    _mood=(widget.existing?['mood'] as num?)?.toInt()??3;
    _visibility=widget.existing?['visibility'] as String? ?? 'shared';
  }
  @override
  void dispose(){_message.dispose();_gratitude.dispose();super.dispose();}

  Future<void> _save() async {
    if(!_canEdit || _saving)return;
    if(_message.text.length>2000 || _gratitude.text.length>500){
      setState(()=>_error=tr(context,'checkinValidation'));return;
    }
    setState((){_saving=true;_error=null;});
    final date='${_date.year}-${_date.month.toString().padLeft(2,'0')}-'
      '${_date.day.toString().padLeft(2,'0')}';
    try{
      final fields=<String,dynamic>{
        'mood':_mood,'message':_message.text.trim(),
        'gratitude':_gratitude.text.trim(),
      };
      if(widget.existing==null) {
        // Check uniqueness explicitly for a friendly message.
        final previous=await _client.from('daily_checkins').select('id')
          .eq('created_by',_client.auth.currentUser!.id)
          .eq('checkin_date',date).limit(1);
        if(previous.isNotEmpty){
          if(mounted)setState(()=>_error=tr(context,'checkinAlreadyExists'));
          return;
        }
        await _client.from('daily_checkins').insert({
          ...fields,'space_id':widget.spaceId,
          'created_by':_client.auth.currentUser!.id,
          'checkin_date':date,'visibility':_visibility,
        });
      }else{
        final rows=await _client.from('daily_checkins')
          .update(fields).eq('id',widget.existing!['id'] as String)
          .select('id');
        if(rows.isEmpty) throw StateError('No editable checkin');
      }
      if(mounted)Navigator.of(context).pop();
    }on PostgrestException catch(e){
      if(mounted)setState(()=>_error=e.message);
    }catch(_){
      if(mounted)setState(()=>_error=tr(context,'saveFailed'));
    }finally{
      if(mounted)setState(()=>_saving=false);
    }
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(tr(context,'dailyCheckin'))),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
      if(!_canEdit)Text(tr(context,'viewOnly')),
      OutlinedButton.icon(
        onPressed:!_canEdit || _saving || widget.existing!=null
          ? null : ()async{
          final now=DateTime.now();
          final selected=await showDatePicker(context:context,
            initialDate:_date,firstDate:DateTime(2020),lastDate:now);
          if(mounted && selected!=null)setState(()=>_date=selected);
        },
        icon:const Icon(Icons.event),
        label:Text('${_date.year}-${_date.month}-${_date.day}')),
      const SizedBox(height:18),
      Text(tr(context,'howAreYouFeeling'),
        style:Theme.of(context).textTheme.titleMedium),
      const SizedBox(height:8),
      Wrap(spacing:6,children:List.generate(5,(i){
        return ChoiceChip(
          key:Key('mood-${i+1}'),
          label:Text('${i+1}'),
          selected:_mood==i+1,
          onSelected:!_canEdit || _saving?null:
            (_)=>setState(()=>_mood=i+1));
      })),
      const SizedBox(height:14),
      TextField(controller:_message,readOnly:!_canEdit,
        maxLength:2000,minLines:2,maxLines:5,
        decoration:InputDecoration(
          labelText:tr(context,'checkinMessage'),
          border:const OutlineInputBorder())),
      const SizedBox(height:12),
      TextField(controller:_gratitude,readOnly:!_canEdit,maxLength:500,
        minLines:1,maxLines:3,
        decoration:InputDecoration(
          labelText:tr(context,'gratitude'),
          border:const OutlineInputBorder())),
      const SizedBox(height:12),
      Text(tr(context,'visibility')),
      Wrap(spacing:8,children:['shared','private'].map((v)=>ChoiceChip(
        selected:_visibility==v,label:Text(tr(context,v)),
        onSelected:widget.existing!=null || _saving?null:
          (_)=>setState(()=>_visibility=v))).toList()),
      Text(tr(context,'privacyFixed'),
        style:Theme.of(context).textTheme.bodySmall),
      const SizedBox(height:16),
      if(_error!=null)Text(_error!,style:const TextStyle(color:Colors.red)),
      if(_canEdit)FilledButton(
        onPressed:_saving?null:_save,child:Text(tr(context,'save'))),
    ])),
  );
}
