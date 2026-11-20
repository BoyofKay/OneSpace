import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_env.dart';

/// The two independent scopes shown as one experience in QA.
///
/// On Production the old couple-scoped schema is retained until an approved
/// production migration. An unpaired QA account can always use its private
/// namespace, even when there is no shared relationship.
class AccountContentScope {
  const AccountContentScope({
    required this.accountOwned,
    required this.sharedSpaceId,
    this.privateSpaceId,
  });

  final bool accountOwned;
  final String? sharedSpaceId;
  final String? privateSpaceId;

  bool get canCreatePrivate =>
      accountOwned ? privateSpaceId != null : sharedSpaceId != null;
  bool get canCreateShared => sharedSpaceId != null;

  /// Never infer ownership from a former relationship or cached space ID.
  static Future<AccountContentScope> load(
    SupabaseClient client, {
    String? legacySpaceId,
  }) async {
    if (OneSpaceEnv.isProduction) {
      return AccountContentScope(
        accountOwned: false,
        sharedSpaceId: legacySpaceId,
      );
    }
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in to load your personal space.');
    final raw = await client.rpc('my_storage_scopes');
    if (raw is! Map) throw StateError('Personal scope unavailable.');
    final ownerId = raw['private_space_id']?.toString();
    if (ownerId != userId) {
      throw StateError('Your personal scope is not ready. Please retry.');
    }
    return AccountContentScope(
      accountOwned: true,
      privateSpaceId: ownerId,
      sharedSpaceId: raw['shared_space_id']?.toString(),
    );
  }

  /// Used for new content only. Existing records never change owner/scope as
  /// a side effect of editing a title, a date, or their visibility label.
  Map<String, dynamic> fieldsForNew({required bool shared}) {
    if (shared) {
      final id = sharedSpaceId;
      if (id == null) {
        throw StateError('Join a partner before creating shared content.');
      }
      return {'space_id': id, 'visibility': 'shared'};
    }
    if (accountOwned) {
      final id = privateSpaceId;
      if (id == null) throw StateError('Personal space unavailable.');
      return {'private_space_id': id, 'visibility': 'private'};
    }
    final id = sharedSpaceId;
    if (id == null) throw StateError('Space unavailable.');
    return {'space_id': id, 'visibility': 'private'};
  }
}
