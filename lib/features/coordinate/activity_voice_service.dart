import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'activity_voice_rules.dart';
import '../../core/app_env.dart';

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
    var bucketId=ActivityVoiceRules.bucket;
    if(!OneSpaceEnv.isProduction){
      final activity=await client.from('activities')
       .select('space_id,private_space_id,created_by,visibility')
       .eq('id',activityId).single();
      if(activity['private_space_id']!=null){
        if(activity['private_space_id']!=userId||activity['created_by']!=userId||
          activity['space_id']!=null||activity['visibility']!='private'){
          throw StateError('This personal Activity belongs to another account.');
        }
        bucketId='onespace-private-activity-voice';
      }else if(activity['space_id']==null||activity['visibility']!='shared'){
        throw StateError('No current shared space for this voice note.');
      }
    }
    final path = ActivityVoiceRules.objectPath(
      activityId: activityId,
      userId: userId,
      fileId: const Uuid().v4(),
    );
    final storage = client.storage.from(bucketId);
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
            if(!OneSpaceEnv.isProduction)'bucket_id':bucketId,
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
          if(!OneSpaceEnv.isProduction)'voice_bucket_id':bucketId,
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
