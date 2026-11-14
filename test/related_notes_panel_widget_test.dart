import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/features/notes/related_notes_panel.dart';

void main(){
 testWidgets('collapsed related notes is safe without backend initialization',
  (tester)async{
  await tester.pumpWidget(const MaterialApp(home:Scaffold(
   body:RelatedNotesPanel(sourceKind:'task',sourceId:'sample'),
  )));
  expect(find.text('Related notes'),findsOneWidget);
  expect(tester.takeException(),isNull);
 });
}
