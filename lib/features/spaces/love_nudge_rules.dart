/// R55 built-in "a little love" nudge (replaces the manual reminder button).
///
/// Today shows one gentle row in Needs your attention when it has been a
/// while since you sent your partner a little love:
/// * living apart: after 1 day; together: after 2 days; never sent: always;
/// * only between 9:00 AM and 9:00 PM on your phone;
/// * "Not today" hides it until tomorrow.
class LoveNudgeRules {
  const LoveNudgeRules._();

  static int thresholdDays({required bool apart}) => apart ? 1 : 2;

  /// The row text, or null when no nudge should show.
  static String? nudge({required DateTime? lastSent, required DateTime now,
      required bool apart, DateTime? dismissedOn}) {
    if (now.hour < 9 || now.hour >= 21) return null;
    final today = DateTime(now.year, now.month, now.day);
    if (dismissedOn != null &&
        DateTime(dismissedOn.year, dismissedOn.month, dismissedOn.day) == today) {
      return null;
    }
    if (lastSent == null) return 'Send your first little love';
    final days = today.difference(DateTime(lastSent.year, lastSent.month, lastSent.day)).inDays;
    if (days < thresholdDays(apart: apart)) return null;
    return days == 1 ? 'Your last little love was yesterday'
        : 'It has been $days days since your last little love';
  }
}
