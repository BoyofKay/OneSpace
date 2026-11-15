import '../../core/item_menu.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/collection_history_screen.dart';
import '../../core/current_space_cache.dart';
import '../../core/record_list_top_actions.dart';
import 'share_intake_screen.dart';
import 'share_suggestions.dart';

/// R52 (spec 4.3): "Items to sort", the tray for things saved quickly from
/// other apps. Private to the person who saved it unless switched to Shared.
/// Each item: Sort (destination picker with suggestions), Remove, Change log.
/// Nothing is removed automatically; old items get a gentle label.
class ItemsToSortScreen extends StatefulWidget {
  const ItemsToSortScreen({super.key});
  @override State<ItemsToSortScreen> createState() => _ItemsToSortScreenState();
}

class _ItemsToSortScreenState extends State<ItemsToSortScreen> {
  final db = Supabase.instance.client;
  bool loading = true, showRemoved = false;
  String? error, spaceId;
  List<Map<String, dynamic>> items = const [];

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      spaceId ??= await CurrentSpaceCache.instance.get();
      if (spaceId == null) {
        if (mounted) setState(() { loading = false; error = 'Connect a shared space first.'; });
        return;
      }
      var query = db.from('items_to_sort')
          .select('id,created_by,title,link,note,visibility,archived_at,created_at,file_path,file_name,file_mime')
          .eq('space_id', spaceId!).isFilter('sorted_at', null);
      query = showRemoved ? query.not('archived_at', 'is', null)
          : query.isFilter('archived_at', null);
      final rows = await query.order('created_at', ascending: false).limit(200);
      if (!mounted) return;
      setState(() { items = List<Map<String, dynamic>>.from(rows); loading = false; });
    } catch (_) {
      if (mounted) setState(() { loading = false; error = 'Items to sort are unavailable right now.'; });
    }
  }

  Future<void> _update(Map<String, dynamic> item, Map<String, dynamic> change, String done) async {
    try {
      await db.from('items_to_sort').update(change).eq('id', item['id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save the change. Try again.')));
      }
    }
  }

  Future<void> _sort(Map<String, dynamic> item) async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
        builder: (_) => ShareIntakeScreen(trayItem: item)));
    if (mounted) await _load();
  }

  /// R55: open an attached photo/PDF through a short-lived signed link.
  Future<void> _openFile(Map<String, dynamic> item) async {
    try {
      final url = await db.storage.from('onespace-share-in')
          .createSignedUrl(item['file_path'].toString(), 300);
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No app could open this file.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the file. Please retry.')));
      }
    }
  }

  Future<void> _add() async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
        builder: (_) => const ShareIntakeScreen()));
    if (mounted) await _load();
  }

  String query = '';
  bool _matches(Map<String, dynamic> item) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [item['title'], item['note'], item['link'], item['file_name']]
        .map((v) => v?.toString().toLowerCase() ?? '').join(' ').contains(q);
  }

  String _age(Object? raw) {
    final at = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (at == null) return '';
    final days = DateTime.now().difference(at).inDays;
    return days == 0 ? 'Saved today' : days == 1 ? 'Saved yesterday' : 'Saved $days days ago';
  }

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = db.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Items to sort'), actions: [
        RecordListTopActions(
          showHistory: showRemoved,
          onToggleHistory: () { setState(() => showRemoved = !showRemoved); _load(); },
          historyKinds: const ['sort_item'], historyTitle: 'Items to sort'),
      ]),
      floatingActionButton: FloatingActionButton.extended(heroTag: 'add-sort-item',
        onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add item')),
      body: RefreshIndicator(onRefresh: _load, child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
        children: [
          TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search),
              labelText: 'Search items to sort', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          if (showRemoved) FilterShowingLine(labels: const ['Removed'],
            onClear: () { setState(() => showRemoved = false); _load(); }),
          if (loading) const Padding(padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()))
          else if (error != null) Padding(padding: const EdgeInsets.all(24),
            child: Column(children: [Text(error!),
              TextButton(onPressed: _load, child: const Text('Retry'))]))
          else if (items.isEmpty) Padding(padding: const EdgeInsets.all(28),
            child: Text(showRemoved ? 'Nothing removed.'
                : 'Nothing to sort. Share a link, a note or a product from any app '
                  'and choose "Save to Items to sort".',
              textAlign: TextAlign.center, style: theme.textTheme.bodyMedium))
          else for (final item in items.where(_matches)) Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(padding: const EdgeInsets.fromLTRB(14, 10, 4, 8), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(item['title']?.toString() ?? 'Saved item',
                    style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    onSelected: (choice) {
                      switch (choice) {
                        case 'share': _update(item, {'visibility': 'shared'}, 'Now visible to both of you.');
                        case 'private': _update(item, {'visibility': 'private'}, 'Now only you can see it.');
                        case 'remove': _update(item, {'archived_at': DateTime.now().toUtc().toIso8601String()},
                            'Removed. Restore it from the filter panel.');
                        case 'restore': _update(item, {'archived_at': null}, 'Restored.');
                        case 'sort': _sort(item);
                        case 'log': openChangeLog(context, kind: 'sort_item',
                            recordId: item['id'].toString(), recordTitle: item['title']?.toString());
                      }
                    },
                    itemBuilder: (_) => [
                      if (item['created_by'] == me) item['visibility'] == 'shared'
                        ? iconMenuItem('private', MenuIcons.private, 'Make it only mine')
                        : iconMenuItem('share', MenuIcons.share, 'Share with my partner'),
                      if (item['archived_at'] == null) iconMenuItem('sort', Icons.drive_file_move_outlined, 'Sort'),
                      const PopupMenuDivider(),
                      if (item['archived_at'] == null)
                        iconMenuItem('remove', MenuIcons.remove, 'Remove')
                      else iconMenuItem('restore', MenuIcons.restore, 'Restore'),
                      iconMenuItem('log', MenuIcons.changeLog, 'Change log'),
                    ]),
                ]),
                if ((item['link']?.toString() ?? '').isNotEmpty)
                  Text(item['link'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                if (item['file_path'] != null) Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: ActionChip(
                    avatar: Icon(item['file_mime'] == 'application/pdf'
                        ? Icons.picture_as_pdf_outlined : Icons.image_outlined, size: 18),
                    label: Text(item['file_name']?.toString() ??
                        (item['file_mime'] == 'application/pdf' ? 'PDF' : 'Photo'),
                      overflow: TextOverflow.ellipsis),
                    onPressed: () => _openFile(item))),
                if ((item['note']?.toString() ?? '').isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 2), child: Text(item['note'].toString(),
                    maxLines: 3, overflow: TextOverflow.ellipsis)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(item['visibility'] == 'shared' ? Icons.people_outline : Icons.lock_outline,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(child: Text([
                    item['visibility'] == 'shared' ? 'Shared' : 'Only me',
                    _age(item['created_at']),
                    if (ShareSuggestions.isStale(
                        DateTime.tryParse(item['created_at']?.toString() ?? '') ?? DateTime.now(),
                        DateTime.now())) 'still want this?',
                  ].join(' · '), style: theme.textTheme.bodySmall)),
                  if (item['archived_at'] == null) FilledButton.tonal(
                    onPressed: () => _sort(item), child: const Text('Sort')),
                ]),
              ]))),
        ],
      )),
    );
  }
}
