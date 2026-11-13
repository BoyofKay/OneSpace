import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'partner_time_zones.dart';

/// Refreshes the account's zone from Android/iOS system settings.
/// Never requests GPS or stores a fixed UTC offset.
class DeviceTimeZone {
  const DeviceTimeZone._();

  static Future<String?> readPhone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      final zone = info.identifier;
      return PartnerTimeZones.valid(zone) ? zone : null;
    } catch (_) {
      return null; // Phone clock stays available even if native plugin fails.
    }
  }

  static Future<String?> sync(SupabaseClient client, {
    String? storedZone,
  }) async {
    final id = client.auth.currentUser?.id;
    if (id == null) return null;
    final phoneZone = await readPhone();
    if (phoneZone == null || phoneZone == storedZone) return phoneZone;
    await client.from('profiles')
        .update({'time_zone': phoneZone}).eq('id',id);
    return phoneZone;
  }
}
