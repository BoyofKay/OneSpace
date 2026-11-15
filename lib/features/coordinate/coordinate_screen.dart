import '../../core/editor_scaffold.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../../core/record_list_top_actions.dart';
import '../../core/status_look.dart';
import 'activity_detail_screen.dart';
import 'new_activity_screen.dart';
import 'coordinate_activity_filters.dart';

// Keep navigation imports from Remember and other existing features working.
export 'activity_detail_screen.dart' show ActivityScreen;

/// The shared-life workspace: active work, items needing attention and a
/// searchable history. There is no requirement to assign a task or deadline.
class CoordinateScreen extends StatefulWidget {
  const CoordinateScreen({super.key});

  @override
  State<CoordinateScreen> createState() => _CoordinateScreenState();
}

class _CoordinateScreenState extends State<CoordinateScreen> {
  final db = Supabase.instance.client;
  String? space;
  Stream<List<Map<String, dynamic>>>? items;
  String? error;
  bool loading = true;
  CoordinateActivityView selected = CoordinateActivityView.active;
  bool showArchived=false;
  String search = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final id = await CurrentSpaceCache.instance.get();
      if (!mounted) return;
      setState(() {
        space = id;
        loading = false;
        error = null;
        items = id == null ? null : db.from('activities')
            .stream(primaryKey: ['id']).eq('space_id', id)
            .order('updated_at', ascending: false);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Unable to load the shared workspace.';
        });
      }
    }
  }

  /// R51: a new Activity opens as a full draft page (no dialog).
  Future<void> create() async {
    if (space == null) return;
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => NewActivityScreen(spaceId: space!)));
    if (mounted) await load();
  }

  String updated(Object? raw) {
    final d = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (d == null) return '';
    return '${d.day}/${d.month}';
  }

  String label(CoordinateActivityView view) => switch (view) {
    CoordinateActivityView.active => 'Active',
    CoordinateActivityView.attention => 'Attention',
    CoordinateActivityView.finished => 'Finished',
    CoordinateActivityView.all => 'All',
  };

  Widget activityTile(Map<String, dynamic> item) {
    final priority = item['priority']?.toString() ?? 'normal';
    final stage = item['stage']?.toString() ?? 'exploring';
    final due = item['due_on']?.toString();
    final body = item['body']?.toString() ?? '';
    final emphasis = priority == 'urgent' || priority == 'high';
    final archived = item['archived_at'] != null;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 5, 5, 5),
        leading: (archived ? null : StatusLook.mark(item['stage']?.toString())) ?? Icon(
          archived ? Icons.inventory_2_outlined :
            CoordinateActivityFilters.finished(item)
              ? Icons.check_circle_outline : Icons.hub_outlined,
          color: emphasis ? Theme.of(context).colorScheme.error :
              Theme.of(context).colorScheme.secondary,
        ),
        title: Text(
          item['title']?.toString() ?? '',
          style: StatusLook.title(context, item['stage']?.toString(),
              const TextStyle(fontWeight: FontWeight.w600)),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(body, maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            const SizedBox(height: 5),
            Text(
              '${archived ? 'Removed · ' : ''}'
              '${stage.replaceAll('_', ' ')}'
              '${emphasis ? ' · $priority priority' : ''}'
              '${due == null ? '' : ' · due $due'}'
              '${item['updated_at'] == null ? '' : ' · ${updated(item['updated_at'])}'}',
              maxLines: 2,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) =>
            ActivityScreen(id: item['id'] as String))),
      ),
    );
  }

  Widget activityOverview(List<Map<String,dynamic>> all) {
    final now = DateTime.now();
    final inView=all.where((row)=>
      (row['archived_at']!=null)==showArchived).toList();
    final view=showArchived?CoordinateActivityView.all:selected;
    final shown=CoordinateActivityFilters.visible(inView,view,search,now);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if(showArchived)Text(
       'Removed Activities · Open one to restore it.',
       style:Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 10),
      TextField(
        decoration: const InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.search),
          hintText: 'Search Activities…',
          border: OutlineInputBorder(),
        ),
        onChanged: (text) => setState(() => search = text),
      ),
      const SizedBox(height: 10),
      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Text(
            search.isNotEmpty ? 'No matching Activities.' :
            showArchived ? 'No removed Activities to restore.' :
            selected == CoordinateActivityView.active ?
              'Your shared space begins with an idea. Create an Activity above.' :
            selected == CoordinateActivityView.attention ?
              'Nothing urgent or due soon.' :
              selected == CoordinateActivityView.finished ?
              'Completed decisions and experiences will stay here.' :
              'No Activities in this view.',
            textAlign: TextAlign.center,
          ),
        ),
      for (final activity in shown) activityTile(activity),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    floatingActionButton: space == null ? null
        : AddFab(label: 'Start activity', onPressed: create),
    body: RefreshIndicator(
    onRefresh: load,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Row(children:[
         Expanded(child:Text('Coordinate',
          style:Theme.of(context).textTheme.headlineMedium)),
         RecordListTopActions(
          historyKinds:const ['activity'],historyTitle:'Activities',
          showHistory:showArchived,
          onToggleHistory:()=>setState(()=>showArchived=!showArchived),
          groups:[FilterGroupSpec(id:'view',label:'Activities',options:{for(final v in CoordinateActivityView.values)v.name:label(v)},selected:selected.name,defaultValue:CoordinateActivityView.active.name)],
           onApply:(v)=>setState(()=>selected=CoordinateActivityView.values.byName(v['view']!)),
         ),
        ]),
        const SizedBox(height: 3),
        const Text('Ideas become plans, comparisons, decisions and memories.'),
        const SizedBox(height: 12),
        if (error != null) ...[
          Text(error!, style: TextStyle(
              color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
        ],
        if (loading)
          const Center(child: CircularProgressIndicator())
        else if (space == null)
          const Text('Connect your shared space to start coordinating.')
        else if (items != null)
          StreamBuilder<List<Map<String,dynamic>>>(
            stream: items,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('Could not load Activities. Pull down to retry.');
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return activityOverview(snapshot.data!);
            },
          ),
      ],
    ),
  ));
}
