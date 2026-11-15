import 'package:material_ui/material_ui.dart';

import 'collection_history_screen.dart';

/// One group of filter choices a screen offers (single choice, shown as chips).
/// Screens only describe their groups; the panel draws every screen the same way.
class FilterGroupSpec {
  const FilterGroupSpec({required this.id, required this.label,
    required this.options, required this.selected, required this.defaultValue});
  final String id, label;
  /// value -> label, in display order.
  final Map<String, String> options;
  final String selected, defaultValue;

  bool get isActive => selected != defaultValue;
  String get selectedLabel => options[selected] ?? selected;

  /// Labels for the "Showing: …" line, Removed first.
  static List<String> showing(List<FilterGroupSpec> groups, {bool removed = false}) => [
    if (removed) 'Removed',
    for (final g in groups) if (g.isActive) g.selectedLabel,
  ];
}

/// R50/R55 (spec 2.3/2.4, backlog B-13/B-14): the same two top actions on every
/// collection screen.
///
/// * Clock: the change log page ("who did what, when") with people and action chips.
/// * Slider: a filter panel that drops down under the icon (never a bottom
///   sheet). "Status: Active | Removed" first, then the screen's own groups as
///   chips, Clear and Apply pinned at the bottom. Nothing changes until Apply.
///   A dot on the icon shows while any filter is on.
///
/// Filters live in the screen's state, so they reset when you leave it.
class RecordListTopActions extends StatelessWidget {
  const RecordListTopActions({super.key,
    required this.showHistory, required this.onToggleHistory,
    this.groups = const [], this.onApply,
    this.historyKinds, this.historyTitle = 'Change log', this.allowRemoved = true});

  /// True while removed items are shown (Status = Removed).
  final bool showHistory;
  final VoidCallback onToggleHistory;
  final List<FilterGroupSpec> groups;
  /// Called on Apply/Clear with the chosen value per group id.
  final ValueChanged<Map<String, String>>? onApply;
  /// Record kinds for the change log page; null hides the clock.
  final List<String>? historyKinds;
  final String historyTitle;
  /// Screens without Remove (nothing to restore) hide the Status group.
  final bool allowRemoved;

  bool get active => showHistory || groups.any((g) => g.isActive);

  @override Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min, children: [
      if (historyKinds != null) IconButton(
        tooltip: 'Change log',
        icon: const Icon(Icons.history),
        onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
          builder: (_) => CollectionHistoryScreen(
            kinds: historyKinds!, title: historyTitle)))),
      if (allowRemoved || groups.isNotEmpty) Builder(builder: (anchor) => IconButton(
        tooltip: active ? 'Filters (on)' : 'Filters',
        icon: Badge(isLabelVisible: active, smallSize: 8, child: const Icon(Icons.tune)),
        onPressed: () => showFilterPanel(anchor,
          removed: showHistory,
          allowRemoved: allowRemoved,
          groups: groups,
          onApply: (removed, values) {
            if (removed != showHistory) onToggleHistory();
            onApply?.call(values);
          }))),
    ]);
}

/// Opens the drop-down filter panel under [anchor] (spec 2.3).
Future<void> showFilterPanel(BuildContext anchor, {
  required bool removed,
  required List<FilterGroupSpec> groups,
  required void Function(bool removed, Map<String, String> values) onApply,
  bool allowRemoved = true,
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
      final pending = {for (final g in groups) g.id: g.selected};
      final width = (media.size.width - 24).clamp(260.0, 380.0);
      return Stack(children: [
        Positioned(
          top: top, right: 12, width: width,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: media.size.height * .7),
              child: StatefulBuilder(builder: (context, refresh) {
                final theme = Theme.of(context);
                Widget group(String label, Map<String, String> options, String value,
                    ValueChanged<String> pick) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final o in options.entries) ChoiceChip(
                        label: Text(o.value),
                        selected: value == o.key,
                        showCheckmark: false,
                        onSelected: (_) => refresh(() => pick(o.key))),
                    ]),
                  ]));
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 2),
                      child: Row(children: [
                        Expanded(child: Text('Filter', style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700))),
                        IconButton(tooltip: 'Close', visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.of(context).pop()),
                      ])),
                    Flexible(child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (allowRemoved) group('Status',
                          const {'active': 'Active', 'removed': 'Removed'},
                          pendingRemoved ? 'removed' : 'active',
                          (v) => pendingRemoved = v == 'removed'),
                        for (var i = 0; i < groups.length; i++) ...[
                          if (allowRemoved || i > 0)
                            const Divider(height: 1, indent: 16, endIndent: 16),
                          group(groups[i].label, groups[i].options, pending[groups[i].id]!,
                            (v) => pending[groups[i].id] = v),
                        ],
                      ]))),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      child: Row(children: [
                        Expanded(child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onApply(false, {for (final g in groups) g.id: g.defaultValue});
                          },
                          child: const Text('Clear'))),
                        const SizedBox(width: 10),
                        Expanded(child: FilledButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onApply(pendingRemoved, pending);
                          },
                          child: const Text('Apply'))),
                      ])),
                  ]);
              }),
            ),
          ),
        ),
      ]);
    },
  );
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

/// AppBar.bottom "Showing" line for a list screen; null when no filter is on.
PreferredSizeWidget? filterShowingBar(List<FilterGroupSpec> groups,
    {required bool removed, required VoidCallback onClear}) {
  final labels = FilterGroupSpec.showing(groups, removed: removed);
  if (labels.isEmpty) return null;
  return PreferredSize(preferredSize: const Size.fromHeight(34),
    child: FilterShowingLine(labels: labels, onClear: onClear));
}
