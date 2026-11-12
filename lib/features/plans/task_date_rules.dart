/// OneSpace task dates are calendar days in the user's local timezone.
/// A target must be today or later; past dates remain visible for old tasks.
class TaskDateRules {
  const TaskDateRules._();

  static DateTime localToday(DateTime now) =>
      DateTime(now.year, now.month, now.day);

  static bool isAllowed(DateTime? targetDate, DateTime now) {
    if (targetDate == null) return true;
    final day = localToday(targetDate);
    return !day.isBefore(localToday(now));
  }

  static DateTime initialForPicker(DateTime? existing, DateTime now) {
    return isAllowed(existing, now) && existing != null
        ? localToday(existing)
        : localToday(now);
  }
}
