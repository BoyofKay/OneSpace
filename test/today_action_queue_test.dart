import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/spaces/today_attention_rules.dart';

void main(){
  test('Prioritizes overdue, due today, direct request, tomorrow, urgent',(){
    final items=TodayAttentionItem.fromActionQueue([
      {'id':'urgent','source':'activity','activity_id':'urgent','score':4,
       'priority':'urgent','title':'Urgent unscheduled'},
      {'id':'tomorrow','source':'task','score':3,'title':'Tomorrow',
       'due_on':'2026-11-14'},
      {'id':'checkin','source':'checkin','score':2,'title':'Partner check-in'},
      {'id':'today','source':'task','score':1,'title':'Due today'},
      {'id':'overdue','source':'activity','activity_id':'overdue',
       'score':0,'title':'Overdue'},
    ]);
    expect(items.map((item)=>item.id).toList(),
      ['overdue','today','checkin','tomorrow','urgent']);
  });
  test('Related Activity reminders and mentions deduplicate',(){
    final items=TodayAttentionItem.fromActionQueue([
      {'id':'a','source':'activity','activity_id':'a','score':5,'title':'Research'},
      {'id':'a','source':'activity','activity_id':'a','score':2,
       'title':'Partner mentioned you','reason':'Direct request'},
      {'id':'a','source':'task','score':1,'title':'Different task'},
    ]);
    expect(items.length,2);
    expect(items.first.source,'task');
    expect(items.last.reason,'Direct request');
  });
  test('Rejects malformed sources and sorts calendar dates without UTC',(){
    final items=TodayAttentionItem.fromActionQueue([
      {'id':'x','source':'unknown','title':'Invalid'},
      {'id':'','source':'task','title':'Blank'},
      {'id':'b','source':'task','score':0,'due_on':'2026-11-12',
       'title':'Later'},
      {'id':'a','source':'task','score':0,'due_on':'2026-11-10',
       'title':'Earlier'},
    ]);
    expect(items.length,2);
    expect(items.first.id,'a');
    expect(items.last.id,'b');
  });
}
