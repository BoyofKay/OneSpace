/// Presentation-only checks; database RLS remains the authority.
class ObjectPermissions {
  const ObjectPermissions._();

  static bool canEdit({
    required String visibility,
    required String createdBy,
    required String userId,
  }) => visibility == 'shared' || createdBy == userId;

  static bool canManagePrivateShare({
    required String visibility,
    required String createdBy,
    required String userId,
  }) => visibility == 'private' && createdBy == userId;

  static bool isViewOnly({
    required String visibility,
    required String createdBy,
    required String userId,
  }) => visibility == 'private' && createdBy != userId;
}
