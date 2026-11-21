import 'package:material_ui/material_ui.dart';
import 'package:onespace/l10n/phrases.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_env.dart';
import '../../core/current_space_cache.dart';

/// QA: a fixed banner on Today that tells someone their pairing changed
/// (partner left, removed, space deleted, account deleted). It stays until
/// they dismiss it, and does not depend on any space, so it survives the
/// shared space being deleted.
class AccountNoticeBanner extends StatefulWidget {
  const AccountNoticeBanner({super.key});
  @override
  State<AccountNoticeBanner> createState() => _AccountNoticeBannerState();
}

class _AccountNoticeBannerState extends State<AccountNoticeBanner> with WidgetsBindingObserver {
  List<Map<String, dynamic>> notices = const [];

  @override
  void initState() {
    super.initState();
    if (OneSpaceEnv.isProduction) return;
    WidgetsBinding.instance.addObserver(this);
    CurrentSpaceCache.paired.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    if (!OneSpaceEnv.isProduction) {
      WidgetsBinding.instance.removeObserver(this);
      CurrentSpaceCache.paired.removeListener(_load);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final db = Supabase.instance.client;
      final me = db.auth.currentUser?.id;
      if (me == null) return;
      final rows = await db.from('account_notices').select('id,title,body,created_at')
        .eq('user_id', me).isFilter('dismissed_at', null)
        .order('created_at', ascending: false).limit(3);
      if (mounted) setState(() => notices = List<Map<String, dynamic>>.from(rows));
    } catch (_) {/* The banner is a hint; Today still works without it. */}
  }

  Future<void> _dismiss(String id) async {
    setState(() => notices = notices.where((n) => n['id'] != id).toList());
    try {
      await Supabase.instance.client.from('account_notices')
        .update({'dismissed_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
    } catch (_) { _load(); }
  }

  @override
  Widget build(BuildContext context) {
    if (OneSpaceEnv.isProduction || notices.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(children: [
      for (final n in notices)
        Card(
          key: ValueKey('notice-${n['id']}'),
          color: theme.colorScheme.secondaryContainer,
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 6, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tt(n['title']?.toString() ?? ''), style: theme.textTheme.titleSmall
                    ?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
                  const SizedBox(height: 4),
                  Text(tt(n['body']?.toString() ?? ''), style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
                ])),
              ]),
              Align(alignment: AlignmentDirectional.centerEnd,
                child: TextButton(onPressed: () => _dismiss(n['id'].toString()),
                  child: Text(tt('Dismiss')))),
            ]),
          ),
        ),
    ]);
  }
}
