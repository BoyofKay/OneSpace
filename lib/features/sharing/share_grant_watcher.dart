import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Reopens the RLS-filtered data stream whenever a private view grant changes.
/// This matters because an ACL change does not itself emit a row change on
/// the task/list/note, so its old stream might otherwise retain stale data.
StreamSubscription<List<Map<String, dynamic>>> watchObjectShares({
  required SupabaseClient client,
  required String spaceId,
  required String objectType,
  required void Function() onChanged,
}) {
  String? previous;
  return client.from('object_shares')
      .stream(primaryKey: ['id'])
      .eq('space_id', spaceId)
      .listen((rows) {
        final fragments = rows
            .where((r) => r['object_type'] == objectType)
            .map((r) => '${r['id']}:${r['revoked_at'] ?? 'active'}')
            .toList()..sort();
        final signature = fragments.join('|');
        if (previous != null && previous != signature) onChanged();
        previous = signature;
      }, onError: (Object error, StackTrace trace) {
        // The original protected data stream is still controlled by RLS.
        // A future tab refresh will requery content when connectivity returns.
      });
}
