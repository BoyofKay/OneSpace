import 'package:material_ui/material_ui.dart';
import 'package:onespace/l10n/phrases.dart';

/// QA lifecycle: explicit consent UI, not an active relationship-delete action.
/// MySpace keeps destructive CTAs disabled until the server endpoint, physical
/// Storage purge and two-phone isolation tests are fully verified.
enum RelationshipExitAction { removePartner, leaveSpace, deleteSpace }

class RelationshipExitConfirmation extends StatefulWidget {
  const RelationshipExitConfirmation({
    super.key,
    required this.action,
    this.spaceName,
    this.members = const [],
  });

  final RelationshipExitAction action;
  final String? spaceName;
  final List<String> members;
  static const requiredPhrase = 'DELETE SHARED CONTENT';

  static Future<bool> ask(
    BuildContext context, {
    required RelationshipExitAction action,
    String? spaceName,
    List<String> members = const [],
  }) async {
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RelationshipExitConfirmation(
        action: action, spaceName: spaceName, members: members),
    );
    return approved == true;
  }

  @override
  State<RelationshipExitConfirmation> createState() =>
      _RelationshipExitConfirmationState();
}

class _RelationshipExitConfirmationState
    extends State<RelationshipExitConfirmation> {
  final TextEditingController _confirmation = TextEditingController();

  bool get _matches =>
      _confirmation.text == RelationshipExitConfirmation.requiredPhrase;

  String get _title => switch (widget.action) {
        RelationshipExitAction.removePartner => 'Remove your partner?',
        RelationshipExitAction.leaveSpace => 'Leave your shared space?',
        RelationshipExitAction.deleteSpace => 'Delete your shared space?',
      };

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(scrollable:true,
      title: Text(tt(_title)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.spaceName != null) ...[
              Text(widget.members.isEmpty ? widget.spaceName!
                : '${widget.spaceName!}: ${widget.members.join(' · ')}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
            ],
            Text(tt('This action permanently ends your current shared space. '
              'All content belonging to this relationship, including shared '
              'memories, activities, photos and messages, is permanently erased. '
              'Neither person can recover it in OneSpace.')),
            const SizedBox(height: 12),
            Text(tt('Both people keep their own private Notes, Tasks, Memories, '
              'photos and other account-owned information. Your private data '
              'will never be given to a future partner.')),
            const SizedBox(height: 12),
            Text(tt('No automatic archive, export or restore is created. '
              'Once completed, this decision cannot be reversed.')),
            const SizedBox(height: 16),
            Text(tt('To confirm, enter the exact phrase:')),
            const SizedBox(height: 6),
            const SelectableText(
              RelationshipExitConfirmation.requiredPhrase,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('relationshipDeleteConfirmationPhrase'),
              controller: _confirmation,
              maxLength: 64,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: tt('Confirmation phrase'),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('relationshipDeleteCancel'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(tt('Cancel')),
        ),
        FilledButton(
          key: const Key('relationshipDeleteConfirm'),
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          child: Text(tt('Delete shared content permanently')),
        ),
      ],
    );
  }
}
