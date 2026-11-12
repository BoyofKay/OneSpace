import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/sharing/object_permissions.dart';

void main() {
  test('A shared object is collaborative', () {
    expect(ObjectPermissions.canEdit(
      visibility: 'shared', createdBy: 'partner', userId: 'me',
    ), isTrue);
  });
  test('A private object shared for viewing is not editable', () {
    expect(ObjectPermissions.isViewOnly(
      visibility: 'private', createdBy: 'partner', userId: 'me',
    ), isTrue);
    expect(ObjectPermissions.canEdit(
      visibility: 'private', createdBy: 'partner', userId: 'me',
    ), isFalse);
    expect(ObjectPermissions.canManagePrivateShare(
      visibility: 'private', createdBy: 'partner', userId: 'me',
    ), isFalse);
  });
  test('Only private owner controls sharing', () {
    expect(ObjectPermissions.canManagePrivateShare(
      visibility: 'private', createdBy: 'me', userId: 'me',
    ), isTrue);
    expect(ObjectPermissions.canManagePrivateShare(
      visibility: 'shared', createdBy: 'me', userId: 'me',
    ), isFalse);
  });
}
