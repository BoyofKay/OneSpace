import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/features/plans/task_editor_sheet.dart';

void main() {
  testWidgets('Creating a list on its page saves its items and closes',
      (tester) async {
    TaskDraft? saved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => FilledButton(
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (_) => TaskEditorSheet(
              members: const {'my-user': 'Me', 'partner-user': 'Partner'},
              currentUserId: 'my-user',
              onSave: (draft) async { saved = draft; },
            ),
          )),
          child: const Text('Open task editor'),
        )),
      ),
    ));
    await tester.tap(find.text('Open task editor'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('taskTitleInput')), findsOneWidget);
    // Save stays off until the required name is filled.
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('taskTitleInput')),
        'Book weekend travel');
    await tester.enterText(find.widgetWithText(TextField, "What's on the list?"),
        'Passports\nTickets\n\n');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(saved?.title, 'Book weekend travel');
    expect(saved?.items, ['Passports', 'Tickets']);
    expect(saved?.visibility, TaskVisibility.shared);
    expect(find.byKey(const Key('taskTitleInput')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Editing with a missing previous assignee does not crash',
      (tester) async {
    TaskDraft? saved;
    const task = SharedTask(
      id: 'task-123',
      title: 'Older task',
      priority: TaskPriority.high,
      status: TaskStatus.open,
      visibility: TaskVisibility.shared,
      createdBy: 'my-user',
      assignedTo: 'former-member',
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => FilledButton(
        onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
          builder: (_) => TaskEditorSheet(
            existing: task,
            members: const {'my-user': 'Me', 'partner-user': 'Partner'},
            currentUserId: 'my-user',
            onSave: (draft) async { saved = draft; },
          ),
        )),
        child: const Text('Edit task'),
      ))),
    ));
    await tester.tap(find.text('Edit task'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('taskTitleInput')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('taskTitleInput')),
        'Updated task');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(saved?.title, 'Updated task');
    expect(saved?.assignedTo, isNull);
    expect(tester.takeException(), isNull);
  });

  test('Private task payload never contains another assignee', () {
    const draft = TaskDraft(
      title: 'Private reminder',
      priority: TaskPriority.normal,
      visibility: TaskVisibility.private,
      assignedTo: 'partner-user',
    );
    expect(draft.toEditableFields()['assigned_to'], isNull);
  });
}
