/// OneSpace chat identity is intentionally human-readable: the current
/// speaker is 'You', while the partner's saved full display name is shown.
/// Avatar initials always come from the saved name when available.
class ActivityMessageIdentity {
  const ActivityMessageIdentity._();

  static String label({
    required String? authorId,
    required String currentUserId,
    required Map<String, String>? memberNames,
  }) {
    if (authorId == currentUserId && currentUserId.isNotEmpty) return 'You';
    final saved = memberNames?[authorId]?.trim();
    return saved == null || saved.isEmpty ? 'Partner' : saved;
  }

  static String initials({
    required String? authorId,
    required String currentUserId,
    required Map<String, String>? memberNames,
  }) {
    final saved = memberNames?[authorId]?.trim();
    final value = saved == null || saved.isEmpty
        ? (authorId == currentUserId ? 'You' : 'Partner')
        : saved;
    final parts = value.split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = String.fromCharCodes(parts.first.runes.take(1));
    final last = parts.length == 1
        ? '' : String.fromCharCodes(parts.last.runes.take(1));
    return '$first$last'.toUpperCase();
  }
}
