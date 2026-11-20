import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/features/spaces/relationship_exit_confirmation.dart';

void main() {
  testWidgets('Delete shared content requires exact typed irreversible phrase',
      (tester) async {
    bool? approved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => FilledButton(
        onPressed: () async {
          approved = await RelationshipExitConfirmation.ask(
            context, action: RelationshipExitAction.deleteSpace);
        },
        child: const Text('Review deletion'),
      ))),
    ));
    await tester.tap(find.text('Review deletion'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Both people keep their own private'),
      findsOneWidget);
    expect(find.textContaining('No automatic archive'), findsOneWidget);
    final confirm = find.byKey(const Key('relationshipDeleteConfirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('relationshipDeleteConfirmationPhrase')),
      'delete shared content');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('relationshipDeleteConfirmationPhrase')),
      RelationshipExitConfirmation.requiredPhrase);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(approved, isTrue);
  });

  testWidgets('Cancelling requires no phrase and never confirms destructive action',
      (tester) async {
    bool? approved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => FilledButton(
        onPressed: () async {
          approved = await RelationshipExitConfirmation.ask(
            context, action: RelationshipExitAction.leaveSpace);
        },
        child: const Text('Review leaving'),
      ))),
    ));
    await tester.tap(find.text('Review leaving'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('relationshipDeleteCancel')));
    await tester.pumpAndSettle();
    expect(approved, isFalse);
    expect(find.text('Leave your shared space?'), findsNothing);
  });
}
