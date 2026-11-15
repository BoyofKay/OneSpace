import 'package:material_ui/material_ui.dart';

/// R55 (Ahmed, 15 Nov): every "Add new …" / "Edit …" page looks and behaves
/// the same way.
///
/// * Cancel and Save are pinned at the bottom of the page.
/// * Save is enabled only when something changed AND every required field
///   (marked with *) is filled.
/// * Leaving with unsaved changes asks "Discard changes?" first.
class EditorScaffold extends StatelessWidget {
  const EditorScaffold({super.key, required this.title, required this.body,
    required this.isChanged, required this.isComplete, required this.onSave,
    this.listenTo = const [], this.saving = false, this.saveLabel = 'Save', this.isNew = false,
    this.actions = const [], this.missingHint = 'Fill in the fields marked *'});

  final String title;
  final Widget body;
  /// Something differs from what the page opened with.
  final bool Function() isChanged;
  /// Every required (*) field is filled.
  final bool Function() isComplete;
  /// Text fields to watch so Save turns on/off while typing.
  final List<Listenable> listenTo;
  final bool saving;
  /// New items can be saved as soon as required fields are filled (even when
  /// pre-filled); existing ones only once something changed.
  final bool isNew;
  final VoidCallback onSave;
  final String saveLabel;
  final List<Widget> actions;
  final String? missingHint;

  static Future<bool> confirmDiscard(BuildContext context) async =>
      await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('What you changed on this page will not be saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ])) ?? false;

  @override Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge(listenTo),
    builder: (context, _) {
      final theme = Theme.of(context);
      final dirty = isChanged();
      final complete = isComplete();
      final canSave = (isNew || dirty) && complete && !saving;
      return PopScope(
        canPop: !dirty || saving,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await confirmDiscard(context) && context.mounted) Navigator.of(context).pop();
        },
        child: Scaffold(
          appBar: AppBar(title: Text(title), actions: actions),
          body: body,
          bottomNavigationBar: SafeArea(child: Material(
            elevation: 6,
            color: theme.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (missingHint != null && !complete) Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(missingHint!, style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant))),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: saving ? null : () => Navigator.of(context).maybePop(),
                    child: const Text('Cancel'))),
                  const SizedBox(width: 12),
                  Expanded(child: FilledButton(
                    onPressed: canSave ? onSave : null,
                    child: saving
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(saveLabel))),
                ]),
              ]),
            ),
          )),
        ),
      );
    });
}

/// "Title *" for a required field label.
String requiredLabel(String label) => '$label *';

/// Tracks whether a form differs from its starting point. Each editor gives a
/// [signature] of its current values; [mark] records the starting point.
mixin FormChangeTracker<T extends StatefulWidget> on State<T> {
  String? _start;
  /// The current form values in one string.
  String get signature;
  /// Records the current values as the starting point (also after a save).
  void markClean() => _start = signature;
  /// The first call records the starting point, so editors need no setup.
  bool get changed {
    _start ??= signature;
    return signature != _start;
  }
}

/// The add buttons: one pinned button at the lower right of every screen.
class AddFab extends StatelessWidget {
  const AddFab({super.key, required this.label, required this.onPressed, this.heroTag});
  final String label;
  final VoidCallback? onPressed;
  final Object? heroTag;
  @override Widget build(BuildContext context) => FloatingActionButton.extended(
    heroTag: heroTag ?? label,
    onPressed: onPressed,
    icon: const Icon(Icons.add),
    label: Text(label));
}

/// One choice in a fold-up add button.
class AddFabOption {
  const AddFabOption(this.label, this.icon, this.onPressed);
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

/// An add button that folds up a short menu of choices (e.g. Memories:
/// Story journal · Daily selfie · Scrapbook studio).
class AddFabMenu extends StatefulWidget {
  const AddFabMenu({super.key, required this.label, required this.options});
  final String label;
  final List<AddFabOption> options;
  @override State<AddFabMenu> createState() => _AddFabMenuState();
}

class _AddFabMenuState extends State<AddFabMenu> {
  bool open = false;
  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (open) for (final o in widget.options) Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Material(
              elevation: 2, borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.surfaceContainerHigh,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(o.label, style: theme.textTheme.labelLarge))),
            const SizedBox(width: 10),
            FloatingActionButton.small(
              heroTag: 'fab-${o.label}',
              tooltip: o.label,
              onPressed: () { setState(() => open = false); o.onPressed(); },
              child: Icon(o.icon)),
          ])),
        FloatingActionButton.extended(
          heroTag: 'fab-${widget.label}',
          onPressed: () => setState(() => open = !open),
          icon: Icon(open ? Icons.close : Icons.add),
          label: Text(open ? 'Close' : widget.label)),
      ]);
  }
}
