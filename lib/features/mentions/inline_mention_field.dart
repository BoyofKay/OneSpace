import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onespace/l10n/phrases.dart';

/// R76 (Ahmed): mentions built into the text box, like the Activity chat —
/// type "@" and your partner's name appears above the box; tap it to insert
/// "@Full Name " exactly as the database mention trigger expects.
class InlineMentionField extends StatefulWidget {
  const InlineMentionField({super.key, required this.spaceId, required this.controller,
    this.focusNode, this.hintText, this.maxLength = 2000, this.minLines = 1, this.maxLines = 4});
  final String? spaceId;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hintText;
  final int maxLength, minLines, maxLines;
  @override
  State<InlineMentionField> createState() => _InlineMentionFieldState();
}

class _InlineMentionFieldState extends State<InlineMentionField> {
  String? partner;
  String? suggestion;
  int offset = -1;
  late final FocusNode focus = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    if (widget.focusNode == null) focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final space = widget.spaceId;
    if (space == null || space.isEmpty) return;
    final client = Supabase.instance.client, me = client.auth.currentUser?.id;
    if (me == null) return;
    try {
      final rows = await client.from('space_members').select('user_id').eq('space_id', space);
      final other = rows.where((m) => m['user_id'] != me).firstOrNull;
      if (other == null) return;
      final profile = await client.from('profiles').select('display_name').eq('id', other['user_id']).single();
      if (mounted) setState(() => partner = profile['display_name']?.toString().trim());
    } catch (_) {}
  }

  /// Suggest only when "@" starts a word — never inside an email address.
  void _changed() {
    final c = widget.controller;
    final text = c.text;
    final caret = c.selection.isValid ? c.selection.baseOffset.clamp(0, text.length) : text.length;
    final hit = RegExp(r'(^|\s)@([^\s@]*)$').firstMatch(text.substring(0, caret));
    final name = partner;
    final partial = hit?.group(2) ?? '';
    final show = hit != null && name != null && name.isNotEmpty &&
      name.toLowerCase().startsWith(partial.toLowerCase());
    final at = show ? caret - partial.length - 1 : -1;
    if (suggestion != (show ? name : null) || offset != at) {
      setState(() { suggestion = show ? name : null; offset = at; });
    }
  }

  void _accept() {
    final name = suggestion;
    if (name == null || offset < 0) return;
    final c = widget.controller;
    final caret = c.selection.isValid ? c.selection.baseOffset : c.text.length;
    final end = caret.clamp(offset, c.text.length);
    final insertion = '@$name ';
    c.value = TextEditingValue(text: c.text.replaceRange(offset, end, insertion),
      selection: TextSelection.collapsed(offset: offset + insertion.length));
    setState(() { suggestion = null; offset = -1; });
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (suggestion != null) Padding(padding: const EdgeInsets.only(bottom: 4),
        child: ActionChip(avatar: const Icon(Icons.alternate_email, size: 18),
          label: Text(suggestion!), onPressed: _accept)),
      TextField(controller: widget.controller, focusNode: focus,
        minLines: widget.minLines, maxLines: widget.maxLines, maxLength: widget.maxLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: widget.hintText ?? tt('Message… type @ to mention'),
          isDense: true, counterText: '',
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: const OutlineInputBorder())),
    ]);
}
