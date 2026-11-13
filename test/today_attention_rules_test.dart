import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/spaces/today_attention_rules.dart';

void main() {
  final today = DateTime(2026, 11, 13);

  test('overdue reminders beat urgent items without deadlines', () {
    final items = TodayAttentionItem.parse([
      {'id':'high','activity_id':'high','title':'Compare heater',
        'kind':'activity','priority':'urgent'},
      {'id':'later','activity_id':'later','title':'Gymnastics',
        'kind':'activity','priority':'normal','due_on':'2026-11-17'},
      {'id':'reminder','activity_id':'parent','title':'Email the school',
        'kind':'reminder','priority':'normal','due_on':'2026-11-12'},
      {'id':'today','activity_id':'today','title':'Visit the school',
        'kind':'activity','priority':'normal','due_on':'2026-11-13'},
    ],today);
    expect(items.map((e)=>e.id).toList(),
      ['reminder','today','high','later']);
    expect(items.first.relativeLabel(today),'Overdue by 1 day');
    expect(items[1].relativeLabel(today),'Due today');
    expect(items[2].relativeLabel(today),'Urgent · no due date');
    expect(items[3].relativeLabel(today),'Due in 4 days');
    expect(items.first.activityId,'parent');
  });

  test('invalid rows are ignored and missing dates never turn overdue', () {
    final result=TodayAttentionItem.parse([
      null,42,{}, {'id':'i','activity_id':'a','title':'Follow up',
        'priority':'high','kind':'reminder','due_on':'invalid'},
    ],today);
    expect(result.length,1);
    expect(result.single.daysUntil(today),isNull);
  });

  test('annual occasion recurs on the next valid local calendar date', () {
    final entries=TodayAttentionItem.upcomingEvents([
      {'title':'Anniversary','event_date':'2019-11-16',
        'recurrence':'yearly','kind':'occasion'},
      {'title':'Past meeting','event_date':'2026-11-01','recurrence':'none'},
      {'title':'Soon','event_date':'2026-11-14','recurrence':'none'},
      {'title':'Later','event_date':'2026-12-20','recurrence':'none'},
    ],today);
    expect(entries.map((e)=>e.title).toList(),['Soon','Anniversary']);
    expect(entries.last.date,DateTime(2026,11,16));
  });

  test('leap day anniversaries do not invent February 29', () {
    final entries=TodayAttentionItem.upcomingEvents([
      {'title':'Leap occasion','event_date':'2024-02-29',
        'recurrence':'yearly','kind':'occasion'},
    ],DateTime(2027,2,25),horizonDays:500);
    expect(entries.single.date,DateTime(2028,2,29));
  });
}
