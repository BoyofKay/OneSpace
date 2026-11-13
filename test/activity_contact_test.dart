import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/coordinate/activity_contact.dart';

void main() {
  test('contact details can represent a gymnastics registration office', () {
    final item = ActivityContact.fromPayload({
      'contact_name': 'Maya / Registration',
      'phone': '+1 (610) 555-0147',
      'email': 'classes@example.com',
      'address': '100 Main Street, Pennsylvania, USA',
      'working_hours': 'Monday–Friday 9am–5pm',
      'note': 'Ask about swimming and ages 2–4',
    });
    expect(item.validate(), isNull);
    expect(item.dialableNumber, '+16105550147');
    expect(item.phoneUri?.scheme, 'tel');
    expect(item.emailUri?.scheme, 'mailto');
    expect(item.mapUri?.queryParameters['query'],
      '100 Main Street, Pennsylvania, USA');
    expect(item.summary, contains('Hours: Monday–Friday 9am–5pm'));
    expect(item.toPayload()['contact_name'], 'Maya / Registration');
  });

  test('contact may include only a phone or only working hours', () {
    expect(const ActivityContact(phone: '+966 11 234 5678').validate(), isNull);
    expect(const ActivityContact(workingHours: 'By appointment').validate(), isNull);
    expect(const ActivityContact().validate(), isNotNull);
  });

  test('bad numbers and email are rejected before opening external apps', () {
    const item = ActivityContact(phone: 'call me sometime',email: 'wrong@@example');
    expect(item.validate(), contains('telephone'));
    expect(item.phoneUri, isNull);
    expect(item.emailUri, isNull);
    expect(const ActivityContact(email: 'wrong').validate(), contains('email'));
  });

  test('malicious long input and delimiters cannot be used as a phone', () {
    const item = ActivityContact(phone: '+1 555; rm -rf /');
    expect(item.validPhone, isFalse);
    expect(item.phoneUri, isNull);
    expect(ActivityContact(person: List.filled(181, 'A').join()).validate(), contains('too long'));
  });

  test('editing contact preserves unknown fields and note', () {
    const updated = ActivityContact(person: 'Office', note: 'Call first');
    final payload = updated.toPayload(original: {
      'custom_field': 'keep',
      'contact_name': 'old',
    });
    expect(payload['custom_field'], 'keep');
    expect(payload['contact_name'], 'Office');
    expect(payload['note'], 'Call first');
  });

  test('blank contact does not create actionable links or invented hours', () {
    const item = ActivityContact();
    expect(item.phoneUri, isNull);
    expect(item.emailUri, isNull);
    expect(item.mapUri, isNull);
    expect(item.summary, isEmpty);
  });
}
