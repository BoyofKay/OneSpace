import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:onespace/l10n/phrases.dart';

/// R68 (Ahmed): a formatting bar for people who are not used to editors.
/// Every button has a word under its icon, the current style is shown as
/// selected, and the less common tools (colours, link, clear) open small,
/// clearly labelled choices instead of tiny icons.
class NoteFormatBar extends StatelessWidget {
  const NoteFormatBar({super.key, required this.controller});
  final quill.QuillController controller;

  static const highlights = <String, String>{
    '#FFF59D': 'Yellow', '#C8E6C9': 'Green', '#BBDEFB': 'Blue', '#F8BBD0': 'Pink',
  };
  static const colours = <String, String>{
    '#C62828': 'Red', '#2E7D32': 'Green', '#1565C0': 'Blue', '#6A1B9A': 'Purple', '#EF6C00': 'Orange',
  };

  bool _has(quill.Attribute a) {
    final value = controller.getSelectionStyle().attributes[a.key]?.value;
    return value != null && value == a.value;
  }

  void _toggle(quill.Attribute a) {
    controller.formatSelection(_has(a) ? quill.Attribute.clone(a, null) : a);
  }

  void _setStyle(String style) {
    controller.formatSelection(quill.Attribute.clone(quill.Attribute.h1, null));
    if (style == 'title') controller.formatSelection(quill.Attribute.h1);
    if (style == 'heading') controller.formatSelection(quill.Attribute.h2);
  }

  String get _style {
    final level = controller.getSelectionStyle().attributes[quill.Attribute.header.key]?.value;
    return level == 1 ? 'title' : level == 2 || level == 3 ? 'heading' : 'normal';
  }

  void _clear() {
    for (final a in [quill.Attribute.bold, quill.Attribute.italic, quill.Attribute.underline,
        quill.Attribute.strikeThrough, quill.Attribute.color, quill.Attribute.background,
        quill.Attribute.link]) {
      controller.formatSelection(quill.Attribute.clone(a, null));
    }
  }

  Future<void> _pickColour(BuildContext context, {required bool highlight}) async {
    final options = highlight ? highlights : colours;
    final picked = await showModalBottomSheet<String>(context: context, showDragHandle: true,
      builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tt(highlight ? 'Highlight the selected text' : 'Colour the selected text'),
            style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final e in options.entries) InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pop(ctx, e.key),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(radius: 22, backgroundColor: Color(int.parse('FF${e.key.substring(1)}', radix: 16)),
                  child: highlight ? null : const Text('A', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                const SizedBox(height: 4),
                Text(tt(e.value), style: Theme.of(ctx).textTheme.labelSmall),
              ])),
            InkWell(borderRadius: BorderRadius.circular(12), onTap: () => Navigator.pop(ctx, ''),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircleAvatar(radius: 22, child: Icon(Icons.format_color_reset_outlined)),
                const SizedBox(height: 4),
                Text(tt('None'), style: Theme.of(ctx).textTheme.labelSmall),
              ])),
          ]),
        ]))));
    if (picked == null) return;
    final a = highlight ? quill.Attribute.background : quill.Attribute.color;
    controller.formatSelection(quill.Attribute.clone(a, picked.isEmpty ? null : picked));
  }

  Future<void> _link(BuildContext context) async {
    final field = TextEditingController(
      text: controller.getSelectionStyle().attributes[quill.Attribute.link.key]?.value?.toString() ?? 'https://');
    final url = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(tt('Add a link')),
      content: TextField(controller: field, autofocus: true, keyboardType: TextInputType.url,
        decoration: InputDecoration(labelText: tt('Web address'), border: const OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tt('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, field.text.trim()), child: Text(tt('Add'))),
      ]));
    field.dispose();
    if (url == null || url.isEmpty || url == 'https://') return;
    final uri = Uri.tryParse(url);
    if (uri == null || !['http', 'https'].contains(uri.scheme)) return;
    final sel = controller.selection;
    if (sel.isCollapsed) {
      controller.replaceText(sel.baseOffset, 0, url, TextSelection(baseOffset: sel.baseOffset,
        extentOffset: sel.baseOffset + url.length));
    }
    controller.formatSelection(quill.LinkAttribute(url));
  }

  Widget _button(BuildContext context, IconData icon, String label, VoidCallback? onTap, {bool on = false}) {
    final colors = Theme.of(context).colorScheme;
    return Padding(padding: const EdgeInsetsDirectional.only(end: 4), child: Material(
      color: on ? colors.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap,
        child: SizedBox(width: 58, height: 54, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 22, color: onTap == null ? colors.outline : on ? colors.onPrimaryContainer : null),
          const SizedBox(height: 2),
          Text(tt(label), maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: on ? colors.onPrimaryContainer : null)),
        ])))));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: controller, builder: (context, _) {
    final theme = Theme.of(context);
    final style = _style;
    return Container(
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant)),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'title', icon: const Icon(Icons.title), label: Text(tt('Title'))),
            ButtonSegment(value: 'heading', icon: const Icon(Icons.text_fields), label: Text(tt('Heading'))),
            ButtonSegment(value: 'normal', icon: const Icon(Icons.notes), label: Text(tt('Text'))),
          ],
          selected: {style},
          onSelectionChanged: (v) => _setStyle(v.first)),
        const SizedBox(height: 6),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          _button(context, Icons.format_bold, 'Bold', () => _toggle(quill.Attribute.bold), on: _has(quill.Attribute.bold)),
          _button(context, Icons.format_italic, 'Italic', () => _toggle(quill.Attribute.italic), on: _has(quill.Attribute.italic)),
          _button(context, Icons.format_underlined, 'Underline', () => _toggle(quill.Attribute.underline),
            on: _has(quill.Attribute.underline)),
          _button(context, Icons.border_color_outlined, 'Highlight', () => _pickColour(context, highlight: true),
            on: controller.getSelectionStyle().attributes.containsKey(quill.Attribute.background.key)),
          _button(context, Icons.format_color_text, 'Colour', () => _pickColour(context, highlight: false),
            on: controller.getSelectionStyle().attributes.containsKey(quill.Attribute.color.key)),
          const SizedBox(height: 40, child: VerticalDivider()),
          _button(context, Icons.format_list_bulleted, 'Bullets', () => _toggle(quill.Attribute.ul), on: _has(quill.Attribute.ul)),
          _button(context, Icons.format_list_numbered, 'Numbers', () => _toggle(quill.Attribute.ol), on: _has(quill.Attribute.ol)),
          _button(context, Icons.checklist, 'Checklist', () => _toggle(quill.Attribute.unchecked),
            on: _has(quill.Attribute.unchecked) || _has(quill.Attribute.checked)),
          _button(context, Icons.format_quote_outlined, 'Quote', () => _toggle(quill.Attribute.blockQuote),
            on: _has(quill.Attribute.blockQuote)),
          const SizedBox(height: 40, child: VerticalDivider()),
          _button(context, Icons.link, 'Link', () => _link(context),
            on: controller.getSelectionStyle().attributes.containsKey(quill.Attribute.link.key)),
          _button(context, Icons.format_clear, 'Clear', _clear),
          _button(context, Icons.undo, 'Undo', controller.hasUndo ? controller.undo : null),
          _button(context, Icons.redo, 'Redo', controller.hasRedo ? controller.redo : null),
        ])),
        Padding(padding: const EdgeInsetsDirectional.only(start: 4, top: 2),
          child: Text(tt('Select words, then tap a style. Lists and headings apply to the whole line.'),
            style: theme.textTheme.bodySmall)),
      ]));
  });
}
