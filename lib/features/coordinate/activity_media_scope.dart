import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_env.dart';
import 'activity_image_rules.dart';
import 'activity_voice_rules.dart';

/// Resolves an Activity's Storage scope from a currently RLS-visible root.
/// Never trust a client-supplied bucket name or a previous couple ID.
class ActivityMediaScope {
  const ActivityMediaScope._();

  static const privateImageBucket = 'onespace-private-activity-media';
  static const privateVoiceBucket = 'onespace-private-activity-voice';

  static Future<bool> isAccountPrivate(
      SupabaseClient db, String activityId) async {
    if (OneSpaceEnv.isProduction) return false;
    final a = await db.from('activities')
        .select('private_space_id,created_by,space_id,visibility')
        .eq('id', activityId).single();
    final privateId = a['private_space_id']?.toString();
    if (privateId == null) {
      if (a['space_id'] == null) {
        throw StateError('Activity has no active content scope.');
      }
      return false;
    }
    final me = db.auth.currentUser?.id;
    if (me != privateId || a['created_by'] != me ||
        a['space_id'] != null || a['visibility'] != 'private') {
      throw StateError('Private Activity media belongs to another account.');
    }
    return true;
  }

  static Future<String> imageBucket(
    SupabaseClient db, String activityId,
  ) async => await isAccountPrivate(db, activityId)
      ? privateImageBucket : ActivityImageRules.bucket;

  static Future<String> voiceBucket(
    SupabaseClient db, String activityId,
  ) async => await isAccountPrivate(db, activityId)
      ? privateVoiceBucket : ActivityVoiceRules.bucket;

  static String activityIdFromPath(String path) {
    final parts = path.split('/');
    if (parts.length != 3 || parts.first.isEmpty) {
      throw const FormatException('Invalid Activity media path.');
    }
    return parts.first;
  }
}
