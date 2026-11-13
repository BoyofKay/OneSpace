/// Resolves contextual reply previews against only the already RLS-visible
/// messages and components of the current Activity. No extra network calls.
class ActivityConversationReferences {
  const ActivityConversationReferences._();

  static String excerpt(Object? raw, {int maxCharacters = 88}) {
    final value = raw?.toString().replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    if (value.runes.length <= maxCharacters) return value;
    final runes = value.runes.take(maxCharacters - 1).toList();
    return '${String.fromCharCodes(runes).trimRight()}…';
  }

  static String? quotedMessage(
    Map<String, dynamic> message,
    List<Map<String, dynamic>> messages,
  ) {
    final parentId = message['reply_to'];
    if (parentId is! String || parentId.isEmpty) return null;
    for (final parent in messages) {
      if (parent['id'] != parentId ||
          parent['activity_id'] != message['activity_id']) {
        continue;
      }
      final preview = excerpt(parent['body']);
      return preview.isEmpty ? 'Earlier message' : preview;
    }
    return 'Earlier message unavailable';
  }

  static String? componentName(
    Map<String, dynamic> message,
    List<Map<String, dynamic>> components,
  ) {
    final componentId = message['component_id'];
    if (componentId is! String || componentId.isEmpty) return null;
    for (final component in components) {
      if (component['id'] != componentId ||
          component['activity_id'] != message['activity_id']) {
        continue;
      }
      final title = excerpt(component['label'], maxCharacters: 65);
      return title.isEmpty ? 'Attached item' : title;
    }
    return 'Attached item unavailable';
  }
}
