import 'package:material_ui/material_ui.dart';

import '../calendar/calendar_rules.dart';
import 'today_attention_rules.dart';

/// Compact, content-first agenda: actionable links to real Activities,
/// not a duplicated task database or decorative dashboard counter.
class TodayAttentionSection extends StatefulWidget {
  const TodayAttentionSection({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onSnooze,
  });

  final List<TodayAttentionItem> items;
  final void Function(String activityId) onOpen;
  final Future<void> Function(TodayAttentionItem item, int days) onSnooze;

  @override
  State<TodayAttentionSection> createState() => _TodayAttentionSectionState();
}

class _TodayAttentionSectionState extends State<TodayAttentionSection> {
  bool showAll = false;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final items = widget.items;
    final visible = showAll ? items : items.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text('Needs attention',
            style: Theme.of(context).textTheme.titleLarge)),
          if (items.isNotEmpty)
            Text('${items.length}',
              style: Theme.of(context).textTheme.labelLarge),
        ]),
        const SizedBox(height: 7),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 7, 2, 13),
            child: Text('All clear for now. New Activity deadlines '
              'and reminders will appear here.'),
          )
        else ...[
          for (final item in visible)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 5),
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(11, 0, 2, 0),
                dense: true,
                leading: Icon(
                  item.isReminder
                    ? Icons.notifications_active_outlined
                    : item.daysUntil(now) != null &&
                        item.daysUntil(now)! < 0
                        ? Icons.error_outline
                        : Icons.flag_outlined,
                  size: 21,
                  color: item.daysUntil(now) != null &&
                          item.daysUntil(now)! < 0
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                title: Text(item.title, maxLines: 2),
                subtitle: Text(
                  '${item.isReminder ? 'Reminder · ' : ''}'
                  '${item.relativeLabel(now)}',
                  style: Theme.of(context).textTheme.bodySmall),
                onTap: () => widget.onOpen(item.activityId),
                trailing: PopupMenuButton<int>(
                  tooltip: 'Snooze this item for me',
                  icon: const Icon(Icons.more_horiz,size:20),
                  onSelected: (days) => widget.onSnooze(item, days),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 1,child:Text('Hide until tomorrow')),
                    PopupMenuItem(value: 3,child:Text('Hide for 3 days')),
                    PopupMenuItem(value: 7,child:Text('Hide for 1 week')),
                  ],
                ),
              ),
            ),
          if (items.length > 4)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => showAll = !showAll),
                child: Text(showAll ? 'Show fewer'
                  : 'Show ${items.length - 4} more'),
              ),
            ),
          Text('Snooze only changes your Today view, not your '
            'partner\'s. Phone notifications are not enabled.',
            style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

class TodayCalendarSection extends StatelessWidget {
  const TodayCalendarSection({
    super.key,
    required this.entries,
    required this.onOpen,
  });

  final List<TodayCalendarEntry> entries;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final next = entries.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text('Coming up together',
            style: Theme.of(context).textTheme.titleLarge)),
          TextButton(
            onPressed: onOpen,
            child: const Text('Calendar'),
          ),
        ]),
        if (next.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('No calendar occasions in the next 7 days.'),
          )
        else
          for (final entry in next)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Icon(entry.kind == 'occasion'
                  ? Icons.celebration_outlined
                  : Icons.calendar_month_outlined,size:21),
              title: Text(entry.title,maxLines:1,
                overflow:TextOverflow.ellipsis),
              subtitle: Text(CalendarRules.sqlDate(entry.date)),
              onTap: onOpen,
            ),
      ],
    );
  }
}
