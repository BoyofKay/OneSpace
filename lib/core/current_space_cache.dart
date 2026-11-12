import 'package:supabase_flutter/supabase_flutter.dart';

/// User-scoped, short-lived in-memory membership lookup.
///
/// Prevents repeating the Seoul round trip each time a new tab opens.
/// Never caches data to disk or skips backend RLS checks for content.
class CurrentSpaceCache {
  CurrentSpaceCache._();
  static final instance = CurrentSpaceCache._();

  String? _userId;
  String? _spaceId;
  DateTime? _loadedAt;
  Future<String?>? _pending;

  void seed(String userId, String? spaceId) {
    _userId = userId;
    _spaceId = spaceId;
    _loadedAt = DateTime.now();
    _pending = null;
  }

  void clear() {
    _userId = null;
    _spaceId = null;
    _loadedAt = null;
    _pending = null;
  }

  Future<String?> get({bool refresh = false}) {
    final client = Supabase.instance.client;
    final id = client.auth.currentUser?.id;
    if (id == null) {
      clear();
      return Future.value(null);
    }
    if (_userId != id) clear();
    if (!refresh &&
        _userId == id &&
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(minutes: 2)) {
      return Future.value(_spaceId);
    }
    if (!refresh && _userId == id && _pending != null) return _pending!;
    _userId = id;
    final request = client.from('space_members')
        .select('space_id').eq('user_id', id).limit(1)
        .then((rows) {
          final spaceId = rows.isEmpty ? null : rows.first['space_id'] as String?;
          if (_userId == id) {
            _spaceId = spaceId;
            _loadedAt = DateTime.now();
            _pending = null;
          }
          return spaceId;
        })
        .catchError((Object error) {
          if (_userId == id) {
            _loadedAt = null;
            _pending = null;
          }
          throw error;
        });
    _pending = request;
    return request;
  }
}
