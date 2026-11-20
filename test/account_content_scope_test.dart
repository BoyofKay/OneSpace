import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/account_content_scope.dart';
import 'package:onespace/features/coordinate/new_activity_screen.dart';

void main() {
  test('a solo QA person can save only to their own private namespace', () {
    const scopes = AccountContentScope(
      accountOwned: true, privateSpaceId: 'account-a', sharedSpaceId: null);
    expect(scopes.canCreatePrivate, isTrue);
    expect(scopes.canCreateShared, isFalse);
    expect(scopes.fieldsForNew(shared: false), {
      'private_space_id': 'account-a', 'visibility': 'private',
    });
    expect(() => scopes.fieldsForNew(shared: true), throwsStateError);
  });

  test('new QA Activities never mix private and relationship IDs', () {
    const scopes = AccountContentScope(
      accountOwned: true, privateSpaceId: 'account-a', sharedSpaceId: 'pair-ab');
    final mine = const NewActivityDraft(title: 'My note', shared: false)
        .toScopedInsert(scopes);
    final ours = const NewActivityDraft(title: 'Our idea', shared: true)
        .toScopedInsert(scopes);
    expect(mine['space_id'], isNull);
    expect(mine['private_space_id'], 'account-a');
    expect(mine['visibility'], 'private');
    expect(ours['private_space_id'], isNull);
    expect(ours['space_id'], 'pair-ab');
    expect(ours['visibility'], 'shared');
  });

  test('private activity cannot assign another person', () {
    const scopes = AccountContentScope(
      accountOwned: true, privateSpaceId: 'a', sharedSpaceId: 'pair');
    final privateRecord = const NewActivityDraft(
      title: 'To myself', shared: false, forUserId: 'partner')
        .toScopedInsert(scopes);
    expect(privateRecord.containsKey('for_user_id'), isFalse);
  });

  test('production keeps legacy routing until its own approved cutover', () {
    const scopes = AccountContentScope(
      accountOwned: false, sharedSpaceId: 'old-space');
    expect(scopes.fieldsForNew(shared: false), {
      'space_id': 'old-space', 'visibility': 'private',
    });
    expect(scopes.fieldsForNew(shared: true), {
      'space_id': 'old-space', 'visibility': 'shared',
    });
  });

  test('missing private namespace fails closed', () {
    const scopes = AccountContentScope(
      accountOwned: true, sharedSpaceId: 'pair-ab');
    expect(() => scopes.fieldsForNew(shared: false), throwsStateError);
  });
}
