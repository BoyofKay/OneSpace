import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/contacts/contact_card_entry.dart';

void main() {
  final gym = ContactCardEntry.fromRow({
    'id':'first',
    'activity_id':'gymnastics',
    'label':'Gym B admissions',
    'activities':{'title':'Find gymnastics for our baby'},
    'payload':{
      'contact_name':'Sarah',
      'phone':'+1 610 555 0147',
      'email':'gym@example.com',
      'address':'Pennsylvania',
      'working_hours':'Saturday 9–1',
    },
  });
  final heater = ContactCardEntry.fromRow({
    'id':'second',
    'activity_id':'heater',
    'label':'Heater supplier',
    'activities':{'title':'Find bedroom heater'},
    'payload':{'phone':'+1 215 555 0112'},
  });

  test('World contacts are references to the original Activity', () {
    expect(gym.activityId,'gymnastics');
    expect(gym.activityTitle,'Find gymnastics for our baby');
    expect(gym.contact.person,'Sarah');
  });

  test('contacts are searchable by person, provider, phone and hours', () {
    final all=[heater,gym];
    expect(ContactCardEntry.filtered(all,'sarah'),[gym]);
    expect(ContactCardEntry.filtered(all,'GYMNASTICS'),[gym]);
    expect(ContactCardEntry.filtered(all,'Saturday'),[gym]);
    expect(ContactCardEntry.filtered(all,'+1 215'),[heater]);
    expect(ContactCardEntry.filtered(all,'nothing'),isEmpty);
  });

  test('blank search sorts contacts without modifying originals', () {
    final records=[heater,gym];
    final sorted=ContactCardEntry.filtered(records,'');
    expect(sorted.map((e)=>e.label).toList(),[
      'Gym B admissions','Heater supplier',
    ]);
    expect(records.first,heater);
  });

  test('missing properties cannot create fake contact details', () {
    final blank=ContactCardEntry.fromRow({'id':'blank'});
    expect(blank.contact.hasDetails,isFalse);
    expect(blank.activityTitle,'Activity');
    expect(blank.label,'Contact');
  });
}
