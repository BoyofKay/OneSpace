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
  Map<String, String>? _memberNames;
  DateTime? _loadedAt;
  Future<String?>? _pending;
  int _generation = 0;

  void seed(String userId, String? spaceId,
      {Map<String, String>? memberNames}) {
    _generation++;
    _userId = userId;
    _spaceId = spaceId;
    // Only cache names returned by an authenticated, RLS-checked snapshot.
    // They never touch local disk and expire with the membership lookup.
    _memberNames = memberNames == null
        ? null : Map<String, String>.unmodifiable(memberNames);
    _loadedAt = DateTime.now();
    _pending = null;
  }

  Map<String, String>? memberNamesFor(String spaceId) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || _userId != userId || _spaceId != spaceId ||
        _loadedAt == null ||
        DateTime.now().difference(_loadedAt!) >= const Duration(minutes: 2)) {
      return null;
    }
    return _memberNames;
  }

  void clear() {
    _generation++;
    _userId = null;
    _spaceId = null;
    _memberNames = null;
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
    final generation=++_generation;
    final request = client.from('space_members')
        .select('space_id').eq('user_id', id).limit(1)
        .then((rows) {
          final spaceId = rows.isEmpty ? null : rows.first['space_id'] as String?;
          if (_userId == id && _generation == generation) {
            if (_spaceId != spaceId) _memberNames = null;
            _spaceId = spaceId;
            _loadedAt = DateTime.now();
            _pending = null;
          }
          return spaceId;
        })
        .catchError((Object error) {
          if (_userId == id && _generation == generation) {
            _loadedAt = null;
            _pending = null;
          }
          throw error;
        });
    _pending = request;
    return request;
  }
}
