/// Client-side validation only. Supabase still verifies current credentials.
/// Do not enable the submit action on an empty/incomplete form.
class PasswordChangeRules {
  const PasswordChangeRules._();

  static bool canSubmit({
    required String current,
    required String next,
    required String confirmation,
    required bool busy,
  }) => !busy &&
      current.isNotEmpty &&
      next.length >= 8 &&
      next != current &&
      confirmation == next;
}
