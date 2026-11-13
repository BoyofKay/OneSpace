import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'activity_voice_rules.dart';

enum VoiceDestination { component, comment }

/// Upload a user-approved local recording and atomically represent it as a
/// shared Activity contribution. Failed database writes clean up only unused
/// own uploads; the caller keeps local bytes so Send can be retried.
class ActivityVoiceService {
  const ActivityVoiceService(this.client);

  final SupabaseClient client;

  Future<void> send({
    required Uint8List bytes,
    required int seconds,
    required String activityId,
    required VoiceDestination destination,
    String? parentComponentId,
    String? replyToCommentId,
    String? relatedComponentId,
  }) async {
    ActivityVoiceRules.validate(bytes, seconds);
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Please sign in to send a voice note.');
    final path = ActivityVoiceRules.objectPath(
      activityId: activityId,
      userId: userId,
      fileId: const Uuid().v4(),
    );
    final storage = client.storage.from(ActivityVoiceRules.bucket);
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(
        contentType: 'audio/mp4',
        upsert: false,
      ),
    );
    try {
      if (destination == VoiceDestination.component) {
        await client.from('activity_components').insert({
          'activity_id': activityId,
          'parent_component_id': parentComponentId,
          'kind': 'voice',
          'label': 'Voice note',
          'payload': {
            'voice_path': path,
            'voice_seconds': seconds,
            'note': '',
          },
        });
      } else {
        await client.from('activity_comments').insert({
          'activity_id': activityId,
          'body': 'Voice note',
          'reply_to': replyToCommentId,
          'component_id': relatedComponentId,
          'voice_path': path,
          'voice_seconds': seconds,
        });
      }
    } catch (_) {
      try {
        await storage.remove([path]);
      } catch (_) {
        // An unreferenced object can be collected later without ever deleting
        // an existing attachment. The local recording remains available.
      }
      rethrow;
    }
  }
}
