/// Note limits used by the app and matching the database constraints.
class NoteDraftRules {
  const NoteDraftRules._();

  static bool isValid({required String title, required String body}) =>
      title.trim().isNotEmpty &&
      title.trim().length <= 120 &&
      body.length <= 30000;
}
