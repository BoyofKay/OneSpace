import 'package:material_ui/material_ui.dart';
import 'package:onespace/l10n/phrases.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../calendar/calendar_rules.dart';
import 'memory_photo_service.dart';
import 'memory_view_screen.dart';

/// The daily-selfie pattern: one month at a time, a small photo on each day
/// someone took a selfie (mine and, when shared, my partner's). Tap a day to
/// open that selfie.
class SelfieCalendarScreen extends StatefulWidget {
  const SelfieCalendarScreen({super.key, required this.spaceId});
  final String spaceId;
  @override
  State<SelfieCalendarScreen> createState() => _SelfieCalendarScreenState();
}

class SelfieDay {
  const SelfieDay(this.memoryId, this.createdBy, this.photoPath);
  final String memoryId, createdBy;
  final String? photoPath;
}

class _SelfieCalendarScreenState extends State<SelfieCalendarScreen> {
  final db = Supabase.instance.client;
  late final MemoryPhotoService photos = MemoryPhotoService(db);
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<int, List<SelfieDay>> days = const {};
  final Map<String, Future<String>> _urls = {};
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final end = DateTime(month.year, month.month + 1);
      // RLS returns only selfies I may see: mine, and shared ones.
      final rows = await db.from('memories').select('id,created_by,memory_date')
        .eq('memory_type', 'daily_selfie').isFilter('archived_at', null)
        .gte('memory_date', CalendarRules.sqlDate(month))
        .lt('memory_date', CalendarRules.sqlDate(end))
        .order('memory_date');
      final ids = [for (final r in rows) r['id'].toString()];
      final pics = ids.isEmpty ? const <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(await db.from('memory_photos')
            .select('memory_id,object_path,display_order').inFilter('memory_id', ids)
            .order('display_order'));
      final out = <int, List<SelfieDay>>{};
      for (final r in rows) {
        final date = DateTime.tryParse(r['memory_date']?.toString() ?? '');
        if (date == null) continue;
        final id = r['id'].toString();
        final path = pics.where((p) => p['memory_id'].toString() == id)
          .map((p) => p['object_path']?.toString()).firstOrNull;
        (out[date.day] ??= []).add(SelfieDay(id, r['created_by']?.toString() ?? '', path));
      }
      if (mounted) setState(() { days = out; loading = false; });
    } catch (_) {
      if (mounted) setState(() { loading = false; error = 'Could not load your selfies. Pull to try again.'; });
    }
  }

  Future<String> _url(String path) => _urls[path] ??= photos.signedUrl(path);

  void _shift(int by) {
    setState(() => month = DateTime(month.year, month.month + by));
    _load();
  }

  Future<void> _open(SelfieDay d) async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => MemoryViewScreen(spaceId: widget.spaceId, memoryId: d.memoryId)));
    if (mounted) _load();
  }

  Widget _thumb(SelfieDay d, double size) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Icon(Icons.photo_camera_front_outlined, size: size * .6, color: scheme.primary);
    return ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: size, height: size,
      child: d.photoPath == null ? fallback : FutureBuilder<String>(
        future: _url(d.photoPath!),
        builder: (_, s) => s.hasData
          ? Image.network(s.data!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)
          : ColoredBox(color: scheme.surfaceContainerHighest))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    final me = db.auth.currentUser?.id;
    final first = DateTime(month.year, month.month);
    final count = DateTime(month.year, month.month + 1, 0).day;
    // Monday-first grid.
    final lead = (first.weekday + 6) % 7;
    final taken = days.length;
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    return Scaffold(
      appBar: AppBar(title: Text(tt('Daily selfies'))),
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          IconButton(tooltip: tt('Previous month'), icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
          Expanded(child: Text(loc.formatMonthYear(month), textAlign: TextAlign.center, style: theme.textTheme.titleMedium)),
          IconButton(tooltip: tt('Next month'), icon: const Icon(Icons.chevron_right),
            onPressed: isCurrent ? null : () => _shift(1)),
        ]),
        Padding(padding: const EdgeInsets.only(bottom: 10),
          child: Text(tt('Days with a selfie this month: ') + '$taken', textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall)),
        Row(children: [
          for (final d in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
            Expanded(child: Text(tt(d), textAlign: TextAlign.center, style: theme.textTheme.labelSmall)),
        ]),
        const SizedBox(height: 6),
        if (loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else LayoutBuilder(builder: (context, box) {
          final cell = box.maxWidth / 7;
          return Wrap(children: [
            for (var i = 0; i < lead; i++) SizedBox(width: cell, height: cell + 14),
            for (var day = 1; day <= count; day++) SizedBox(width: cell, height: cell + 14, child: Builder(builder: (_) {
              final list = days[day] ?? const <SelfieDay>[];
              final mine = list.where((d) => d.createdBy == me).firstOrNull;
              final theirs = list.where((d) => d.createdBy != me).firstOrNull;
              final main = mine ?? theirs;
              final today = isCurrent && day == now.day;
              return InkWell(
                key: ValueKey('selfie-day-$day'),
                onTap: main == null ? null : () => _open(main),
                borderRadius: BorderRadius.circular(8),
                child: Padding(padding: const EdgeInsets.all(2), child: Column(children: [
                  Text('$day', style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: today ? FontWeight.bold : null,
                    color: today ? theme.colorScheme.primary : null)),
                  const SizedBox(height: 2),
                  Expanded(child: main == null
                    ? Center(child: Container(width: 6, height: 6, decoration: BoxDecoration(
                        shape: BoxShape.circle, color: theme.colorScheme.outlineVariant)))
                    : Stack(clipBehavior: Clip.none, children: [
                        Positioned.fill(child: _thumb(main, cell)),
                        if (mine != null && theirs != null) Positioned(right: -2, bottom: -2,
                          child: GestureDetector(onTap: () => _open(theirs), child: Container(
                            decoration: BoxDecoration(border: Border.all(color: theme.colorScheme.surface, width: 2),
                              borderRadius: BorderRadius.circular(6)),
                            child: _thumb(theirs, cell * .45)))),
                      ])),
                ])));
            })),
          ]);
        }),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text(tt(error!), style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: 12),
        Text(tt('Tap a day to open that selfie. A small photo in the corner is your partner’s.'),
          style: theme.textTheme.bodySmall),
      ])));
  }
}
