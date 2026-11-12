/// Extracts only partner identities the authenticated Home snapshot returned.
/// This is never a global directory and must not be persisted to disk.
class HomeMemberNames {
  const HomeMemberNames._();

  static Map<String, String>? parse(Object? members) {
    if (members is! List) return null;
    final names = <String, String>{};
    for (final entry in members) {
      if (entry is! Map) continue;
      final id = entry['user_id'];
      if (id is! String || id.isEmpty) continue;
      final label = entry['name'];
      names[id] = label is String && label.trim().isNotEmpty
          ? label : 'Member';
    }
    return names.isEmpty ? null : Map<String, String>.unmodifiable(names);
  }
}
