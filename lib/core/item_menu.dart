import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'collection_history_screen.dart';
import 'package:onespace/l10n/phrases.dart';

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
        title: Text('Remove ${title == null || title!.isEmpty ? tt('this item') : '“$title”'}?'),
        content: Text(tt('It moves to Removed. You can restore it from the filter anytime.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tt('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tt('Remove'))),
        ]));
      if (ok != true || !context.mounted) return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final rows = await Supabase.instance.client.from(t).update({
        'archived_at': removed ? null : DateTime.now().toUtc().toIso8601String(),
      }).eq('id', recordId).select('id');
      if (rows.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(tt('Only the person who added it can change this.'))));
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(tt(removed ? tt('Restored.') : tt('Removed.')))));
      onChanged?.call();
    } on PostgrestException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${tt('Could not update')}: ${e.message}')));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(tt('Could not update. Please retry.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = <PopupMenuEntry<String>>[];
    for (var i = 0; i < statusActions.length; i++) {
      entries.add(PopupMenuItem(value: 's$i', child: ListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          leading: Icon(statusActions[i].icon), title: Text(tt(statusActions[i].label)))));
    }
    if (statusActions.isNotEmpty) entries.add(const PopupMenuDivider());
    if (onOpen != null) {
      entries.add(PopupMenuItem(value: 'open', child: ListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          leading: Icon(openLabel == 'Open' ? Icons.open_in_new : MenuIcons.edit), title: Text(tt(openLabel)))));
    }
    for (var i = 0; i < moreActions.length; i++) {
      entries.add(PopupMenuItem(value: 'm$i', child: ListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          leading: Icon(moreActions[i].icon), title: Text(tt(moreActions[i].label)))));
    }
    if (table != null || onRemove != null) {
      entries.add(PopupMenuItem(value: 'remove', child: ListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          leading: Icon(removed ? MenuIcons.restore : MenuIcons.remove),
          title: Text(tt(removed ? tt('Restore') : tt('Remove'))))));
    }
    entries.add(PopupMenuItem(value: 'log', child: ListTile(
        dense: true, contentPadding: EdgeInsets.zero,
        leading: Icon(MenuIcons.changeLog), title: Text(tt('Change log')))));
    // R58: the position is measured once, when tapped. PopupMenuButton
    // re-measures its anchor on every layout while the menu is open, which
    // crashed ("RenderBox was not laid out") on pages that rebuild live
    // underneath the menu, such as an Activity.
    return Builder(builder: (anchor) => IconButton(
      tooltip: tt('More'),
      icon: const Icon(Icons.more_vert),
      onPressed: () async {
        final box = anchor.findRenderObject() as RenderBox?;
        final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox?;
        if (box == null || overlay == null || !box.hasSize) return;
        final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
        final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
        final position = RelativeRect.fromRect(Rect.fromPoints(topLeft, bottomRight), Offset.zero & overlay.size);
        final v = await showMenu<String>(context: anchor, position: position, items: entries);
        if (v == null) return;
        if (v.startsWith('m')) {
          moreActions[int.parse(v.substring(1))].onSelected();
        } else if (v.startsWith('s')) {
          statusActions[int.parse(v.substring(1))].onSelected();
        } else if (v == 'open') {
          onOpen?.call();
        } else if (v == 'remove') {
          if (onRemove != null) { onRemove!(); } else if (anchor.mounted) { _toggleRemoved(anchor); }
        } else if (v == 'log' && anchor.mounted) {
          openChangeLog(anchor, kind: kind, recordId: recordId, recordTitle: title);
        }
      }));
  }
}

/// R57: the standard icons for menu actions, so the same action always looks
/// the same everywhere.
class MenuIcons {
  const MenuIcons._();
  static const edit = Icons.edit_outlined;
  static const remove = Icons.delete_outline;
  static const restore = Icons.restore;
  static const changeLog = Icons.history;
  static const complete = Icons.task_alt;
  static const cancel = Icons.block;
  static const reopen = Icons.undo;
  static const share = Icons.people_outline;
  static const private = Icons.lock_outline;
  static const createFrom = Icons.add_link;
  static const linked = Icons.link;
  static const readAloud = Icons.volume_up_outlined;
}

/// A menu row with its icon (for menus that are not [ItemMenu]).
PopupMenuItem<T> iconMenuItem<T>(T value, IconData icon, String label) => PopupMenuItem<T>(
  value: value,
  child: ListTile(dense: true, contentPadding: EdgeInsets.zero,
    leading: Icon(icon), title: Text(tt(label))));

/// Opens a menu at [anchor]'s current position, measured once.
Future<T?> showAnchoredMenu<T>(BuildContext anchor, List<PopupMenuEntry<T>> items) async {
  final box = anchor.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null || !box.hasSize || items.isEmpty) return null;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
  return showMenu<T>(context: anchor, items: items,
    position: RelativeRect.fromRect(Rect.fromPoints(topLeft, bottomRight), Offset.zero & overlay.size));
}

/// R58: drop-in for PopupMenuButton on pages that rebuild while a menu is
/// open (it does not re-measure its anchor during the menu's layout).
class AnchoredMenuButton<T> extends StatelessWidget {
  const AnchoredMenuButton({super.key, required this.itemBuilder, this.onSelected,
    this.icon, this.tooltip, this.initialValue});
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final Widget? icon;
  final String? tooltip;
  final T? initialValue;
  @override
  Widget build(BuildContext context) => Builder(builder: (anchor) => IconButton(
    tooltip: tooltip,
    icon: icon ?? const Icon(Icons.more_vert),
    onPressed: () async {
      final v = await showAnchoredMenu<T>(anchor, itemBuilder(anchor));
      if (v != null) onSelected?.call(v);
    }));
}
