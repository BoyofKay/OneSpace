/// Distinguish the local privacy shield from the remote Supabase session.
/// Local locking does NOT revoke an access token or stop its refresh.
class SessionLockRules {
  const SessionLockRules._();

  static const idleTimeout = Duration(minutes: 30);
  static const backgroundTimeout = Duration(minutes: 5);

  static bool idleExpired(DateTime lastActivity, DateTime now) =>
      now.difference(lastActivity) >= idleTimeout;

  static bool backgroundExpired(DateTime leftApp, DateTime now) =>
      now.difference(leftApp) >= backgroundTimeout;
}
