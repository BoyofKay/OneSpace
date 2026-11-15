
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/current_space_cache.dart';
import '../calendar/calendar_rules.dart';
import 'activity_component_editor.dart';
import 'activity_countdown_rules.dart';
import 'activity_decision_rules.dart';
import 'activity_comparison_matrix.dart';
import 'activity_comparison_sheet.dart';
import '../occasions/occasion_option_linker.dart';
import 'activity_conversation_references.dart';
import 'activity_image_service.dart';
import 'activity_image_preview.dart';
import 'activity_contact.dart';
import 'activity_contact_view.dart';
import 'activity_voice_player.dart';
import 'activity_inline_voice_composer.dart';
import 'activity_voice_recorder_sheet.dart';
import 'activity_voice_service.dart';
import 'activity_message_identity.dart';

/// Purpose-first Activity detail. Primary content gets the screen; metadata,
/// actions and reactions are deliberately tucked into compact controls.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.id, this.focusConversation = false});
  final String id;
  /// R48: opened from a chat push - scroll to the conversation once loaded.
  final bool focusConversation;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final db = Supabase.instance.client;
  final composer = TextEditingController();
  final composerFocus = FocusNode();
  late final Stream<List<Map<String, dynamic>>> activity;
  late final Stream<List<Map<String, dynamic>>> components;
  late final Stream<List<Map<String, dynamic>>> comments;
  final GlobalKey _conversationKey = GlobalKey();
  bool _conversationFocused = false;
  late final Stream<List<Map<String, dynamic>>> revisions;
  late final Stream<List<Map<String, dynamic>>> reactions;
  late final Stream<List<Map<String, dynamic>>> decisions;
  String? replyingTo;
  String? replyPreview;
  String? onComponent;
  String? onComponentTitle;
  String? issue;
  bool sending = false;
  bool voiceMode=false;
  bool showRemovedComponents=false;
  String? mentionSuggestion;
  int mentionOffset = -1;
  String? conversationSpaceId;

  String get me => db.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    final id = widget.id;
    activity = db.from('activities')
        .stream(primaryKey: ['id']).eq('id', id);
    components = db.from('activity_components')
        .stream(primaryKey: ['id']).eq('activity_id', id).order('created_at');
    comments = db.from('activity_comments')
        .stream(primaryKey: ['id']).eq('activity_id', id).order('created_at');
    reactions = db.from('activity_component_reactions')
        .stream(primaryKey: ['component_id', 'user_id']).eq('activity_id', id);
    decisions = db.from('activity_decisions')
        .stream(primaryKey: ['id']).eq('activity_id', id)
        .order('created_at', ascending: false);
    revisions = db.from('activity_revisions')
        .stream(primaryKey: ['id']).eq('activity_id', id)
        .order('changed_at', ascending: false);
  }

  @override
  void dispose() {
    composer.dispose();
    composerFocus.dispose();
    super.dispose();
  }

  String when(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '${date.day}/${date.month}/${date.year} $h:$m';
  }

  String author(String? id, String? spaceId) {
    if (id == me) return 'You';
    final names = CurrentSpaceCache.instance.memberNamesFor(spaceId ?? '');
    return names?[id] ?? 'Partner';
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => issue = null);
    } catch (e) {
      if (mounted) {
        setState(() => issue = 'Could not save your change. $e');
      }
    }
  }

  Future<String?> prompt(String label, {String initial = '', int max = 12000}) async {
    final text = TextEditingController(text: initial);
    try {
      return await showDialog<String>(context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(label),
            content: TextField(controller: text, maxLength: max,
              minLines: 2, maxLines: 8, autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder())),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, text.text.trim()),
                child: const Text('Save')),
            ],
          ));
    } finally {
      text.dispose();
    }
  }

  Future<void> editActivity(Map<String, dynamic> item) async {
    final title = TextEditingController(text: item['title']?.toString() ?? '');
    final body = TextEditingController(text: item['body']?.toString() ?? '');
    try {
      final changed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Edit Activity'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, maxLength: 120,
                decoration: const InputDecoration(labelText: 'Title')),
              TextField(controller: body, maxLength: 12000,
                minLines: 4, maxLines: 8,
                decoration: const InputDecoration(labelText: 'Details')),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
            FilledButton(onPressed: () {
              if (title.text.trim().isNotEmpty) {
                Navigator.pop(ctx, true);
              }
            }, child: const Text('Save')),
          ],
        ),
      );
      if (changed != true || !mounted) return;
      await run(() async {
        final rows = await db.from('activities').update({
            'title': title.text.trim(), 'body': body.text.trim(),
          }).eq('id', widget.id)
          .eq('updated_at', item['updated_at'] as String)
          .select('id');
        if (rows.isEmpty) {
          throw StateError('Your partner edited this Activity. Review their changes first.');
        }
      });
    } finally {
      title.dispose();
      body.dispose();
    }
  }

  Future<void> editBody(Map<String, dynamic> item) async {
    final body = await prompt('Edit Activity details',
      initial: item['body']?.toString() ?? '');
    if (body == null || !mounted) return;
    await changeField(item, 'body', body);
  }

  /// Selecting an option and recording an outcome update stage together on the
  /// server, preserving the author's reason and prior outcomes.
  Future<void> recordDecision(String action, {String? componentId}) async {
    if (action == 'chosen' && componentId == null) {
      await chooseDecisionOption();
      return;
    }
    final reason = await prompt(
      action == 'chosen' ? 'Why choose this option?' :
      action == 'purchased' ? 'Purchase details (optional)' :
      action == 'registered' ? 'Registration details (optional)' :
      action == 'delivered' ? 'Delivery details (optional)' :
      'Reason or update (optional)',
      max: 2000,
    );
    if (reason == null || !mounted) return;
    await run(() async {
      await db.rpc('record_activity_decision', params: {
        'p_activity_id': widget.id,
        'p_action': action,
        'p_component_id': componentId,
        'p_reason': reason,
      });
    });
  }

  Future<void> chooseDecisionOption() async {
    try {
      final results = await db.from('activity_components')
          .select('id,label')
          .eq('activity_id', widget.id)
          .eq('kind', 'option')
          .isFilter('archived_at', null)
          .order('created_at');
      if (!mounted) return;
      if (results.isEmpty) {
        setState(() => issue = 'Add an Option first, then choose it.');
        return;
      }
      final chosen = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Which option did we choose?',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final item in results)
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(item['label']?.toString() ?? ''),
                onTap: () => Navigator.pop(ctx, item['id'] as String),
              ),
          ],
        )),
      );
      if (chosen == null || !mounted) return;
      await recordDecision('chosen', componentId: chosen);
    } catch (e) {
      if (mounted) setState(() => issue = 'Unable to load options. $e');
    }
  }

  Widget decisionSection(String? spaceId) =>
      StreamBuilder<List<Map<String, dynamic>>>(
    stream: decisions,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Text('Outcome history could not be loaded.');
      }
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final history = snapshot.data!;
      final latest = ActivityDecisionRules.latest(history);
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('Decision & outcome',
                style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                tooltip: 'Choose an option',
                icon: const Icon(Icons.fact_check_outlined),
                onPressed: chooseDecisionOption,
              ),
              PopupMenuButton<String>(
                tooltip: 'Record an outcome',
                icon: const Icon(Icons.more_horiz),
                onSelected: (action) => recordDecision(action),
                itemBuilder: (_) => [
                  for (final action in ActivityDecisionRules.actions
                      .where((v) => v != 'chosen'))
                    PopupMenuItem(
                      value: action,
                      child: Text(ActivityDecisionRules.titleFor(action)),
                    ),
                ],
              ),
            ]),
            if (latest == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No decision yet. Choose an option or record an outcome.'),
              )
            else
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ActivityDecisionRules.titleFor(
                          latest['action']?.toString() ?? ''),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (latest['component_id'] != null)
                        StreamBuilder<List<Map<String, dynamic>>>(
                          stream: components,
                          builder: (context, optionsSnapshot) {
                            final selected = optionsSnapshot.data
                                ?.where((item) =>
                                    item['id'] == latest['component_id'])
                                .firstOrNull;
                            return Text(
                              selected?['label']?.toString() ?? 'Selected option',
                              style: Theme.of(context).textTheme.bodyLarge,
                            );
                          },
                        ),
                      if ((latest['reason']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(latest['reason'].toString()),
                      ],
                      const SizedBox(height: 4),
                      Text('${author(latest['created_by']?.toString(),spaceId)}'
                          ' · ${when(latest['created_at'])}',
                        style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
              ),
            if (history.length > 1)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Previous outcomes (${history.length - 1})',
                    style: Theme.of(context).textTheme.labelLarge),
                children: [
                  for (final entry in history.where(
                      (event) => event['id'] != latest?['id']))
                    ListTile(
                      dense: true,
                      title: Text(ActivityDecisionRules.titleFor(
                          entry['action']?.toString() ?? '')),
                      subtitle: Text([
                        if ((entry['reason']?.toString() ?? '').isNotEmpty)
                          entry['reason'].toString(),
                        '${author(entry['created_by']?.toString(),spaceId)}'
                            ' · ${when(entry['created_at'])}',
                      ].join('\n')),
                    ),
                ],
              ),
          ],
        ),
      );
    },
  );

  Future<void> changeField(Map<String,dynamic> item,
      String field, Object? value) async {
    await run(() async {
      final rows = await db.from('activities')
        .update({field: value}).eq('id', widget.id)
        .eq('updated_at', item['updated_at'] as String).select('id');
      if (rows.isEmpty) throw StateError('Activity changed on another device. Please review.');
    });
  }

  Future<void> pickDueDate(Map<String,dynamic> item) async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(item['due_on']?.toString() ?? '') ?? now;
    final selected = await showDatePicker(context: context,
      firstDate: DateTime(2000), lastDate: DateTime(2100),
      initialDate: initial);
    if (selected != null) {
      await changeField(item, 'due_on', CalendarRules.sqlDate(selected));
    }
  }

  Future<void> chooseAdd({String? under, String? underTitle}) async {
    final choices = <(String,IconData,String)>[
      ('option', Icons.compare_arrows, 'Compare an option'),
      ('link', Icons.link, 'Link'),
      ('image', Icons.image_outlined, 'Photo / screenshot'),
      ('voice', Icons.mic_none_outlined, 'Voice note'),
      ('note', Icons.subject, 'Note'),
      ('step', Icons.check_circle_outline, 'Step'),
      ('price', Icons.payments_outlined, 'Price'),
      ('spec', Icons.tune, 'Specification'),
      ('date', Icons.event, 'Date'),
      ('countdown', Icons.hourglass_bottom_outlined, 'Countdown'),
      ('reminder', Icons.notifications_outlined, 'Remind us'),
      ('location', Icons.place_outlined, 'Map location'),
      ('contact', Icons.contact_phone_outlined, 'Contact information'),
      ('tag', Icons.sell_outlined, 'Tag'),
    ];
    final chosen = await showModalBottomSheet<String>(
      context: context, showDragHandle: true,
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(underTitle == null ? 'Add to this Activity'
                : 'Add detail to $underTitle',
              style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(spacing: 7, runSpacing: 7,
              children: [
                for (final choice in choices)
                  ActionChip(
                    avatar: Icon(choice.$2, size: 17),
                    label: Text(choice.$3),
                    onPressed: () => Navigator.pop(ctx, choice.$1),
                  ),
              ]),
          ],
        )),
      )),
    );
    if (chosen == null || !mounted) return;
    if (chosen == 'image') {
      await run(() async {
        await ActivityImageService(db).addPhoto(
          activityId: widget.id,
          parentComponentId: under,
        );
      });
    } else if (chosen == 'voice') {
      await recordVoice(
        destination: VoiceDestination.component,
        parentComponentId: under,
        contextLabel: underTitle == null ? null : 'Attached to $underTitle',
      );
    } else {
      await openEditor(chosen, parent: under);
    }
  }

  Future<void> recordVoice({
    required VoiceDestination destination,
    String? parentComponentId,
    String? contextLabel,
  }) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: false,
      builder: (_) => ActivityVoiceRecorderSheet(
        activityId: widget.id,
        destination: destination,
        parentComponentId: parentComponentId,
        replyToCommentId: destination == VoiceDestination.comment
            ? replyingTo : null,
        relatedComponentId: destination == VoiceDestination.comment
            ? onComponent : null,
        contextLabel: contextLabel ??
            (destination == VoiceDestination.comment
                ? replyingTo != null
                    ? 'Replying to: ${replyPreview ?? 'message'}'
                    : onComponentTitle != null
                        ? 'About: $onComponentTitle'
                        : null
                : null),
      ),
    );
    if (sent == true && mounted &&
        destination == VoiceDestination.comment) {
      setState(() {
        replyingTo = null;
        replyPreview = null;
        onComponent = null;
        onComponentTitle = null;
      });
    }
  }

  Future<void> openEditor(String kind, {
    String? parent,
    Map<String,dynamic>? existing,
  }) async {
    final draft = await showModalBottomSheet<Map<String,dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ComponentEditorSheet(kind: kind, existing: existing,
        spaceId:conversationSpaceId),
    );
    if (draft == null || !mounted) return;
    await run(() async {
      if (existing == null) {
        await db.from('activity_components').insert({
          'activity_id': widget.id,
          'parent_component_id': parent,
          'kind': kind,
          ...draft,
        });
      } else {
        final rows = await db.from('activity_components').update(draft)
            .eq('id', existing['id'] as String)
            .eq('updated_at', existing['updated_at'] as String)
            .select('id');
        if (rows.isEmpty) {
          throw StateError('This component was edited by your partner. Please reopen it.');
        }
      }
    });
  }

  Future<void> toggleStep(Map<String,dynamic> item) async {
    final payload = Map<String,dynamic>.from(item['payload'] as Map? ?? const {});
    payload['status'] = payload['status'] == 'done' ? 'open' : 'done';
    await run(() async {
      final result = await db.from('activity_components')
        .update({'payload': payload}).eq('id', item['id'] as String)
        .eq('updated_at', item['updated_at'] as String).select('id');
      if (result.isEmpty) throw StateError('Step was edited on another device.');
    });
  }

  Future<void> toggleReminder(Map<String,dynamic> item) async {
    final payload=Map<String,dynamic>.from(
      item['payload'] as Map? ?? const {});
    payload['status']=payload['status']=='done'?'open':'done';
    await run(() async {
      final rows=await db.from('activity_components')
        .update({'payload':payload}).eq('id',item['id'] as String)
        .eq('updated_at',item['updated_at'] as String).select('id');
      if(rows.isEmpty) {
        throw StateError('This reminder changed on another device.');
      }
    });
  }

  Future<void> opinion(Map<String,dynamic> item, int vote) async {
    await run(() async {
      final componentId=item['id'].toString();
      final existing=await db.from('activity_component_reactions')
        .select('component_id').eq('component_id',componentId)
        .eq('user_id',me).limit(1);
      if(existing.isEmpty){
        try{
          await db.from('activity_component_reactions').insert({
            'activity_id':widget.id,
            'component_id':componentId,
            'user_id':me,
            'opinion':vote,
          });
        }on PostgrestException catch(e){
          if(e.code!='23505')rethrow;
          await db.from('activity_component_reactions')
            .update({'opinion':vote})
            .eq('component_id',componentId).eq('user_id',me);
        }
      }else{
        await db.from('activity_component_reactions')
          .update({'opinion':vote})
          .eq('component_id',componentId).eq('user_id',me);
      }
    });
  }

  Future<void> openExternal(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      if (mounted) setState(() => issue = 'That website address is invalid.');
      return;
    }
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        await Clipboard.setData(ClipboardData(text: url));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot open website; link copied.')));
      }
    } catch (_) {
      if (mounted) setState(() => issue = 'Could not open the link.');
    }
  }

  Future<void> openMap(String place) async {
    if (place.trim().isEmpty) return;
    final url = Uri.https('www.google.com', '/maps/search/', {
      'api': '1', 'query': place.trim(),
    });
    await openExternal(url.toString());
  }

  /// Launches the OS dialer or mail composer. Never places calls or sends
  /// email itself. On unsupported devices, copy the verified contact value.
  Future<void> openContactAction(Uri uri) async {
    if (uri.scheme != 'tel' && uri.scheme != 'mailto') return;
    try {
      final didOpen = await launchUrl(
        uri, mode: LaunchMode.externalApplication,
      );
      if (!didOpen) {
        await Clipboard.setData(ClipboardData(text: uri.path));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
            'No compatible app found. Contact detail copied.',
          )),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => issue = 'Could not open this contact detail.');
    }
  }

  /// Suggest only when @ starts a message token, never in email addresses.
  void _onComposerChanged(String text) {
    final caret=composer.selection.isValid
      ?composer.selection.baseOffset:text.length;
    final before=text.substring(0,caret.clamp(0,text.length));
    final hit=RegExp(r'(^|\s)@([^\s@]*)$').firstMatch(before);
    final names=CurrentSpaceCache.instance.memberNamesFor(conversationSpaceId??'');
    final partner=names?.entries.where((entry)=>entry.key!=me)
      .map((entry)=>entry.value).firstOrNull;
    final partial=hit?.group(2)??'';
    final show=hit!=null&&partner!=null&&
      partner.toLowerCase().startsWith(partial.toLowerCase());
    final position=show?caret-partial.length-1:-1;
    if(mentionSuggestion!=(show?partner:null)||mentionOffset!=position) {
      setState((){
        mentionSuggestion=show?partner:null;
        mentionOffset=position;
      });
    }
  }

  void _acceptMention() {
    final name=mentionSuggestion;
    if(name==null||mentionOffset<0)return;
    final caret=composer.selection.isValid
      ?composer.selection.baseOffset:composer.text.length;
    final end=caret.clamp(mentionOffset,composer.text.length);
    final insertion='@'+name+' ';
    composer.value=TextEditingValue(
      text:composer.text.replaceRange(mentionOffset,end,insertion),
      selection:TextSelection.collapsed(offset:mentionOffset+insertion.length));
    setState((){
      mentionSuggestion=null;
      mentionOffset=-1;
    });
    composerFocus.requestFocus();
  }

  void focusOnComponent(Map<String,dynamic> item) {
    setState((){
      onComponent=item['id'] as String;
      onComponentTitle=item['label']?.toString();
      replyingTo=null;
      replyPreview=null;
    });
    composerFocus.requestFocus();
  }

  void startReply(Map<String, dynamic> message) {
    setState(() {
      replyingTo = message['id']?.toString();
      replyPreview = ActivityConversationReferences.excerpt(message['body']);
      onComponent = null;
      onComponentTitle = null;
    });
    composerFocus.requestFocus();
  }

  Future<void> _setComponentRemoved(Map<String,dynamic> item,bool remove) async{
    final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>
      AlertDialog(
        title:Text(remove?'Remove this component?':'Restore this component?'),
        content:Text(remove
          ?'It will disappear from the active Activity. Its contents and '
           'change history are preserved.'
          :'Return this component to the Activity.'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),
            child:const Text('Keep')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),
            child:Text(remove?'Remove':'Restore')),
        ],
      ));
    if(confirmed!=true||!mounted)return;
    await run(() async{
      final rows=await db.from('activity_components').update({
        'archived_at':remove?DateTime.now().toUtc().toIso8601String():null,
      }).eq('id',item['id'].toString())
       .eq('updated_at',item['updated_at'].toString())
       .select('id');
      if(rows.isEmpty)throw StateError('Component changed. Please retry.');
    });
  }

  Future<void> _setActivityArchived(Map<String,dynamic> item,bool archive) async{
    final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>
      AlertDialog(
        title:Text(archive?'Archive this Activity?':'Restore this Activity?'),
        content:Text(archive
          ?'Hide this Activity from active lists while keeping its '
           'comments, evidence, decisions, and audit trail.'
          :'Restore this Activity without losing history.'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),
            child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),
            child:Text(archive?'Archive':'Restore')),
        ],
      ));
    if(confirmed!=true||!mounted)return;
    await run(()async{
      final rows=await db.from('activities').update({
        'archived_at':archive?DateTime.now().toUtc().toIso8601String():null,
      }).eq('id',widget.id)
       .eq('updated_at',item['updated_at'].toString())
       .select('id');
      if(rows.isEmpty)throw StateError('Activity changed. Please retry.');
    });
  }

  Future<void> _finishActivity(Map<String,dynamic> item) async{
    final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>
      AlertDialog(
        title:const Text('Mark Activity completed?'),
        content:const Text('Every comment, component, decision and edit '
          'remains available. You can reopen it later.'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),
            child:const Text('Not yet')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),
            child:const Text('Mark completed')),
        ],
      ));
    if(confirmed==true&&mounted)await changeField(item,'stage','completed');
  }

  Future<void> componentMenu(
    Map<String, dynamic> item,
    List<Map<String, dynamic>> votes,
  ) async {
    final kind = item['kind']?.toString() ?? '';
    final id = item['id'] as String;
    final title = item['label']?.toString();
    final payload = item['payload'] as Map? ?? const {};
    final current = votes.where(
      (vote) => vote['component_id'] == id && vote['user_id'] == me,
    ).firstOrNull?['opinion'] as num? ?? 0;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.72,
          ),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (kind == 'link')
                ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: const Text('Open website'),
                  onTap: () => Navigator.pop(ctx, 'open-link')),
              if (kind == 'location')
                ListTile(
                  leading: const Icon(Icons.map_outlined),
                  title: const Text('Open in Maps'),
                  onTap: () => Navigator.pop(ctx, 'open-location')),
              if (kind == 'reminder')
                ListTile(
                  leading: Icon(payload['status']=='done'
                    ? Icons.restart_alt : Icons.done_all),
                  title: Text(payload['status']=='done'
                    ? 'Reopen shared reminder'
                    : 'Mark reminder handled for both of us'),
                  onTap: () => Navigator.pop(ctx,'reminder'),
                ),
              if (kind == 'step')
                ListTile(
                  leading: Icon(payload['status'] == 'done'
                      ? Icons.restart_alt : Icons.check_circle_outline),
                  title: Text(payload['status'] == 'done'
                      ? 'Reopen step' : 'Mark step completed'),
                  onTap: () => Navigator.pop(ctx, 'step')),
              if (kind == 'option') ...[
                ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: const Text('Choose this option'),
                  onTap: () => Navigator.pop(ctx, 'choose')),
                ListTile(
                  leading: const Icon(Icons.tune_outlined),
                  title: const Text('Add a specification'),
                  onTap: () => Navigator.pop(ctx, 'add-spec')),
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: const Text('Add or update a price observation'),
                  onTap: () => Navigator.pop(ctx, 'add-price')),
                ListTile(
                  leading: const Icon(Icons.note_add_outlined),
                  title: const Text('Add a note or response'),
                  onTap: () => Navigator.pop(ctx, 'add-note')),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('Attach another source link'),
                  onTap: () => Navigator.pop(ctx, 'add-link')),
                ListTile(
                  leading: const Icon(Icons.mic_none_outlined),
                  title: const Text('Attach voice note'),
                  onTap: () => Navigator.pop(ctx, 'add-voice')),
                ListTile(
                  leading: const Icon(Icons.contact_phone_outlined),
                  title: const Text('Attach contact information'),
                  onTap: () => Navigator.pop(ctx, 'add-contact')),
              ],
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: const Text('Discuss this item'),
                onTap: () => Navigator.pop(ctx, 'comment')),
              if (kind != 'step') ...[
                ListTile(
                  leading: const Icon(Icons.thumb_up_outlined),
                  title: const Text('Like'),
                  trailing: current == 1 ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(ctx, 'like')),
                ListTile(
                  leading: const Icon(Icons.thumb_down_outlined),
                  title: const Text('Dislike'),
                  trailing: current == -1 ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(ctx, 'dislike')),
              ],
              ListTile(
                leading: const Icon(Icons.add_outlined),
                title: const Text('Attach another component'),
                onTap: () => Navigator.pop(ctx, 'child')),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () => Navigator.pop(ctx, 'edit')),
              ListTile(
                leading:const Icon(Icons.history),
                title:const Text('Edit & removal history'),
                onTap:()=>Navigator.pop(ctx,'history')),
              ListTile(
                leading:Icon(item['archived_at']==null
                  ?Icons.remove_circle_outline:Icons.restore_outlined),
                title:Text(item['archived_at']==null?
                  'Remove from Activity':'Restore component'),
                onTap:()=>Navigator.pop(ctx,'toggle-removed')),
            ]),
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'open-link':
        await openExternal(payload['value']?.toString() ?? '');
      case 'open-location':
        await openMap(payload['value']?.toString() ?? '');
      case 'step':
        await toggleStep(item);
      case 'reminder':
        await toggleReminder(item);
      case 'choose':
        await recordDecision('chosen', componentId: id);
      case 'comment':
        focusOnComponent(item);
      case 'like':
        await opinion(item, current == 1 ? 0 : 1);
      case 'dislike':
        await opinion(item, current == -1 ? 0 : -1);
      case 'add-spec':
        await openEditor('spec', parent: id);
      case 'add-price':
        await openEditor('price', parent: id);
      case 'add-note':
        await openEditor('note', parent: id);
      case 'add-link':
        await openEditor('link', parent: id);
      case 'add-contact':
        await openEditor('contact', parent: id);
      case 'add-voice':
        await recordVoice(
          destination: VoiceDestination.component,
          parentComponentId: id,
          contextLabel: title == null ? null : 'Attached to $title',
        );
      case 'child':
        await chooseAdd(under: id, underTitle: title);
      case 'edit':
        await openEditor(kind, existing: item);
      case 'history':
        await showComponentHistory(item);
      case 'toggle-removed':
        await _setComponentRemoved(item,item['archived_at']==null);
    }
  }

  Future<void> showComponentHistory(Map<String,dynamic> item) async {
    await run(() async {
      final changes = await db.from('activity_component_revisions').select()
          .eq('component_id', item['id'] as String)
          .order('changed_at', ascending: false);
      if (!mounted) return;
      await showDialog<void>(context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Component history'),
          content: SizedBox(width: 420,
            child: ListView(shrinkWrap: true, children: [
              if (changes.isEmpty) const Text('No edits yet.'),
              for (final change in changes)
                ListTile(
                  title:Text((change['change_kind']?.toString()??'Edited')+
                    ' · '+when(change['changed_at'])),
                  subtitle: Text(
                    '${change['old_label']} → ${change['new_label']}\n'
                    '${change['old_payload']} → ${change['new_payload']}'),
                ),
            ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
          ],
        ));
    });
  }

  Future<void> compare(
    List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> votes,
  ) async {
    final matrix = ActivityComparisonMatrix.build(
      items, reactions: votes, currentUserId: me,
    );
    if (matrix.columns.length < 2) {
      if (mounted) {
        setState(() => issue = 'Add two or more options before comparing.');
      }
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ActivityComparisonSheet(
        matrix: matrix,
        onChoose: (optionId) {
          recordDecision('chosen', componentId: optionId);
        },
        onOpenSource: (url) {
          openExternal(url);
        },
      ),
    );
  }

  Future<void> send() async {
    if (sending || composer.text.trim().isEmpty) return;
    setState(() => sending = true);
    final message = composer.text.trim();
    try {
      await db.from('activity_comments').insert({
        'activity_id': widget.id,
        'body': message,
        'reply_to': replyingTo,
        'component_id': onComponent,
      });
      composer.clear();
      if (mounted) {
        setState(() {
          replyingTo = null;
          replyPreview = null;
          onComponent = null;
          onComponentTitle = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => issue = 'Message was not sent. Please retry.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  IconData typeIcon(String kind) {
    switch (kind) {
      case 'option': return Icons.compare_arrows;
      case 'link': return Icons.link;
      case 'image': return Icons.image_outlined;
      case 'voice': return Icons.mic_none_outlined;
      case 'note': return Icons.subject;
      case 'step': return Icons.check_circle_outline;
      case 'price': return Icons.payments_outlined;
      case 'spec': return Icons.tune;
      case 'date': return Icons.event_outlined;
      case 'countdown': return Icons.hourglass_bottom_outlined;
      case 'location': return Icons.place_outlined;
      case 'contact': return Icons.contact_phone_outlined;
      case 'tag': return Icons.sell_outlined;
      case 'reminder': return Icons.notifications_outlined;
      case 'mention': return Icons.alternate_email;
      default: return Icons.extension_outlined;
    }
  }

  String valueFor(Map<String,dynamic> item) {
    final kind = item['kind'] as String? ?? 'note';
    final payload = item['payload'] as Map? ?? const {};
    final value = payload['value']?.toString() ?? '';
    if(kind=='countdown'){
      return ActivityCountdownRules.summary(value,
        repeatYearly:payload['repeat_yearly']==true,now:DateTime.now());
    }
    if (kind == 'price') return '${payload['currency'] ?? ''} $value';
    if (kind == 'contact' || kind == 'voice') return '';
    if (kind == 'option') {
      final price = payload['price']?.toString() ?? '';
      final currency = payload['currency']?.toString() ?? '';
      final specs = payload['specs']?.toString() ?? '';
      return [
        if (price.isNotEmpty) '$currency $price',
        if (value.isNotEmpty) value,
        if (specs.isNotEmpty) specs,
      ].join('\n');
    }
    return value;
  }

  Widget componentCard(Map<String,dynamic> item,
      List<Map<String,dynamic>> allVotes) {
    final kind = item['kind'] as String? ?? 'note';
    final payload = item['payload'] as Map? ?? const {};
    final value = valueFor(item);
    final note = payload['note']?.toString() ?? '';
    final done = payload['status'] == 'done';
    final removed=item['archived_at']!=null;
    final votes = allVotes.where((v) => v['component_id'] == item['id']);
    final likes = votes.where((v) => v['opinion'] == 1).length;
    final dislikes = votes.where((v) => v['opinion'] == -1).length;
    final url = kind == 'link' ? payload['value']?.toString() ?? '' :
        kind == 'option' ? payload['url']?.toString() ?? '' : '';
    final location = kind == 'location' ? payload['value']?.toString() ?? '' : '';
    final isNested = item['parent_component_id'] != null;
    final contact = kind == 'contact'
        ? ActivityContact.fromPayload(Map<String, dynamic>.from(payload))
        : null;

    Future<void> primaryAction() async {
      if (kind == 'link' && url.isNotEmpty) {
        await openExternal(url);
      } else if (kind == 'location') {
        await openMap(location);
      } else if (kind == 'step') {
        await toggleStep(item);
      } else if (kind == 'reminder') {
        await componentMenu(item, allVotes);
      } else {
        await componentMenu(item, allVotes);
      }
    }

    return Padding(
      padding: EdgeInsetsDirectional.only(start: isNested ? 16 : 0, bottom: 5),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          // Voice content is controlled by its player, not by a card tap.
          onTap: kind == 'voice'||removed ? null : primaryAction,
          onLongPress: () => componentMenu(item, allVotes),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 10, 7, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (kind == 'step')
                SizedBox(width: 30, height: 30,
                  child: Checkbox(value: done,
                    onChanged: (_) => toggleStep(item)))
              else if (kind == 'reminder')
                SizedBox(width: 30, height: 30,
                  child: Checkbox(value: done,
                    onChanged: (_) => toggleReminder(item)))
              else
                Padding(padding: const EdgeInsets.only(top: 4, right: 8),
                  child: Icon(typeIcon(kind), size: 19,
                    color: Theme.of(context).colorScheme.secondary)),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['label']?.toString() ?? '',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color:removed?Theme.of(context).colorScheme.outline:null,
                      decoration: done ? TextDecoration.lineThrough : null,
                    )),
                  if(removed)const Text('Removed · kept in history'),
                  if (value.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    SelectableText(value,
                      style: TextStyle(
                        fontSize: kind == 'price' ? 17 : 14,
                        height: 1.35,
                        fontWeight: kind == 'price' ? FontWeight.w600 : null,
                      )),
                  ],
                  if(kind=='countdown')...[
                    const SizedBox(height:5),
                    Text('Milestone: '+(payload['value']?.toString()??''),
                      style:Theme.of(context).textTheme.labelSmall),
                    if(payload['repeat_yearly']==true)
                      Text('Repeats every year',
                        style:Theme.of(context).textTheme.bodySmall),
                  ],
                  if (contact != null) ...[
                    const SizedBox(height: 5),
                    ActivityContactView(
                      contact: contact,
                      onPhone: openContactAction,
                      onEmail: openContactAction,
                      onMap: openMap,
                    ),
                  ],
                  if (kind == 'voice' &&
                      (payload['voice_path']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ActivityVoicePlayer(
                      objectPath: payload['voice_path'].toString(),
                      seconds: (payload['voice_seconds'] as num?)?.toInt() ?? 0,
                    ),
                  ],
                  if (kind == 'image' &&
                      (payload['object_path']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 7),
                    ActivityImagePreview(
                      objectPath: payload['object_path'].toString(),
                      label: item['label']?.toString() ?? 'Activity photo',
                    ),
                  ],
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(note, style: Theme.of(context).textTheme.bodySmall),
                  ],
                  if (url.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => openExternal(url),
                      icon: const Icon(Icons.open_in_new, size: 15),
                      label: const Text('Open link'),
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 0)),
                    ),
                  if (location.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => openMap(location),
                      icon: const Icon(Icons.map_outlined, size: 15),
                      label: const Text('Open in Maps'),
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 0)),
                    ),
                  if(kind=='option'&&!removed)
                   TextButton.icon(
                    onPressed:()=>showModalBottomSheet<void>(
                     context:context,isScrollControlled:true,showDragHandle:true,
                     builder:(_)=>SendOptionToOccasionSheet(
                      activityId:widget.id,option:item)),
                    icon:const Icon(Icons.card_giftcard_outlined,size:16),
                    label:const Text('Send to occasion plan'),
                   ),
                  if (kind == 'reminder')
                    Text('Notification not active',
                        style: Theme.of(context).textTheme.labelSmall),
                  if (likes > 0 || dislikes > 0)
                    Padding(padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${likes > 0 ? '👍 $likes ' : ''}'
                        '${dislikes > 0 ? '👎 $dislikes' : ''}',
                        style: Theme.of(context).textTheme.labelSmall,
                      )),
                ],
              )),
              SizedBox(width: 33, height: 33,
                child: IconButton(
                  tooltip: 'More options for ${item['label']}',
                  padding: EdgeInsets.zero,
                  iconSize: 19,
                  onPressed: () => componentMenu(item, allVotes),
                  icon: const Icon(Icons.more_horiz),
                )),
            ]),
          ),
        ),
      ),
    );
  }


  List<Widget> attachedTree(
    Map<String,dynamic> root,
    List<Map<String,dynamic>> items,
    List<Map<String,dynamic>> votes, {
    int depth = 0,
  }) {
    if (depth >= 8) return [componentCard(root, votes)];
    return [
      componentCard(root, votes),
      for (final child in items.where(
          (item) => item['parent_component_id'] == root['id']))
        ...attachedTree(child, items, votes, depth: depth + 1),
    ];
  }

  Widget componentSection() => StreamBuilder<List<Map<String,dynamic>>>(
    stream: components,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('Could not load attached items.');
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final items = snapshot.data!;
      final visible=showRemovedComponents?items:
      items.where((i)=>i['archived_at']==null).toList();
    final roots=visible.where((i)=>i['parent_component_id']==null).toList();
      final options = roots.where((i) => i['kind'] == 'option').toList();
      final steps = roots.where((i) => i['kind'] == 'step').toList();
      final references = roots.where(
          (i) => i['kind'] != 'option' && i['kind'] != 'step').toList();
      return StreamBuilder<List<Map<String,dynamic>>>(
        stream: reactions,
        builder: (context, r) {
          final votes = r.data ?? [];
          return Column(crossAxisAlignment: CrossAxisAlignment.start,children:[
            if(items.any((i)=>i['archived_at']!=null))
              Align(alignment:AlignmentDirectional.centerEnd,
                child:TextButton.icon(
                  onPressed:()=>setState(() =>
                    showRemovedComponents=!showRemovedComponents),
                  icon:Icon(showRemovedComponents?
                    Icons.visibility_off_outlined:Icons.history_toggle_off),
                  label:Text(showRemovedComponents?
                    'Hide removed items':'View removed items'))),
            if (items.isEmpty) ...[
              Row(children: [
                Expanded(child: Text('Add to this Activity',
                  style: Theme.of(context).textTheme.titleMedium)),
                IconButton(
                  tooltip: 'Add a component',
                  onPressed: chooseAdd,
                  icon: const Icon(Icons.add_circle_outline)),
              ]),
              const Padding(padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Add a product, link, note, step or map location.')),
            ],
            if (options.isNotEmpty) ...[
              Row(children: [
                Expanded(child: Text('Options · ${options.length}',
                  style: Theme.of(context).textTheme.titleMedium)),
                if (options.length >= 2)
                  IconButton(tooltip: 'Compare options',
                    onPressed: () => compare(items, votes),
                    icon: const Icon(Icons.compare_arrows)),
                IconButton(tooltip: 'Add option',
                  onPressed: () => openEditor('option'),
                  icon: const Icon(Icons.add)),
              ]),
              for (final option in options) ...attachedTree(option,visible,votes),
              const SizedBox(height: 10),
            ],
            if (steps.isNotEmpty) ...[
              Row(children: [
                Expanded(child: Text('Next steps · ${steps.where(
                    (i) => (i['payload'] as Map?)?['status'] != 'done').length} open',
                  style: Theme.of(context).textTheme.titleMedium)),
                IconButton(tooltip: 'Add step',
                  onPressed: () => openEditor('step'),
                  icon: const Icon(Icons.add)),
              ]),
              for (final step in steps) ...attachedTree(step,visible,votes),
              const SizedBox(height: 10),
            ],
            if (references.isNotEmpty) ...[
              Row(children: [
                Expanded(child: Text('Notes & references',
                  style: Theme.of(context).textTheme.titleMedium)),
                IconButton(tooltip: 'Add reference',
                  onPressed: chooseAdd,
                  icon: const Icon(Icons.add)),
              ]),
              for (final reference in references)
                ...attachedTree(reference,visible,votes),
            ],
          ]);
        },
      );
    },
  );

  Widget conversation(String? spaceId) =>
      StreamBuilder<List<Map<String, dynamic>>>(
    stream: comments,
    builder: (context, messagesSnapshot) {
      if (messagesSnapshot.hasError) {
        return const Text('Could not load the conversation.');
      }
      if (!messagesSnapshot.hasData) return const LinearProgressIndicator();
      final messages = messagesSnapshot.data!;
      if (widget.focusConversation && !_conversationFocused) {
        _conversationFocused = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final target = _conversationKey.currentContext;
          if (target != null && target.mounted) {
            Scrollable.ensureVisible(target,
              duration: const Duration(milliseconds: 350),
              alignment: 1.0);
          }
        });
      }
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: components,
        builder: (context, componentSnapshot) {
          final componentItems = componentSnapshot.data ?? const [];
          return Column(key: _conversationKey,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 18),
            Text('Conversation', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            if (messages.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('Start talking here. Every message stays with this Activity.')),
            for (final message in messages)
              commentBubble(message, spaceId, messages, componentItems),
          ]);
        },
      );
    },
  );

  Widget commentBubble(
    Map<String, dynamic> msg,
    String? spaceId,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> componentItems,
  ) {
    final owner = msg['author_id']?.toString();
    final mine = owner == me;
    final memberNames = CurrentSpaceCache.instance.memberNamesFor(spaceId ?? '');
    final avatarText = ActivityMessageIdentity.initials(
      authorId: owner,
      currentUserId: me,
      memberNames: memberNames,
    );
    final isVoice = (msg['voice_path']?.toString() ?? '').isNotEmpty;
    final replyQuote = ActivityConversationReferences.quotedMessage(
      msg, messages,
    );
    final target = ActivityConversationReferences.componentName(
      msg, componentItems,
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        // Let tapping a voice bubble control playback; long-press still replies.
        onTap: isVoice ? null : () => startReply(msg),
        onLongPress: () async {
          final action = await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => SafeArea(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.reply_outlined),
                  title: const Text('Reply'),
                  onTap: () => Navigator.pop(ctx, 'reply')),
                if (!isVoice)
                  ListTile(
                    leading: const Icon(Icons.copy_outlined),
                    title: const Text('Copy message'),
                    onTap: () => Navigator.pop(ctx, 'copy')),
              ],
            )),
          );
          if (!mounted) return;
          if (action == 'copy') {
            await Clipboard.setData(
              ClipboardData(text: msg['body']?.toString() ?? ''),
            );
          } else if (action == 'reply') {
            startReply(msg);
          }
        },
        child: Container(
          constraints: const BoxConstraints(maxWidth: 350),
          margin: const EdgeInsets.only(bottom: 7),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: mine
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    child: Text(avatarText,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary)),
                  ),
                  Text(when(msg['created_at']),
                    style: Theme.of(context).textTheme.labelSmall),
                ]),
              if (replyQuote != null || target != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        width: 2,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (target != null)
                        Text('About: $target',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall),
                      if (replyQuote != null)
                        Text(replyQuote,
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 4),
              if ((msg['voice_path']?.toString() ?? '').isNotEmpty)
                ActivityVoicePlayer(
                  objectPath: msg['voice_path'].toString(),
                  seconds: (msg['voice_seconds'] as num?)?.toInt() ?? 0,
                )
              else
                Text(msg['body']?.toString() ?? '',
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }

  Widget bottomComposer()=>SafeArea(
    top:false,
    child:Container(
      padding:const EdgeInsets.fromLTRB(9,5,9,8),
      decoration:BoxDecoration(
        color:Theme.of(context).colorScheme.surface,
        border:Border(top:BorderSide(
          color:Theme.of(context).colorScheme.outlineVariant)),
      ),
      child:Column(mainAxisSize:MainAxisSize.min,children:[
        if(replyingTo!=null||onComponent!=null)Row(children:[
          Expanded(child:Text(
            replyingTo!=null?'Replying to: '+(replyPreview??'message'):
              'Discussing: '+(onComponentTitle??'attached item'),
            maxLines:1,overflow:TextOverflow.ellipsis,
            style:Theme.of(context).textTheme.labelSmall)),
          IconButton(icon:const Icon(Icons.close,size:16),
            tooltip:'Cancel reply',onPressed:()=>setState((){
              replyingTo=null;replyPreview=null;
              onComponent=null;onComponentTitle=null;
            })),
        ]),
        if(mentionSuggestion!=null)Align(
          alignment:Alignment.centerLeft,
          child:Card(elevation:2,child:InkWell(
            onTap:_acceptMention,
            child:Padding(padding:const EdgeInsets.all(10),
              child:Row(mainAxisSize:MainAxisSize.min,children:[
                const Icon(Icons.alternate_email,size:18),
                const SizedBox(width:8),
                Text(mentionSuggestion!),
              ]),
            ),
          )),
        ),
        if(voiceMode)ActivityInlineVoiceComposer(
          activityId:widget.id,
          replyToId:replyingTo,
          componentId:onComponent,
          onFinished:(){
            setState((){
              voiceMode=false;
              replyingTo=null;replyPreview=null;
              onComponent=null;onComponentTitle=null;
            });
          },
          onCancel:()=>setState(()=>voiceMode=false),
        )
        else Row(children:[
          IconButton(
            tooltip:'Record voice message',
            onPressed:sending?null:(){
              FocusScope.of(context).unfocus();
              setState(()=>voiceMode=true);
            },
            icon:const Icon(Icons.mic_none_outlined)),
          Expanded(child:TextField(
            controller:composer,focusNode:composerFocus,
            onChanged:_onComposerChanged,
            minLines:1,maxLines:4,maxLength:5000,
            textCapitalization:TextCapitalization.sentences,
            textInputAction:TextInputAction.newline,
            decoration:const InputDecoration(
              hintText:'Message your partner…',
              isDense:true,counterText:'',
              contentPadding:EdgeInsets.symmetric(horizontal:12,vertical:10),
              border:OutlineInputBorder(),
            ),
          )),
          IconButton(tooltip:'Send message',
            onPressed:sending?null:send,
            icon:const Icon(Icons.send_rounded)),
        ]),
      ]),
    ),
  );

  Widget toolbar(Map<String,dynamic> item) {
    final priority = item['priority']?.toString() ?? 'normal';
    final stage = item['stage']?.toString() ?? 'exploring';
    final due = item['due_on']?.toString();
    final archived=item['archived_at']!=null;
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        PopupMenuButton<String>(
          tooltip: 'Priority: $priority',
          icon: Icon(Icons.flag_outlined, size: 22,
            color: priority == 'high' || priority == 'urgent'
              ? Theme.of(context).colorScheme.error : null),
          onSelected: (value) => changeField(item, 'priority', value),
          itemBuilder: (_) => [
            for (final v in ['low','normal','high','urgent'])
              PopupMenuItem(value: v, child: Text('Priority · $v')),
          ],
        ),
        PopupMenuButton<String>(
          tooltip: 'Status: $stage',
          icon: const Icon(Icons.task_alt, size: 22),
          onSelected: (value) {
            if (value == 'decision') {
              chooseDecisionOption();
            } else if (value == 'outcome') {
              recordDecision('reopened');
            } else {
              changeField(item, 'stage', value);
            }
          },
          itemBuilder: (_) => [
            for (final v in ['exploring','comparing'])
              PopupMenuItem(value: v, child: Text('Status · $v')),
            const PopupMenuItem(value: 'decision',
                child: Text('Choose an option…')),
            const PopupMenuItem(value: 'outcome',
                child: Text('Reopen Activity…')),
          ],
        ),
        IconButton(tooltip: 'Set due date', icon: const Icon(Icons.event_outlined),
          onPressed: () => pickDueDate(item)),
        if (due != null)
          IconButton(tooltip: 'Remove due date',
            icon: const Icon(Icons.event_busy_outlined),
            onPressed: () => changeField(item, 'due_on', null)),
        IconButton(tooltip: 'Add an item', icon: const Icon(Icons.add_circle_outline),
          onPressed: chooseAdd),
        PopupMenuButton<String>(
          tooltip:'Activity actions',
          icon:const Icon(Icons.more_horiz),
          onSelected:(value){
            if(value=='completed')_finishActivity(item);
            if(value=='cancelled')recordDecision('cancelled');
            if(value=='reopen')recordDecision('reopened');
            if(value=='archive')_setActivityArchived(item,true);
            if(value=='restore')_setActivityArchived(item,false);
            if(value=='history')showActivityHistory(item);
          },
          itemBuilder:(_)=>[
            if(!archived && stage!='completed')
              const PopupMenuItem(value:'completed',
                child:Text('Mark completed')),
            if(!archived && stage!='cancelled')
              const PopupMenuItem(value:'cancelled',
                child:Text('Cancel Activity…')),
            if(!archived && (stage=='cancelled'||stage=='completed'||
              stage=='on_hold'))
              const PopupMenuItem(value:'reopen',
                child:Text('Reopen Activity…')),
            if(!archived)
              const PopupMenuItem(value:'archive',
                child:Text('Archive (keep history)…')),
            if(archived)
              const PopupMenuItem(value:'restore',
                child:Text('Restore Activity…')),
            const PopupMenuItem(value:'history',child:Text('Audit history')),
          ],
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          '${priority[0].toUpperCase()}${priority.substring(1)} priority'
          ' · ${stage.replaceAll('_', ' ')}'
          '${due == null ? '' : ' · due $due'}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    ]);
  }

  Future<void> showActivityHistory(Map<String,dynamic> item) async {
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (ctx) => SafeArea(child: FractionallySizedBox(
        heightFactor: 0.7,
        child: Padding(padding: const EdgeInsets.all(16),
          child: StreamBuilder<List<Map<String,dynamic>>>(
            stream: revisions,
            builder: (context, s) => ListView(children: [
              Text('Activity edit history',
                style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              ListTile(
                title: const Text('Original'),
                subtitle: Text('${item['original_title']}\n'
                    '${item['original_body']}\n'
                    '${when(item['created_at'])}')),
              if (s.hasData)
                for (final rev in s.data!)
                  ListTile(
                    title:Text((rev['change_kind']?.toString()??'Edited')+
                      ' · '+when(rev['changed_at'])),
                    subtitle: Text(
                      '${rev['old_title']} → ${rev['new_title']}\n'
                      '${rev['old_body']} → ${rev['new_body']}\n'
                      '${rev['old_stage']} → ${rev['new_stage']}'),
                  ),
            ]),
          ),
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<List<Map<String,dynamic>>>(
    stream: activity,
    builder: (context, s) {
      if (s.hasError) {
        return Scaffold(
          appBar: AppBar(title: const Text('Activity')),
          body: const Center(child: Text('This Activity could not be loaded.')));
      }
      if (!s.hasData) {
        return Scaffold(
          appBar: AppBar(title: const Text('Activity')),
          body: const Center(child: CircularProgressIndicator()));
      }
      if (s.data!.isEmpty) {
        return Scaffold(
          appBar: AppBar(title: const Text('Activity')),
          body: const Center(child: Text('Activity not available.')));
      }
      final item = s.data!.first;
      conversationSpaceId=item['space_id']?.toString();
      return Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(item['title']?.toString() ?? 'Activity',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(tooltip: 'Edit title and details',
              onPressed: () => editActivity(item),
              icon: const Icon(Icons.edit_outlined)),
          ]),
        body:Column(children:[
          Expanded(child:ListView(
          keyboardDismissBehavior:ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 15),
          children: [
            toolbar(item),
            if (issue != null)
              Padding(padding: const EdgeInsets.only(bottom: 8),
                child: Text(issue!, style: TextStyle(
                  color: Theme.of(context).colorScheme.error))),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: InkWell(
                onTap: () => editBody(item),
                child: Text(
                  (item['body']?.toString() ?? '').isEmpty
                    ? 'Tap to add details…'
                    : item['body'].toString(),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
            componentSection(),
            decisionSection(item['space_id']?.toString()),
            conversation(item['space_id']?.toString()),
            const SizedBox(height: 12),
            Text('Created by ${author(item['created_by']?.toString(),item['space_id']?.toString())}'
                ' · ${when(item['created_at'])}',
                style: Theme.of(context).textTheme.labelSmall),
          ],
          )),
          bottomComposer(),
        ]),
      );
    },
  );
}
