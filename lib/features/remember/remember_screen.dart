import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../../l10n/onespace_strings.dart';
import '../calendar/calendar_rules.dart';
import '../calendar/calendar_screen.dart';
import '../notes/notes_screen.dart';
import '../plans/plans_screen.dart';
import '../reminders/reminders_screen.dart';
import '../world/world_contacts_screen.dart';
import '../occasions/occasions_screen.dart';
import '../places/places_screen.dart';
import '../counters/counters_screen.dart';
import 'package:onespace/l10n/phrases.dart';

/// The Remember section keeps daily reference information visible in one place.
/// One invoker-only RPC returns the partner's RLS-filtered overview.
class RememberScreen extends StatefulWidget {
  const RememberScreen({super.key, this.refreshToken = 0});
  final int refreshToken;

  @override
  State<RememberScreen> createState() => _RememberScreenState();
}

class _RememberScreenState extends State<RememberScreen> {
  final _client = Supabase.instance.client;
  int _request = 0;
  bool _loading = true;
  bool _hasSpace = true;
  String? _error;
  Map<String, dynamic>? _overview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RememberScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    if (!mounted) return;
    setState(() {
      _loading = _overview == null;
      _error = null;
    });
    try {
      final space = await CurrentSpaceCache.instance.get();
      if (!mounted || request != _request) return;
      if (space == null) {
        setState(() {
          _hasSpace = false;
          _overview = null;
          _loading = false;
        });
        return;
      }
      final raw = await _client.rpc(
        'get_remember_overview',
        params: {'p_today': CalendarRules.sqlDate(DateTime.now())},
      ).timeout(const Duration(seconds: 15));
      if (!mounted || request != _request) return;
      setState(() {
        _hasSpace = true;
        _overview = raw is Map ? Map<String, dynamic>.from(raw) : null;
        _loading = false;
      });
    } on PostgrestException catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _error = tr(context, 'rememberLoadError');
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) await _load();
  }

  int _count(String key) =>
      (_overview?[key] as num?)?.toInt() ?? 0;

  Widget _destination({
    required IconData icon,
    required String title,
    required String subtitle,
    int? count,
    required Widget destination,
  }) => Card(
    elevation: 0,
    child: ListTile(
      leading: Icon(icon,color:Theme.of(context).colorScheme.primary,size:27),
      title: Text(tt(title), style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(tt(subtitle)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if(count!=null)...[
            Text(tt(count.toString()),style:Theme.of(context).textTheme.titleMedium),
            const SizedBox(width:6),
          ],
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => _open(destination),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          Text(tr(context, 'rememberTitle'),
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 5),
          Text(tr(context, 'rememberIntro')),
          const SizedBox(height: 15),
          if (_error != null) ...[
            Text(tt(_error!), style: TextStyle(
                color: Theme.of(context).colorScheme.error)),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(tr(context, 'retry')),
            ),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (!_hasSpace)
            Text(tr(context, 'noSpace'))
          else if (_overview != null) ...[
            _destination(
              icon: Icons.calendar_month_outlined,
              title: tr(context, 'rememberCalendarTitle'),
              subtitle: tr(context, 'rememberCalendarSubtitle'),
              count: _count('event_count'),
              destination: const CalendarScreen(),
            ),
            _destination(
              icon: Icons.checklist_rounded,
              title: tr(context, 'rememberTodosTitle'),
              subtitle: tr(context, 'rememberTodosSubtitle'),
              count: _count('todo_count'),
              destination: const PlansScreen(),
            ),
            _destination(
              icon: Icons.alarm_outlined,
              title: tt('Reminders'),
              subtitle: tt('Personal and shared alerts, snoozes and follow-up notes'),
              destination: const RemindersScreen(),
            ),
            _destination(
              icon: Icons.sticky_note_2_outlined,
              title: tr(context, 'rememberNotesTitle'),
              subtitle: tr(context, 'rememberNotesSubtitle'),
              count: _count('notes_count'),
              destination: const NotesScreen(),
            ),
            // R77: our places and our counters.
            _destination(
              icon:Icons.place_outlined,
              title:tt('Our places'),
              subtitle:tt('Where we have been together, and our bucket list'),
              destination:const PlacesScreen(),
            ),
            _destination(
              icon:Icons.hourglass_bottom_rounded,
              title:tt('Counters'),
              subtitle:tt('Days since and days until the moments that matter'),
              destination:const CountersScreen(),
            ),
            _destination(
              icon:Icons.card_giftcard_outlined,
              title:tt('Occasions'),
              subtitle:tt('Gifts, holidays, budgets and early preparation'),
              destination:const OccasionsScreen(),
            ),
            _destination(
              icon:Icons.contacts_outlined,
              title:tt('Contact cards'),
              subtitle:tt('Family, friends, useful contacts and shared context'),
              destination:const WorldContactsScreen(),
            ),
          ],
        ],
      ),
    );
  }

}
