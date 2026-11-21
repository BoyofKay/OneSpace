import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/features/calendar/couple_day_view.dart';

void main() {
  final day = DateTime.now();
  const a = CouplePerson(id: 'a', first: 'Amr', zone: 'Asia/Riyadh', workDays: {1, 2, 3, 4, 5, 6, 7},
    workStart: TimeOfDay(hour: 9, minute: 0), workEnd: TimeOfDay(hour: 17, minute: 0),
    sleepStart: TimeOfDay(hour: 23, minute: 0), sleepEnd: TimeOfDay(hour: 7, minute: 0));
  const b = CouplePerson(id: 'b', first: 'Sara', zone: 'Europe/London', workDays: {1, 2, 3, 4, 5, 6, 7},
    workStart: TimeOfDay(hour: 9, minute: 0), workEnd: TimeOfDay(hour: 17, minute: 0),
    sleepStart: TimeOfDay(hour: 22, minute: 30), sleepEnd: TimeOfDay(hour: 6, minute: 30));

  testWidgets('split day timeline renders both partners, events and markers', (t) async {
    final start = DateTime(day.year, day.month, day.day, 10).toUtc().toIso8601String();
    final end = DateTime(day.year, day.month, day.day, 11).toUtc().toIso8601String();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Column(children: [
      CoupleDayMarkers(people: const [a, b], day: day, daysOff: [
        {'user_id': 'b', 'off_date': '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}'}]),
      CoupleDayTimeline(people: const [a, b], day: day, daysOff: const [], myId: 'a', onOpen: (_) {},
        timed: [
          {'title': 'Dinner call', 'visibility': 'shared', 'starts_at': start, 'ends_at': end},
          {'title': 'Gym', 'visibility': 'private', 'created_by': 'a', 'for_user_id': 'a', 'starts_at': start, 'ends_at': end},
        ]),
    ])))));
    await t.pumpAndSettle();
    expect(find.text('Amr'), findsNWidgets(4)); // header + repeated every 6 hours
    expect(find.text('Sara'), findsNWidgets(4));
    expect(find.textContaining('Dinner call'), findsOneWidget);
    expect(find.textContaining('Gym'), findsOneWidget);
    expect(find.text('A', skipOffstage: false), findsOneWidget);
    expect(find.text('S', skipOffstage: false), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
