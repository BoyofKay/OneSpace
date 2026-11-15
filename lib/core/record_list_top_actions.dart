import 'package:material_ui/material_ui.dart';

import 'collection_history_screen.dart';

/// R50 (spec 2.3/2.4, backlog B-13/B-14): the same two top actions on every
/// collection screen.
///
/// * Clock: opens the change log page ("who did what, when") for the
///   screen's items, with people and action chips.
/// * Slider (tune): drops a filter panel down under the icon, never a bottom
///   sheet. A Status group always offers "Removed" (Removed is a filter, not
///   history); the screen's own filter groups follow; Clear and Apply stay
///   pinned at the bottom. A dot on the icon shows while any filter is on.
///
/// Filters live in the screen's state, so they reset when you leave it.
class RecordListTopActions extends StatelessWidget {
  const RecordListTopActions({super.key,
    required this.showHistory, required this.onToggleHistory,
    this.filters, this.hasActiveFilters = false,
    this.historyKinds, this.historyTitle = 'Change log', this.onClearFilters});

  /// True while removed items are shown (the "Removed" status filter).
  final bool showHistory;
  final VoidCallback onToggleHistory;
  final WidgetBuilder? filters;
  final bool hasActiveFilters;
  /// Record kinds for the change log page; null hides the clock.
  final List<String>? historyKinds;
  final String historyTitle;
  /// Resets the screen's own filters (Clear button).
  final VoidCallback? onClearFilters;

  @override Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min, children: [
      if (historyKinds != null) IconButton(
        tooltip: 'Change log',
        icon: const Icon(Icons.history),
        onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
          builder: (_) => CollectionHistoryScreen(
            kinds: historyKinds!, title: historyTitle)))),
      Builder(builder: (anchor) => IconButton(
        tooltip: hasActiveFilters || showHistory ? 'Filters (on)' : 'Filters',
        icon: Badge(
          isLabelVisible: hasActiveFilters || showHistory,
          smallSize: 8,
          child: const Icon(Icons.tune)),
        onPressed: () => showFilterPanel(anchor,
          removed: showHistory,
          onRemovedChanged: (_) => onToggleHistory(),
          filters: filters,
          onClear: onClearFilters))),
    ]);
}

/// Opens the drop-down filter panel under [anchor] (spec 2.3).
Future<void> showFilterPanel(BuildContext anchor, {
  required bool removed,
  required ValueChanged<bool> onRemovedChanged,
  WidgetBuilder? filters,
  VoidCallback? onClear,
}) {
  final box = anchor.findRenderObject() as RenderBox?;
  final media = MediaQuery.of(anchor);
  final top = box == null ? media.padding.top + kToolbarHeight
      : box.localToGlobal(Offset.zero).dy + box.size.height;
  return showGeneralDialog<void>(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'Close filters',
    barrierColor: Colors.black.withValues(alpha: .12),
    transitionDuration: const Duration(milliseconds: 140),
    transitionBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
      opacity: animation,
      child: SizeTransition(sizeFactor: animation, axisAlignment: -1, child: child)),
    pageBuilder: (context, animation, secondaryAnimation) {
      var pendingRemoved = removed;
      final width = (media.size.width - 24).clamp(240.0, 380.0);
      final maxHeight = media.size.height * .7;
      return Stack(children: [
        Positioned(
          top: top, right: 12, width: width,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: StatefulBuilder(builder: (context, refresh) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Text('Filters', style: Theme.of(context).textTheme.titleMedium)),
                  Flexible(child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _GroupLabel('Status'),
                        CheckboxListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Removed'),
                          subtitle: const Text('Items either of you removed; restore from here'),
                          value: pendingRemoved,
                          onChanged: (v) => refresh(() => pendingRemoved = v ?? false)),
                        if (filters != null) ...[
                          const Divider(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: filters(context)),
                        ],
                      ]))),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
                    child: Row(children: [
                      TextButton(
                        onPressed: () {
                          if (removed) onRemovedChanged(false);
                          onClear?.call();
                          Navigator.of(context).pop();
                        },
                        child: const Text('Clear')),
                      const Spacer(),
                      FilledButton(
                        onPressed: () {
                          if (pendingRemoved != removed) onRemovedChanged(pendingRemoved);
                          Navigator.of(context).pop();
                        },
                        child: const Text('Apply')),
                    ])),
                ])),
            ),
          ),
        ),
      ]);
    },
  );
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
    child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall
        ?.copyWith(letterSpacing: .8, fontWeight: FontWeight.w700)));
}

/// "Showing: Removed · Only me ✕" under a screen title while filtered.
class FilterShowingLine extends StatelessWidget {
  const FilterShowingLine({super.key, required this.labels, required this.onClear});
  final List<String> labels;
  final VoidCallback onClear;
  @override Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      child: Row(children: [
        Expanded(child: Text('Showing: ${labels.join(' · ')}',
          style: Theme.of(context).textTheme.bodySmall)),
        IconButton(
          tooltip: 'Clear filters',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, size: 18),
          onPressed: onClear),
      ]));
  }
}
