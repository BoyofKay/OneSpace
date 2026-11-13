import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'activity_image_rules.dart';

/// Selects one user-approved photo and attaches it to a Coordinate Activity.
/// Storage uploads use a private bucket. Failed database inserts roll back the
/// unreferenced object without deleting any existing contribution.
class ActivityImageService {
  ActivityImageService(this.client, {ImagePicker? picker})
      : picker = picker ?? ImagePicker();

  final SupabaseClient client;
  final ImagePicker picker;

  /// Returns false if the user cancels the system photo picker.
  Future<bool> addPhoto({
    required String activityId,
    String? parentComponentId,
  }) async {
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked == null) return false;

    final bytes = await picked.readAsBytes();
    ActivityImageRules.validate(bytes);
    final mime = ActivityImageRules.mimeType(bytes)!;
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Please sign in first.');

    final filename = '${const Uuid().v4()}.${ActivityImageRules.extension(mime)}';
    final path = ActivityImageRules.objectPath(
      activityId: activityId,
      userId: userId,
      filename: filename,
    );
    final storage = client.storage.from(ActivityImageRules.bucket);
    await storage.uploadBinary(
      path, bytes,
      fileOptions: FileOptions(contentType: mime, upsert: false),
    );

    try {
      await client.from('activity_components').insert({
        'activity_id': activityId,
        'parent_component_id': parentComponentId,
        'kind': 'image',
        'label': 'Photo',
        'payload': {
          'object_path': path,
          'mime': mime,
          'note': '',
        },
      });
    } catch (_) {
      // Deletion is deliberately restricted by RLS to unreferenced own files.
      try {
        await storage.remove([path]);
      } catch (_) {
        // The failed upload can be cleaned up later without data loss.
      }
      rethrow;
    }
    return true;
  }
}
