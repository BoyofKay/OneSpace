import 'package:material_ui/material_ui.dart';

/// Each authenticated account uses its own server-stored preferred locale.
/// A null locale follows the device language before sign-in.
class OneSpaceLocaleController extends ValueNotifier<Locale?> {
  OneSpaceLocaleController._() : super(null);

  static final OneSpaceLocaleController instance =
      OneSpaceLocaleController._();

  /// UAT 26 Nov 2026: the language picked on the sign-in screen (EN | AR).
  /// At sign-in it becomes the account's language instead of being replaced
  /// by the language saved earlier on the account.
  String? chosenOnSignIn;

  void selectLanguage(String? code) {
    final next = code == 'en' || code == 'ar' ? Locale(code!) : null;
    if (value?.languageCode != next?.languageCode) {
      value = next;
    }
  }
}
