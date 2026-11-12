import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/home_member_names.dart';

void main() {
  test('Home member identities are mapped by exact user ID', () {
    final names = HomeMemberNames.parse([
      {'user_id': 'person-a', 'name': 'Alice', 'is_me': true},
      {'user_id': 'person-b', 'name': 'Bob', 'is_me': false},
    ]);
    expect(names, {'person-a': 'Alice', 'person-b': 'Bob'});
    expect(() => names!['person-a'] = 'Another name', throwsUnsupportedError);
  });

  test('older server response safely falls back to profile lookup', () {
    expect(HomeMemberNames.parse([
      {'name': 'Alice', 'is_me': true},
    ]), isNull);
    expect(HomeMemberNames.parse(null), isNull);
    expect(HomeMemberNames.parse({}), isNull);
  });

  test('ignores malformed IDs and substitutes blank labels', () {
    expect(HomeMemberNames.parse([
      null, 7, {'user_id': null, 'name': 'Ignored'},
      {'user_id': '', 'name': 'Ignored'},
      {'user_id': 'person-a', 'name': '  '},
    ]), {'person-a': 'Member'});
  });
}
