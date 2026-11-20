import 'dart:async';
import '../../core/item_menu.dart';
import '../../core/editor_scaffold.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../../core/app_env.dart';
import '../../core/record_list_top_actions.dart';
import '../../core/status_look.dart';
import 'activity_detail_screen.dart';
import 'new_activity_screen.dart';
import 'coordinate_activity_filters.dart';
import 'package:onespace/l10n/phrases.dart';
import 'activity_countdown_rules.dart';

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
  bool personalReady = false;
  String who = 'all';
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

  /// R66: "N days remaining" per Activity, from its countdown dates.
  Map<String, int> countdowns = const {};

  Future<void> _loadCountdowns() async {
    try {
      final rows = await db.from('activity_components').select('activity_id,kind,payload')
        .inFilter('kind', ['countdown', 'date']).isFilter('archived_at', null).limit(500);
      final now = DateTime.now();
      final map = <String, int>{};
      for (final r in rows) {
        final p = r['payload'] is Map ? r['payload'] as Map : const {};
        if (r['kind'] == 'date' && p['countdown'] != true) continue;
        final days = ActivityCountdownRules.remaining(p['value']?.toString(),
          repeatYearly: p['repeat_yearly'] == true, now: now);
        if (days == null || days < 0) continue;
        final id = r['activity_id'].toString();
        if (!map.containsKey(id) || days < map[id]!) map[id] = days;
      }
      if (mounted) setState(() => countdowns = map);
    } catch (_) {}
  }

  Future<void> load() async {
    unawaited(_loadCountdowns());
    try {
      var id = await CurrentSpaceCache.instance.get();
      bool hasPrivateScope = false;
      if (!OneSpaceEnv.isProduction) {
        final scopes = await db.rpc('my_storage_scopes');
        if (scopes is! Map ||
            scopes['private_space_id']?.toString() != db.auth.currentUser?.id) {
          throw StateError('Personal Activity scope unavailable');
        }
        id = scopes['shared_space_id']?.toString();
        hasPrivateScope = true;
      }
      if (!mounted) return;
      setState(() {
        space = id;
        personalReady = hasPrivateScope;
        loading = false;
        error = null;
        // QA reads only RLS-authorized private and current-pair rows.
        // A new partner never grants access to previous shared activities.
        items = OneSpaceEnv.isProduction
          ? (id == null ? null : db.from('activities')
              .stream(primaryKey: ['id']).eq('space_id', id)
              .order('updated_at', ascending: false))
          : db.from('activities').stream(primaryKey: ['id'])
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
    if (space == null && !personalReady) return;
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => NewActivityScreen(spaceId: space ?? '')));
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
        contentPadding: const EdgeInsetsDirectional.fromSTEB(12, 5, 5, 5),
        leading: (archived ? null : StatusLook.mark(item['stage']?.toString())) ?? Icon(
          archived ? Icons.inventory_2_outlined :
            CoordinateActivityFilters.finished(item)
              ? Icons.check_circle_outline : Icons.hub_outlined,
          color: emphasis ? Theme.of(context).colorScheme.error :
              Theme.of(context).colorScheme.secondary,
        ),
        title: Text(
          tt(item['title']?.toString() ?? ''),
          style: StatusLook.title(context, item['stage']?.toString(),
              const TextStyle(fontWeight: FontWeight.w600)),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(tt(body), maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            if (!archived && countdowns[item['id']?.toString()] != null) Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(children: [
                Icon(Icons.hourglass_bottom_outlined, size: 15, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 4),
                Text(tt(countdowns[item['id'].toString()] == 0 ? 'Today is the day!'
                    : countdowns[item['id'].toString()] == 1 ? '1 day remaining'
                    : '${countdowns[item['id'].toString()]} days remaining'),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
              ])),
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
        trailing: ItemMenu(kind: 'activity', recordId: item['id'].toString(),
          title: item['title']?.toString(), openLabel: tt('Open'),
          onOpen: () async {
            await Navigator.of(context).push<void>(MaterialPageRoute<void>(
              builder: (_) => ActivityScreen(id: item['id'] as String)));
            if (mounted) await load();
          },
          table: 'activities', removed: archived, onChanged: load),
        onTap: () async {
          await Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (_) => ActivityScreen(id: item['id'] as String)));
          if (mounted) await load();
        },
      ),
    );
  }

  Widget activityOverview(List<Map<String,dynamic>> all) {
    final now = DateTime.now();
    final inView=all.where((row)=>
      (row['archived_at']!=null)==showArchived &&
      (who == 'all' || row['visibility'] == who)).toList();
    final view=showArchived?CoordinateActivityView.all:selected;
    final shown=CoordinateActivityFilters.visible(inView,view,search,now);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if(showArchived)Text(
       tt('Removed Activities · Open one to restore it.'),
       style:Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 10),
      TextField(
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.search),
          labelText: tt('Search activities'),
          border: OutlineInputBorder(),
        ),
        onChanged: (text) => setState(() => search = text),
      ),
      const SizedBox(height: 10),
      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Text(
            tt(search.isNotEmpty ? 'No matching Activities.' :
            showArchived ? 'No removed Activities to restore.' :
            selected == CoordinateActivityView.active ?
              'Your shared space begins with an idea. Create an Activity above.' :
            selected == CoordinateActivityView.attention ?
              'Nothing urgent or due soon.' :
              selected == CoordinateActivityView.finished ?
              'Completed decisions and experiences will stay here.' :
              'No Activities in this view.'),
            textAlign: TextAlign.center,
          ),
        ),
      for (final activity in shown) activityTile(activity),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    floatingActionButton: space == null && !personalReady ? null
        : AddFab(label: tt('Start activity'), onPressed: create),
    body: RefreshIndicator(
    onRefresh: load,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 96),
      children: [
        Row(children:[
         Expanded(child:Text(tt('Coordinate'),
          style:Theme.of(context).textTheme.headlineMedium)),
         RecordListTopActions(
          historyKinds:const ['activity'],historyTitle:tt('Activities'),
          showHistory:showArchived,
          onToggleHistory:()=>setState(()=>showArchived=!showArchived),
          groups:[
            FilterGroupSpec(id:'view',label:tt('Activities'),
              options:{for(final v in CoordinateActivityView.values)v.name:label(v)},
              selected:selected.name,defaultValue:CoordinateActivityView.active.name),
            FilterGroupSpec(id:'who',label:tt('Who can see'),
              options:const {'all':'All','shared':'Shared','private':'Only me'},
              selected:who,defaultValue:'all'),
          ],
          onApply:(v)=>setState((){
            selected=CoordinateActivityView.values.byName(v['view']!);
            who=v['who']!;
          }),
         ),
        ]),
        const SizedBox(height: 3),
        Text(tt('Ideas become plans, comparisons, decisions and memories.')),
        const SizedBox(height: 12),
        if (error != null) ...[
          Text(tt(error!), style: TextStyle(
              color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
        ],
        if (loading)
          const Center(child: CircularProgressIndicator())
        else if (space == null && !personalReady)
          Text(tt('Connect your shared space to start coordinating.'))
        else if (items != null)
          StreamBuilder<List<Map<String,dynamic>>>(
            stream: items,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(tt('Could not load Activities. Pull down to retry.'));
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
