import 'package:material_ui/material_ui.dart';

/// Each authenticated account uses its own server-stored preferred locale.
/// A null locale follows the device language before sign-in.
class OneSpaceLocaleController extends ValueNotifier<Locale?> {
  OneSpaceLocaleController._() : super(null);

  static final OneSpaceLocaleController instance =
      OneSpaceLocaleController._();

  void selectLanguage(String? code) {
    final next = code == 'en' || code == 'ar' ? Locale(code!) : null;
    if (value?.languageCode != next?.languageCode) {
      value = next;
    }
  }
}
