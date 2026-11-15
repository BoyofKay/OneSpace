import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onespace/l10n/phrases.dart';

/// R50 (spec 2.4, backlog B-14): the one history page every screen uses.
/// "Who did what, when", newest first, with quick filter chips: people,
/// then actions. Opened from a screen's clock icon (all its items) or from an
/// item's "Change log" (that item only). Rows for removed items can be
/// restored here. Private items only appear in their owner's log: the
/// history table is read through each record's own access rules.
class CollectionHistoryScreen extends StatefulWidget {
  const CollectionHistoryScreen({super.key, required this.kinds,
    required this.title, this.recordId, this.recordTitle});
  final List<String> kinds;
  final String title;
  final String? recordId;
  final String? recordTitle;
  @override State<CollectionHistoryScreen> createState() =>
      _CollectionHistoryScreenState();
}

/// Where each history kind lives, and the column that names an item.
const historySources = <String, (String table, String titleColumn)>{
  'note': ('notes', 'title'),
  'task': ('tasks', 'title'),
  'memory': ('memories', 'title'),
  'event': ('space_events', 'title'),
  'reminder': ('reminders', 'title'),
  'occasion': ('occasion_plans', 'title'),
  'experience': ('shared_experiences', 'title'),
  'trip': ('shared_trips', 'title'),
  'contact': ('saved_contacts', 'label'),
  'sort_item': ('items_to_sort', 'title'),
  'activity': ('activities', 'title'),
};

/// Chip groups (spec 2.4). Database actions map onto the words people use.
const historyActionChips = ['All', 'Created', 'Edited', 'Completed',
  'Cancelled', 'Missed', 'Removed', 'Restored'];

String historyActionLabel(String action) => switch (action) {
  'created' => 'Created',
  'completed' => 'Completed',
  'cancelled' => 'Cancelled',
  'missed' => 'Missed',
  'archived' => 'Removed',
  'restored' => 'Restored',
  'reopened' => 'Reopened',
  _ => 'Edited',
};

bool historyActionMatches(String chip, String action) {
  if (chip == 'All') return true;
  final label = historyActionLabel(action);
  if (chip == 'Edited') return label == 'Edited' || label == 'Reopened';
  return label == chip;
}

/// "due_on, archived_at" -> "due on"; bookkeeping fields are left out.
String historyFieldsLabel(List<dynamic>? fields) {
  const hidden = {'archived_at', 'updated_at', 'created_at', 'id', 'space_id',
    'created_by', 'search_text', 'original_title', 'original_body'};
  final names = [
    for (final f in fields ?? const [])
      if (!hidden.contains(f.toString())) f.toString().replaceAll('_', ' '),
  ];
  if (names.length > 4) {
    return '${names.take(4).join(', ')} +${names.length - 4} more';
  }
  return names.join(', ');
}

class _CollectionHistoryScreenState extends State<CollectionHistoryScreen> {
  final db = Supabase.instance.client;
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> rows = const [];
  final titles = <String, String>{};
  final removedNow = <String>{};
  final people = <String, String>{}; // user id -> first name
  String person = 'everyone';
  String action = 'All';

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      var query = db.from('record_action_history')
          .select('id,record_kind,record_id,actor_id,action,changed_fields,happened_at')
          .inFilter('record_kind', widget.kinds);
      if (widget.recordId != null) query = query.eq('record_id', widget.recordId!);
      final found = List<Map<String, dynamic>>.from(
          await query.order('happened_at', ascending: false).limit(300));
      // Item names and current removed state, one request per kind.
      final byKind = <String, Set<String>>{};
      for (final r in found) {
        byKind.putIfAbsent(r['record_kind'].toString(), () => {})
            .add(r['record_id'].toString());
      }
      for (final entry in byKind.entries) {
        final source = historySources[entry.key];
        if (source == null) continue;
        try {
          final hasRemoved = entry.key != 'task';
          final items = await db.from(source.$1)
              .select(hasRemoved ? 'id,${source.$2},archived_at' : 'id,${source.$2}')
              .inFilter('id', entry.value.toList());
          for (final item in items) {
            final id = item['id'].toString();
            titles[id] = item[source.$2]?.toString() ?? '';
            if (hasRemoved && item['archived_at'] != null) removedNow.add(id);
          }
        } catch (_) {/* A missing title never hides the history row. */}
      }
      final members = await db.from('profiles').select('id,display_name');
      final me = db.auth.currentUser?.id;
      for (final p in members) {
        final name = (p['display_name']?.toString().trim() ?? '');
        people[p['id'].toString()] = p['id'] == me ? 'Me'
            : name.isEmpty ? 'Partner' : name.split(RegExp(r'\s+')).first;
      }
      if (!mounted) return;
      setState(() { rows = found; loading = false; });
    } catch (_) {
      if (mounted) setState(() { loading = false; error = 'History is unavailable right now.'; });
    }
  }

  Future<void> _restore(Map<String, dynamic> row) async {
    final source = historySources[row['record_kind'].toString()];
    if (source == null) return;
    try {
      await db.from(source.$1).update({'archived_at': null})
          .eq('id', row['record_id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tt('Restored.'))));
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tt('Could not restore this item.'))));
      }
    }
  }

  String _initials(String? id) {
    final name = id == null ? 'OneSpace' : people[id] ?? 'Partner';
    return name == 'Me' ? 'Me' : name.substring(0, 1).toUpperCase();
  }

  String _when(Object? raw) {
    final at = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (at == null) return '';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    return '${at.day} ${months[at.month - 1]} · $h:${at.minute.toString().padLeft(2, '0')} '
        '${at.hour >= 12 ? tt('PM') : tt('AM')}';
  }

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = db.auth.currentUser?.id;
    final partnerIds = people.keys.where((id) => id != me).toList();
    final shown = rows.where((r) {
      final actor = r['actor_id']?.toString();
      final personOk = person == 'everyone' || actor == person;
      return personOk && historyActionMatches(action, r['action']?.toString() ?? '');
    }).toList();
    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(label: Text(tt(label)), selected: selected,
          onSelected: (_) => onTap()));
    return Scaffold(
      appBar: AppBar(title: Text(tt(widget.recordTitle == null
          ? '${widget.title} · change log' : tt('Change log')))),
      body: Column(children: [
        if (widget.recordTitle != null) Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 0),
          child: Align(alignment: AlignmentDirectional.centerStart,
            child: Text(tt(widget.recordTitle!), style: theme.textTheme.titleMedium))),
        SizedBox(height: 52, child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 4),
          children: [
            chip('Everyone', person == 'everyone', () => setState(() => person = 'everyone')),
            if (me != null) chip('Me', person == me, () => setState(() => person = me)),
            for (final id in partnerIds)
              chip(people[id]!, person == id, () => setState(() => person = id)),
            const VerticalDivider(width: 14, indent: 8, endIndent: 8),
            for (final a in historyActionChips)
              chip(a, action == a, () => setState(() => action = a)),
          ])),
        const Divider(height: 1),
        Expanded(child: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(tt(error!)), TextButton(onPressed: _load, child: Text(tt('Retry')))]))
            : shown.isEmpty
              ? Center(child: Padding(padding: EdgeInsets.all(24),
                  child: Text(tt('Nothing here yet. Changes appear as either of you works.'),
                    textAlign: TextAlign.center)))
              : RefreshIndicator(onRefresh: _load, child: ListView.separated(
                  itemCount: shown.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 64),
                  itemBuilder: (context, i) {
                    final r = shown[i];
                    final id = r['record_id'].toString();
                    final label = historyActionLabel(r['action']?.toString() ?? '');
                    final title = titles[id]?.trim().isNotEmpty == true ? titles[id]! : 'Untitled';
                    final fields = r['action'] == 'edited'
                        ? historyFieldsLabel(r['changed_fields'] as List<dynamic>?) : '';
                    final canRestore = r['action'] == 'archived' && removedNow.contains(id);
                    return ListTile(
                      leading: CircleAvatar(radius: 18,
                        child: Text(tt(_initials(r['actor_id']?.toString())),
                          style: theme.textTheme.labelMedium)),
                      title: Text('$label · $title', maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(tt([if (fields.isNotEmpty) fields, _when(r['happened_at'])]
                          .join('\n'))),
                      isThreeLine: fields.isNotEmpty,
                      trailing: canRestore ? TextButton(
                        onPressed: () => _restore(r), child: Text(tt('Restore'))) : null,
                    );
                  })),
        ),
      ]),
    );
  }
}

/// Opens the change log for one item (the ⋮ menu's "Change log").
Future<void> openChangeLog(BuildContext context, {required String kind,
    required String recordId, String? recordTitle}) =>
  Navigator.of(context).push<void>(MaterialPageRoute<void>(
    builder: (_) => CollectionHistoryScreen(kinds: [kind], title: tt('Change log'),
        recordId: recordId, recordTitle: recordTitle ?? '')));
