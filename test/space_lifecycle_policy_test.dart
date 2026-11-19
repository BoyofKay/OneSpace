import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/spaces/space_lifecycle_policy.dart';

void main() {
  test('creator cannot leave or transfer via invited partner action', () {
    expect(SpaceLifecyclePolicy.evaluate(
      action:SpaceLifecycleAction.invitedPartnerLeaves,
      actor:SpaceLifecycleRole.owner), isNull);
  });
  test('invited B leaving retires old relationship and A continues seamlessly', () {
    final o = SpaceLifecyclePolicy.evaluate(
      action:SpaceLifecycleAction.invitedPartnerLeaves,
      actor:SpaceLifecycleRole.invitedPartner)!;
    expect(o.retireOldRelationship,true);
    expect(o.ownerKeepsContinuousSpace,true);
    expect(o.invitedPartnerBecomesUnpaired,true);
    expect(o.exportForBoth,true);
  });
  test('owner removes B, A keeps clean continuous space', () {
    final o=SpaceLifecyclePolicy.evaluate(
      action:SpaceLifecycleAction.ownerRemovesPartner,
      actor:SpaceLifecycleRole.owner)!;
    expect(o.ownerKeepsContinuousSpace,true);
    expect(o.retireOldRelationship,true);
  });
  test('deleting space does not recreate owner space automatically', () {
    final o=SpaceLifecyclePolicy.evaluate(
      action:SpaceLifecycleAction.ownerDeletesSpace,
      actor:SpaceLifecycleRole.owner)!;
    expect(o.ownerKeepsContinuousSpace,false);
    expect(o.ownerKeepsAccount,true);
  });
  test('owner account deletion includes shared-space closure', () {
    final o=SpaceLifecyclePolicy.evaluate(
      action:SpaceLifecycleAction.ownerDeletesAccount,
      actor:SpaceLifecycleRole.owner)!;
    expect(o.ownerAccountDeletionRequested,true);
    expect(o.retireOldRelationship,true);
    expect(o.exportForBoth,true);
  });
  test('invited partner account deletion keeps owner space', () {
    final o=SpaceLifecyclePolicy.evaluate(
      action:SpaceLifecycleAction.invitedPartnerDeletesAccount,
      actor:SpaceLifecycleRole.invitedPartner)!;
    expect(o.ownerKeepsContinuousSpace,true);
    expect(o.invitedAccountDeletionRequested,true);
  });
  test('unprivileged roles cannot remove or delete owner space', () {
    expect(SpaceLifecyclePolicy.evaluate(
      action:SpaceLifecycleAction.ownerDeletesSpace,
      actor:SpaceLifecycleRole.invitedPartner),isNull);
    expect(SpaceLifecyclePolicy.evaluate(
      action:SpaceLifecycleAction.ownerRemovesPartner,
      actor:SpaceLifecycleRole.invitedPartner),isNull);
  });
}
