/// Pure client-side checks mirroring database constraints. Server RLS and
/// CHECK constraints still authorize every write.
class ConnectionRules {
  const ConnectionRules._();

  static bool validGoal({
    required String title,
    required String description,
    required int progress,
  }) => title.trim().isNotEmpty && title.trim().length <= 120 &&
      description.length <= 3000 && progress >= 0 && progress <= 100;

  static bool validCheckin({
    required DateTime day,
    required DateTime now,
    required int mood,
    required String message,
    required String gratitude,
  }) {
    final today = DateTime(now.year,now.month,now.day);
    final date = DateTime(day.year,day.month,day.day);
    return !date.isAfter(today) && mood >= 1 && mood <= 5 &&
      message.length <= 2000 && gratitude.length <= 500;
  }
}
