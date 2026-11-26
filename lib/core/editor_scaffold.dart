import 'package:material_ui/material_ui.dart';
import 'package:onespace/l10n/phrases.dart';

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
    this.actions = const [], this.missingHint = 'Fill in the fields marked *', this.meta});

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
  /// R57: the fixed Shared · Belongs to · Date strip, shown right above
  /// Cancel/Save (see form_kit.dart).
  final Widget? meta;

  static Future<bool> confirmDiscard(BuildContext context) async =>
      await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(scrollable:true,
        title: Text(tt('Discard changes?')),
        content: Text(tt('What you changed on this page will not be saved.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tt('Keep editing'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tt('Discard'))),
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
          appBar: AppBar(title: Text(tt(title)), actions: actions),
          body: body,
          bottomNavigationBar: SafeArea(child: Material(
            elevation: 6,
            color: theme.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (meta != null) Align(alignment: AlignmentDirectional.centerStart, child: meta!),
                if (missingHint != null && !complete) Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(tt(missingHint!), style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant))),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: saving ? null : () => Navigator.of(context).maybePop(),
                    child: Text(tt('Cancel')))),
                  const SizedBox(width: 12),
                  Expanded(child: FilledButton(
                    onPressed: canSave ? onSave : null,
                    child: saving
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(tt(saveLabel)))),
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
    label: Text(tt(label)));
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
                child: Text(tt(o.label), style: theme.textTheme.labelLarge))),
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
          label: Text(tt(open ? 'Close' : widget.label))),
      ]);
  }
}

/// One text field on a [FormPage].
class FormFieldSpec {
  const FormFieldSpec(this.label, {this.initial = '', this.required = false,
    this.maxLength = 500, this.lines = 1, this.hint, this.keyboard});
  final String label, initial;
  final bool required;
  final int maxLength, lines;
  final String? hint;
  final TextInputType? keyboard;
}

/// R56: a small full-page form for edits that used to be pop-ups.
/// Returns the trimmed values in field order, or null on Cancel/back.
Future<List<String>?> showFormPage(BuildContext context, {required String title,
    required List<FormFieldSpec> fields, String saveLabel = 'Save', String? intro,
    bool isNew = false}) =>
  Navigator.of(context).push<List<String>>(MaterialPageRoute<List<String>>(
    builder: (_) => _FormPage(title: title, fields: fields, saveLabel: saveLabel,
      intro: intro, isNew: isNew)));

class _FormPage extends StatefulWidget {
  const _FormPage({required this.title, required this.fields, required this.saveLabel,
    this.intro, this.isNew = false});
  final String title, saveLabel;
  final String? intro;
  final bool isNew;
  final List<FormFieldSpec> fields;
  @override
  State<_FormPage> createState() => _FormPageState();
}

class _FormPageState extends State<_FormPage> {
  late final controllers = [for (final f in widget.fields) TextEditingController(text: f.initial)];

  @override
  void dispose() {
    for (final c in controllers) { c.dispose(); }
    super.dispose();
  }

  bool get _changed {
    for (var i = 0; i < controllers.length; i++) {
      if (controllers[i].text != widget.fields[i].initial) return true;
    }
    return false;
  }

  bool get _complete {
    for (var i = 0; i < controllers.length; i++) {
      if (widget.fields[i].required && controllers[i].text.trim().isEmpty) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => EditorScaffold(
    title: widget.title,
    isNew: widget.isNew,
    isChanged: () => _changed,
    isComplete: () => _complete,
    listenTo: controllers,
    saveLabel: widget.saveLabel,
    missingHint: widget.fields.any((f) => f.required) ? 'Fill in the fields marked *' : null,
    onSave: () => Navigator.pop(context, [for (final c in controllers) c.text.trim()]),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      if (widget.intro != null) Padding(padding: const EdgeInsets.only(bottom: 14),
        child: Text(tt(widget.intro!), style: Theme.of(context).textTheme.bodyMedium)),
      for (var i = 0; i < widget.fields.length; i++) Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: TextField(
          controller: controllers[i],
          autofocus: i == 0,
          maxLength: widget.fields[i].maxLength,
          minLines: widget.fields[i].lines,
          maxLines: widget.fields[i].lines == 1 ? 1 : widget.fields[i].lines + 6,
          keyboardType: widget.fields[i].keyboard,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: widget.fields[i].required ? requiredLabel(widget.fields[i].label)
                : widget.fields[i].label,
            hintText: widget.fields[i].hint,
            alignLabelWithHint: widget.fields[i].lines > 1,
            border: const OutlineInputBorder()))),
    ]));
}

/// R56: a page drop-in for an old AlertDialog editor (same title/content/
/// actions), so the form logic is unchanged but it opens as a subpage with
/// its buttons pinned at the bottom.
class EditorPage extends StatelessWidget {
  const EditorPage({super.key, required this.title, required this.content,
    this.actions = const []});
  final Widget title;
  final Widget content;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: title),
    body: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 12, 18, 24), child: content)),
    bottomNavigationBar: SafeArea(child: Container(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
      child: Row(children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: actions[i]),
        ],
      ]))),
  );
}
