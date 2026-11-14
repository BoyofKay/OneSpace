/// Pure, privacy-neutral presentation rules for the two members' preferences.
///
/// Supabase RLS must authorize rows before the app receives them. This class
/// never contacts the backend, sends notifications or infers partner consent.
class ExperienceInterestRules {
  static const choices = <String, String>{
    'yes': 'Interested',
    'maybe': 'Maybe',
    'not_now': 'Not now',
    'undecided': 'Clear pick',
  };

  static List<Map<String, dynamic>> forExperience(
    Iterable<Map<String, dynamic>> votes,
    Object? experienceId,
  ) => votes
      .where((vote) => vote['experience_id'] == experienceId)
      .toList(growable: false);

  static String choiceForUser(
    Iterable<Map<String, dynamic>> votes,
    Object? experienceId,
    Object? userId,
  ) {
    if (userId == null) return 'undecided';
    for (final vote in votes) {
      if (vote['experience_id'] == experienceId && vote['user_id'] == userId) {
        final choice = vote['choice']?.toString();
        if (choices.containsKey(choice)) return choice!;
      }
    }
    return 'undecided';
  }

  static bool mutuallyInterested(
    Iterable<Map<String, dynamic>> votes,
    Object? experienceId,
  ) {
    final agreeingUsers = <String>{};
    for (final vote in votes) {
      if (vote['experience_id'] == experienceId &&
          vote['choice'] == 'yes' &&
          vote['user_id'] != null) {
        agreeingUsers.add(vote['user_id'].toString());
      }
    }
    return agreeingUsers.length >= 2;
  }

  static String summary(
    Iterable<Map<String, dynamic>> votes,
    Object? experienceId,
  ) {
    if (mutuallyInterested(votes, experienceId)) return 'Mutual pick';
    final active = forExperience(votes, experienceId)
        .where((vote) => vote['choice'] != 'undecided')
        .toList(growable: false);
    if (active.isEmpty) return 'No picks yet';
    if (active.any((vote) => vote['choice'] == 'yes')) {
      return 'One partner interested';
    }
    if (active.any((vote) => vote['choice'] == 'maybe')) {
      return 'Still considering';
    }
    return 'Not right now';
  }

  static int mutualCount(
    Iterable<Map<String, dynamic>> experiences,
    Iterable<Map<String, dynamic>> votes,
  ) {
    final activeIds = experiences
        .where((item) => item['archived_at'] == null &&
            item['status'] != 'enjoyed')
        .map((item) => item['id'])
        .toSet();
    return activeIds
        .where((id) => mutuallyInterested(votes, id))
        .length;
  }
}
