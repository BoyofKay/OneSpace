import 'package:material_ui/material_ui.dart';

import '../../l10n/onespace_locale_controller.dart';
import 'package:onespace/l10n/phrases.dart';

/// Small corner switch without adding a full row to sign-in.
class AuthLanguageSwitcher extends StatelessWidget {
  const AuthLanguageSwitcher({super.key, this.disabled = false});
  final bool disabled;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.topEnd,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: disabled ? null : () =>
              OneSpaceLocaleController.instance
                ..chosenOnSignIn = 'en'
                ..selectLanguage('en'),
          child: Text(tt('EN')),
        ),
        const Text('|'),
        TextButton(
          onPressed: disabled ? null : () =>
              OneSpaceLocaleController.instance
                ..chosenOnSignIn = 'ar'
                ..selectLanguage('ar'),
          child: Text(tt('AR')),
        ),
      ],
    ),
  );
}
