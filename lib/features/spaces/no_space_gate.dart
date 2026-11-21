import 'package:material_ui/material_ui.dart';
import 'package:onespace/l10n/phrases.dart';

import '../../core/app_env.dart';
import '../../core/current_space_cache.dart';

/// QA: without a space (after leaving, being removed or a deleted space),
/// nothing new can be added until the person joins or creates one. The tab
/// shows how to get a space instead of its add buttons.
class NoSpaceGate extends StatelessWidget {
  const NoSpaceGate({super.key, required this.child, required this.onGetSpace});
  final Widget child;
  final VoidCallback onGetSpace;

  @override
  Widget build(BuildContext context) {
    if (OneSpaceEnv.usesLegacyBackend) return child;
    return ValueListenableBuilder<bool?>(
      valueListenable: CurrentSpaceCache.hasSpace,
      builder: (context, has, _) {
        if (has != false) return child;
        final theme = Theme.of(context);
        return Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.home_work_outlined, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 14),
            Text(tt('Join or create a space first'), textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(tt('You are not in a space right now. Join your partner’s space, invite a partner, or create your own space to start adding things again.'),
              textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            FilledButton.icon(key: const Key('noSpaceGoToday'), onPressed: onGetSpace,
              icon: const Icon(Icons.arrow_forward), label: Text(tt('Get a space'))),
          ])));
      });
  }
}
