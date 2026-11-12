import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../../core/performance_timings.dart';
import '../../l10n/onespace_strings.dart';
import '../sharing/object_permissions.dart';
import '../sharing/private_share_button.dart';
import 'calendar_event_editor.dart';
import 'calendar_rules.dart';

/// Date-based calendar MVP. RLS filters all server queries; yearly events are
/// calculated locally without moving birthdays across timezones.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.onOpenPlans});
  final VoidCallback? onOpenPlans;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _client = Supabase.instance.client;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = CalendarRules.day(DateTime.now());
  String? _spaceId;
  String? _error;
  bool _loading = true;
  bool _showArchived = false;
  List<Map<String, dynamic>> _events = const [];
  List<Map<String, dynamic>> _tasks = const [];
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    final stopwatch = Stopwatch()..start();
    if (mounted) setState(() { _loading = _spaceId == null; _error = null; });
    try {
      final id = await CurrentSpaceCache.instance.get();
      if (!mounted || version != _loadVersion) return;
      if (id == null) {
        setState(() {
          _spaceId = null;
          _events = const [];
          _tasks = const [];
          _loading = false;
        });
        return;
      }
      _spaceId = id;
      final results = await Future.wait<List<Map<String, dynamic>>>([
        _client.from('space_events')
            .select('id,space_id,created_by,title,details,event_date,kind,recurrence,visibility,archived_at')
            .eq('space_id', id).order('event_date').limit(500),
        _client.from('tasks')
            .select('id,title,target_date,status,visibility,created_by')
            .eq('space_id', id).eq('status', 'open').limit(500),
      ]).timeout(const Duration(seconds: 15));
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _events = results[0];
        _tasks = results[1];
        _loading = false;
      });
      PerformanceTimings.instance.record('Calendar first data', stopwatch.elapsed);
    } on PostgrestException catch (e) {
      if (mounted && version == _loadVersion) {
        setState(() { _error = e.message; _loading = false; });
      }
    } catch (_) {
      if (mounted && version == _loadVersion) {
        setState(() {
          _error = tr(context, 'loadFailed');
          _loading = false;
        });
      }
    }
  }

  DateTime? _eventDate(Map<String, dynamic> entry) =>
      DateTime.tryParse(entry['event_date'] as String? ?? '');

  bool _occurs(Map<String,dynamic> entry, DateTime day) {
    final date = _eventDate(entry);
    return date != null && CalendarRules.occursOn(
      original: date,
      recurrence: entry['recurrence'] as String? ?? 'none',
      selected: day,
    );
  }

  List<Map<String, dynamic>> _entriesOn(DateTime day) =>
    _events.where((e) => (_showArchived || e['archived_at'] == null)
        && _occurs(e, day)).toList();

  List<Map<String, dynamic>> _tasksOn(DateTime day) {
    final date = CalendarRules.sqlDate(day);
    return _tasks.where((e) => e['target_date'] == date).toList();
  }

  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    if (_spaceId == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CalendarEventEditor(
          spaceId: _spaceId!,
          initialDate: _selected,
          existing: existing,
        ),
      ),
    );
    if (mounted && changed == true) await _load();
  }

  Widget _monthGrid() {
    final first = DateTime(_month.year, _month.month);
    final offset = first.weekday % 7; // Sunday is the first day of the week.
    final weekdays = [
      tr(context, 'sun'), tr(context, 'mon'), tr(context, 'tue'),
      tr(context, 'wed'), tr(context, 'thu'), tr(context, 'fri'),
      tr(context, 'sat'),
    ];
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: tr(context, 'previousMonth'),
              onPressed: () => setState(() {
                _month = DateTime(_month.year, _month.month - 1);
              }),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                MaterialLocalizations.of(context).formatMonthYear(_month),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: tr(context, 'nextMonth'),
              onPressed: () => setState(() {
                _month = DateTime(_month.year, _month.month + 1);
              }),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(children: [
          for (final label in weekdays)
            Expanded(child: Center(child: Text(label,
              style: Theme.of(context).textTheme.labelSmall))),
        ]),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 42,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7, childAspectRatio: 0.96,
          ),
          itemBuilder: (context, index) {
            final date = DateTime(_month.year, _month.month, index + 1 - offset);
            final selected = CalendarRules.day(date) == _selected;
            final today = CalendarRules.day(date) ==
                CalendarRules.day(DateTime.now());
            final currentMonth = date.month == _month.month;
            final hasEvent = _events.any((entry) =>
                entry['archived_at'] == null && _occurs(entry, date));
            final hasTask = _tasksOn(date).isNotEmpty;
            return InkWell(
              key: Key('day-${CalendarRules.sqlDate(date)}'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _selected = CalendarRules.day(date)),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF167E81) : null,
                  border: today && !selected
                      ? Border.all(color: const Color(0xFF167E81)) : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${date.day}',
                      style: TextStyle(
                        fontWeight: today || selected
                            ? FontWeight.bold : FontWeight.normal,
                        color: selected
                            ? Colors.white
                            : currentMonth ? null : Colors.grey,
                      ),
                    ),
                    if (hasEvent || hasTask)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (hasEvent) Icon(Icons.circle, size: 7,
                            color: selected ? Colors.white
                                : const Color(0xFF167E81)),
                          if (hasTask) Icon(Icons.circle, size: 7,
                            color: selected ? Colors.white70
                                : const Color(0xFFC47D25)),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _eventTile(Map<String, dynamic> event, {bool upcoming = false}) {
    final id = _client.auth.currentUser?.id ?? '';
    final visibility = event['visibility'] as String? ?? 'shared';
    final creator = event['created_by'] as String? ?? '';
    final canEdit = ObjectPermissions.canEdit(
      visibility: visibility, createdBy: creator, userId: id);
    final canShare = ObjectPermissions.canManagePrivateShare(
      visibility: visibility, createdBy: creator, userId: id);
    final sourceDate = _eventDate(event);
    final next = sourceDate == null ? null : CalendarRules.nextOccurrence(
      original: sourceDate,
      recurrence: event['recurrence'] as String? ?? 'none',
      today: DateTime.now(),
    );
    final countdown = next == null ? '' :
        '${CalendarRules.calendarDaysUntil(DateTime.now(),next)} '
            '${tr(context, 'daysAway')}';
    return Card(
      elevation: 0,
      child: Column(
        children: [
          ListTile(
            leading: Icon(event['kind'] == 'occasion'
                ? Icons.celebration_outlined : Icons.event_outlined),
            title: Text(event['title'] as String? ?? ''),
            subtitle: Text([
              tr(context,event['kind'] as String? ?? 'event'),
              if (upcoming && countdown.isNotEmpty) countdown,
              if (!upcoming && sourceDate != null)
                CalendarRules.sqlDate(sourceDate),
              if (event['recurrence'] == 'yearly') tr(context, 'yearly'),
              if (visibility == 'private') tr(context, 'private'),
              if (!canEdit) tr(context, 'viewOnly'),
              if (event['archived_at'] != null) tr(context, 'archived'),
            ].join(' • ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openEditor(existing: event),
          ),
          if (canShare)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: PrivateShareButton(
                objectType: 'event',
                objectId: event['id'] as String,
                onChanged: _load,
              ),
            ),
        ],
      ),
    );
  }

  Widget _selectedDay() {
    final events = _entriesOn(_selected);
    final tasks = _tasksOn(_selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(CalendarRules.sqlDate(_selected),
          style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        if (events.isEmpty && tasks.isEmpty)
          Text(tr(context, 'noEventsOnDay')),
        ...events.map((e) => _eventTile(e)),
        ...tasks.map((task) => Card(
          elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.checklist_outlined),
            title: Text(task['title'] as String? ?? ''),
            subtitle: Text(tr(context, 'taskDue')),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onOpenPlans,
          ),
        )),
      ],
    );
  }

  Widget _upcoming() {
    final upcoming = <(DateTime, Map<String, dynamic>)>[];
    for (final entry in _events) {
      if (entry['archived_at'] != null) continue;
      final date = _eventDate(entry);
      if (date == null) continue;
      final next = CalendarRules.nextOccurrence(
        original: date, recurrence: entry['recurrence'] as String? ?? 'none',
        today: DateTime.now(),
      );
      if (next != null) upcoming.add((next,entry));
    }
    upcoming.sort((a,b) => a.$1.compareTo(b.$1));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr(context, 'nextOccasions'),
          style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (upcoming.isEmpty) Text(tr(context, 'noUpcomingEvents')),
        ...upcoming.take(5).map((entry) =>
            _eventTile(entry.$2, upcoming: true)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(tr(context, 'calendar'),
          style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(tr(context, 'calendarSubtitle')),
        const SizedBox(height: 14),
        if (_spaceId != null)
          FilledButton.icon(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add),
            label: Text(tr(context, 'newEvent')),
          ),
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: Colors.red)),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: Text(tr(context, 'retry')),
          ),
        ],
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_spaceId == null)
          Text(tr(context, 'noSpace'))
        else ...[
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: _monthGrid(),
            ),
          ),
          const SizedBox(height: 12),
          _selectedDay(),
          const Divider(height: 36),
          _upcoming(),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(context, 'showArchived')),
            value: _showArchived,
            onChanged: (value) => setState(() => _showArchived = value),
          ),
          if (_showArchived) ..._events.where((e) =>
              e['archived_at'] != null).map((e) => _eventTile(e)),
          const SizedBox(height: 12),
          Text(tr(context, 'calendarScopeInfo'),
            style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    ),
  );
}
