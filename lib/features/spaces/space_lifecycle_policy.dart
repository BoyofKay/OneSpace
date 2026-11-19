/// Agreed OneSpace membership lifecycle. Describes outcomes; it does NOT
/// authorize destructive database mutations. Server export/verification
/// is always a prerequisite before these outcomes can be committed.
enum SpaceLifecycleAction {
  invitedPartnerLeaves,
  ownerRemovesPartner,
  ownerDeletesSpace,
  ownerDeletesAccount,
  invitedPartnerDeletesAccount,
}
enum SpaceLifecycleRole { owner, invitedPartner }
class SpaceLifecycleOutcome {
  const SpaceLifecycleOutcome({
    required this.ownerKeepsAccount,
    required this.ownerKeepsContinuousSpace,
    required this.invitedPartnerKeepsAccount,
    required this.invitedPartnerBecomesUnpaired,
    required this.retireOldRelationship,
    required this.exportForBoth,
    required this.ownerAccountDeletionRequested,
    required this.invitedAccountDeletionRequested,
  });
  final bool ownerKeepsAccount;
  final bool ownerKeepsContinuousSpace;
  final bool invitedPartnerKeepsAccount;
  final bool invitedPartnerBecomesUnpaired;
  final bool retireOldRelationship;
  final bool exportForBoth;
  final bool ownerAccountDeletionRequested;
  final bool invitedAccountDeletionRequested;
}
class SpaceLifecyclePolicy {
  const SpaceLifecyclePolicy._();

  static SpaceLifecycleOutcome? evaluate({
    required SpaceLifecycleAction action,
    required SpaceLifecycleRole actor,
  }) {
    final owner = actor == SpaceLifecycleRole.owner;
    switch (action) {
      case SpaceLifecycleAction.invitedPartnerLeaves:
        if (owner) return null; // Creator cannot leave their own space.
        return const SpaceLifecycleOutcome(
          ownerKeepsAccount: true,
          ownerKeepsContinuousSpace: true,
          invitedPartnerKeepsAccount: true,
          invitedPartnerBecomesUnpaired: true,
          retireOldRelationship: true,
          exportForBoth: true,
          ownerAccountDeletionRequested: false,
          invitedAccountDeletionRequested: false,
        );
      case SpaceLifecycleAction.ownerRemovesPartner:
        if (!owner) return null;
        return const SpaceLifecycleOutcome(
          ownerKeepsAccount: true,
          ownerKeepsContinuousSpace: true,
          invitedPartnerKeepsAccount: true,
          invitedPartnerBecomesUnpaired: true,
          retireOldRelationship: true,
          exportForBoth: true,
          ownerAccountDeletionRequested: false,
          invitedAccountDeletionRequested: false,
        );
      case SpaceLifecycleAction.ownerDeletesSpace:
        if (!owner) return null;
        return const SpaceLifecycleOutcome(
          ownerKeepsAccount: true,
          ownerKeepsContinuousSpace: false,
          invitedPartnerKeepsAccount: true,
          invitedPartnerBecomesUnpaired: true,
          retireOldRelationship: true,
          exportForBoth: true,
          ownerAccountDeletionRequested: false,
          invitedAccountDeletionRequested: false,
        );
      case SpaceLifecycleAction.ownerDeletesAccount:
        if (!owner) return null;
        return const SpaceLifecycleOutcome(
          ownerKeepsAccount: false,
          ownerKeepsContinuousSpace: false,
          invitedPartnerKeepsAccount: true,
          invitedPartnerBecomesUnpaired: true,
          retireOldRelationship: true,
          exportForBoth: true,
          ownerAccountDeletionRequested: true,
          invitedAccountDeletionRequested: false,
        );
      case SpaceLifecycleAction.invitedPartnerDeletesAccount:
        if (owner) return null;
        return const SpaceLifecycleOutcome(
          ownerKeepsAccount: true,
          ownerKeepsContinuousSpace: true,
          invitedPartnerKeepsAccount: false,
          invitedPartnerBecomesUnpaired: true,
          retireOldRelationship: true,
          exportForBoth: true,
          ownerAccountDeletionRequested: false,
          invitedAccountDeletionRequested: true,
        );
    }
  }
}
