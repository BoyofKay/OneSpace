import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'collection_history_screen.dart';

/// One extra action shown in an [ItemMenu] (for example "Mark done").
class ItemMenuAction {
  const ItemMenuAction(this.label, this.icon, this.onSelected);
  final String label;
  final IconData icon;
  final VoidCallback onSelected;
}

/// R55: the one ⋮ menu every list item uses, always in the same order:
///
///  1. the item's own final-status actions (Mark done, Cancel, …)
///  2. Open / Edit
///  3. Remove (or Restore when the item is removed)
///  4. Change log
///
/// Remove is a soft remove (`archived_at`), confirmed first, and can be
/// undone with Restore from the Removed filter. Row-level security still
/// decides who may remove; a refusal is shown as a short message.
class ItemMenu extends StatelessWidget {
  const ItemMenu({
    super.key,
    required this.kind,
    required this.recordId,
    this.title,
    this.statusActions = const [],
    this.onOpen,
    this.openLabel = 'Edit',
    this.table,
    this.removed = false,
    this.onChanged,
    this.onRemove,
    this.moreActions = const [],
  });

  /// Change-log kind (as used by `record_action_history`).
  final String kind;
  final String recordId;
  final String? title;
  final List<ItemMenuAction> statusActions;
  final VoidCallback? onOpen;
  final String openLabel;

  /// Table to soft-remove from; null hides Remove/Restore.
  final String? table;
  final bool removed;
  final VoidCallback? onChanged;

  /// Screen-specific remove/restore (keeps its own checks); shown when set.
  final VoidCallback? onRemove;

  /// Item-specific extras (Create from this, Linked items, Share…), shown
  /// after Edit and before Remove.
  final List<ItemMenuAction> moreActions;

  Future<void> _toggleRemoved(BuildContext context) async {
    final t = table;
    if (t == null) return;
    if (!removed) {
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: Text('Remove ${title == null || title!.isEmpty ? 'this item' : '“$title”'}?'),
        content: const Text('It moves to Removed. You can restore it from the filter anytime.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ]));
      if (ok != true || !context.mounted) return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final rows = await Supabase.instance.client.from(t).update({
        'archived_at': removed ? null : DateTime.now().toUtc().toIso8601String(),
      }).eq('id', recordId).select('id');
      if (rows.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('Only the person who added it can change this.')));
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(removed ? 'Restored.' : 'Removed.')));
      onChanged?.call();
    } on PostgrestException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not update: ${e.message}')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not update. Please retry.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = <PopupMenuEntry<String>>[];
    for (var i = 0; i < statusActions.length; i++) {
      entries.add(PopupMenuItem(value: 's$i', child: ListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          leading: Icon(statusActions[i].icon), title: Text(statusActions[i].label))));
    }
    if (statusActions.isNotEmpty) entries.add(const PopupMenuDivider());
    if (onOpen != null) {
      entries.add(PopupMenuItem(value: 'open', child: ListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.edit_outlined), title: Text(openLabel))));
    }
    for (var i = 0; i < moreActions.length; i++) {
      entries.add(PopupMenuItem(value: 'm$i', child: ListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          leading: Icon(moreActions[i].icon), title: Text(moreActions[i].label))));
    }
    if (table != null || onRemove != null) {
      entries.add(PopupMenuItem(value: 'remove', child: ListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          leading: Icon(removed ? Icons.restore : Icons.delete_outline),
          title: Text(removed ? 'Restore' : 'Remove'))));
    }
    entries.add(const PopupMenuItem(value: 'log', child: ListTile(
        dense: true, contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.history), title: Text('Change log'))));
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert),
      itemBuilder: (_) => entries,
      onSelected: (v) {
        if (v.startsWith('m')) {
          moreActions[int.parse(v.substring(1))].onSelected();
        } else if (v.startsWith('s')) {
          statusActions[int.parse(v.substring(1))].onSelected();
        } else if (v == 'open') {
          onOpen?.call();
        } else if (v == 'remove') {
          if (onRemove != null) { onRemove!(); } else { _toggleRemoved(context); }
        } else if (v == 'log') {
          openChangeLog(context, kind: kind, recordId: recordId, recordTitle: title);
        }
      },
    );
  }
}
