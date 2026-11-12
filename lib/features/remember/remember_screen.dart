import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../../l10n/onespace_strings.dart';
import '../calendar/calendar_rules.dart';
import '../calendar/calendar_screen.dart';
import '../coordinate/coordinate_screen.dart';
import '../notes/notes_screen.dart';
import '../plans/plans_screen.dart';
import 'remember_rules.dart';

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

  List<dynamic> _items(String key) =>
      _overview?[key] as List<dynamic>? ?? const [];

  Widget _destination({
    required IconData icon,
    required String title,
    required String subtitle,
    required int count,
    required Widget destination,
  }) => Card(
    elevation: 0,
    child: ListTile(
      leading: Icon(icon, color: const Color(0xFF167E81), size: 27),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => _open(destination),
    ),
  );

  Widget _sectionHeading(String title, Widget destination) => Row(
    children: [
      Expanded(child: Text(title,
          style: Theme.of(context).textTheme.titleLarge)),
      TextButton(
        onPressed: () => _open(destination),
        child: Text(tr(context, 'rememberSeeAll')),
      ),
    ],
  );

  String _dueLabel(RememberDue due) {
    final days = RememberRules.daysFromToday(due.date, DateTime.now());
    if (days < 0) {
      return '${tr(context, 'rememberOverdue')} ${-days} '
          '${tr(context, 'rememberDays')}';
    }
    if (days == 0) return tr(context, 'rememberDueToday');
    return '${tr(context, 'rememberDueIn')} $days '
        '${tr(context, 'rememberDays')}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final events = RememberRules.upcomingEvents(
      _items('upcoming_events'), now);
    final dues = RememberRules.upcomingDues(_items('upcoming_dues'));
    final recentNotes = _items('recent_notes');
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
            Text(_error!, style: TextStyle(
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
              icon: Icons.sticky_note_2_outlined,
              title: tr(context, 'rememberNotesTitle'),
              subtitle: tr(context, 'rememberNotesSubtitle'),
              count: _count('notes_count'),
              destination: const NotesScreen(),
            ),
            const SizedBox(height: 18),
            _sectionHeading(
                tr(context, 'rememberUpcomingDues'), const PlansScreen()),
            const SizedBox(height: 4),
            if (dues.isEmpty)
              _empty(tr(context, 'rememberNoDues'))
            else
              for (final due in dues.take(6))
                Card(
                  elevation: 0,
                  child: ListTile(
                    leading: Icon(
                      due.kind == 'activity'
                          ? Icons.hub_outlined
                          : Icons.check_circle_outline,
                    ),
                    title: Text(due.title),
                    subtitle: Text(
                        '${_dueLabel(due)} · ${CalendarRules.sqlDate(due.date)}'),
                    onTap: () => _open(
                      due.kind == 'activity'
                          ? ActivityScreen(id: due.id)
                          : const PlansScreen(),
                    ),
                  ),
                ),
            const SizedBox(height: 15),
            _sectionHeading(
                tr(context, 'rememberUpcomingEvents'),
                const CalendarScreen()),
            const SizedBox(height: 4),
            if (events.isEmpty)
              _empty(tr(context, 'rememberNoEvents'))
            else
              for (final event in events.take(6))
                Card(
                  elevation: 0,
                  child: ListTile(
                    leading: Icon(event.kind == 'occasion'
                        ? Icons.celebration_outlined
                        : Icons.event_outlined),
                    title: Text(event.title),
                    subtitle: Text(CalendarRules.sqlDate(event.date)),
                    onTap: () => _open(const CalendarScreen()),
                  ),
                ),
            const SizedBox(height: 15),
            _sectionHeading(
                tr(context, 'rememberRecentNotes'), const NotesScreen()),
            const SizedBox(height: 4),
            if (recentNotes.isEmpty)
              _empty(tr(context, 'rememberNoNotes'))
            else
              for (final raw in recentNotes)
                if (raw is Map)
                  Card(
                    elevation: 0,
                    child: ListTile(
                      leading: const Icon(Icons.note_alt_outlined),
                      title: Text(raw['title']?.toString() ?? ''),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(const NotesScreen()),
                    ),
                  ),
          ],
        ],
      ),
    );
  }

  Widget _empty(String message) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(message,
          style: Theme.of(context).textTheme.bodyMedium),
    ),
  );
}

