import 'package:material_ui/material_ui.dart';

import '../../l10n/onespace_locale_controller.dart';

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
              OneSpaceLocaleController.instance.selectLanguage('en'),
          child: const Text('EN'),
        ),
        const Text('|'),
        TextButton(
          onPressed: disabled ? null : () =>
              OneSpaceLocaleController.instance.selectLanguage('ar'),
          child: const Text('AR'),
        ),
      ],
    ),
  );
}
