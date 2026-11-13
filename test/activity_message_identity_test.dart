import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/coordinate/activity_message_identity.dart';

void main() {
  const names = {
    'owner':'Ahmed Ismail',
    'other':'Kandice Ismail',
  };

  test('my messages say You, with my initials from my saved full name', () {
    expect(ActivityMessageIdentity.label(
      authorId:'owner',currentUserId:'owner',memberNames:names),'You');
    expect(ActivityMessageIdentity.initials(
      authorId:'owner',currentUserId:'owner',memberNames:names),'AI');
  });
  test('partner shows full name and their initials', () {
    expect(ActivityMessageIdentity.label(
      authorId:'other',currentUserId:'owner',memberNames:names),
      'Kandice Ismail');
    expect(ActivityMessageIdentity.initials(
      authorId:'other',currentUserId:'owner',memberNames:names),'KI');
  });
  test('missing member name never exposes a UUID', () {
    expect(ActivityMessageIdentity.label(
      authorId:'no-name',currentUserId:'owner',memberNames:names),'Partner');
    expect(ActivityMessageIdentity.initials(
      authorId:'no-name',currentUserId:'owner',memberNames:names),'P');
  });
  test('works with one name and whitespace', () {
    expect(ActivityMessageIdentity.initials(
      authorId:'x',currentUserId:'owner',
      memberNames:{'x':'  Mary   Jane  Doe  '}),'MD');
  });
}
