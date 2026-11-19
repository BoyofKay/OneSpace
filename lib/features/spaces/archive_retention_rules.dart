/// What is allowed to trigger early deletion of an encrypted server archive.
///
/// Automatic app-private backups are intentionally excluded: uninstalling
/// OneSpace destroys those local copies. Only an explicit external save whose
/// written bytes were read back and checksum verified can acknowledge the
/// user download. Independently, the server enforces the 30-day deadline.
class ArchiveRetentionRules {
  const ArchiveRetentionRules._();

  static bool mayConfirmExternalSave({
    required bool userInitiated,
    required bool savedOutsideApp,
    required bool verifiedAfterWrite,
  }) => userInitiated && savedOutsideApp && verifiedAfterWrite;

  static DateTime expiresAt(DateTime readyAt) =>
      readyAt.toUtc().add(const Duration(days: 30));
}
