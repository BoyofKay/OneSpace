import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'partner_time_zones.dart';

/// Clock display uses the existing Today snapshot, never a new API request.
/// DST and the current day are derived from the same UTC instant.
class PartnerClockStrip extends StatefulWidget {
  const PartnerClockStrip({
    super.key,
    required this.members,
    required this.relationshipMode,
    this.onConfigure,
  });

  final List<Map<String, dynamic>> members;
  final String relationshipMode;
  final VoidCallback? onConfigure;

  @override
  State<PartnerClockStrip> createState() => _PartnerClockStripState();
}

class _PartnerClockStripState extends State<PartnerClockStrip> {
  Timer? refresh;

  @override
  void initState() {
    super.initState();
    refresh = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final me = widget.members.where((m) => m['is_me'] == true).toList();
    final them = widget.members.where((m) => m['is_me'] != true).toList();
    final mine = me.isNotEmpty ? me.first : null;
    final partner = them.isNotEmpty ? them.first : null;
    final mineZone = mine?['time_zone']?.toString();
    final theirZone = partner?['time_zone']?.toString();
    final mineTime = PartnerTimeZones.inZone(mineZone, now);
    final theirTime = PartnerTimeZones.inZone(theirZone, now);
    final livingTogether = widget.relationshipMode == 'living_together';
    final knownDifference = PartnerTimeZones.differenceHoursMinutes(
      mineZone, theirZone, now,
    );
    final hint = knownDifference == null
        ? 'Choose time zones in Profile to compare your clocks.'
        : PartnerTimeZones.differenceLabel(knownDifference);

    Widget clock(String label, String? zone, DateTime? time, {
      bool myClock = false,
    }) {
      final deviceTime = myClock && time == null ? now : time;
      final zoneLabel = time != null && zone != null
          ? '${PartnerTimeZones.zoneLabel(zone)} · '
            '${PartnerTimeZones.offsetLabel(time.timeZoneOffset)}'
          : myClock ? 'This phone · time zone not saved' : 'Time zone not set';
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge,
                maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(deviceTime == null ? '—' :
                  PartnerTimeZones.timeLabel(deviceTime),
                style: Theme.of(context).textTheme.titleLarge),
              Text(deviceTime == null ? 'Ask your partner to set their zone' :
                    PartnerTimeZones.dateLabel(deviceTime),
                style: Theme.of(context).textTheme.bodySmall),
              Text(zoneLabel, maxLines: 2,
                style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.public_outlined, size: 21),
              const SizedBox(width: 7),
              Expanded(child: Text(
                livingTogether ? 'Our local time' : 'Our clocks',
                style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                icon: const Icon(Icons.settings_outlined, size: 19),
                tooltip: 'Set my time zone in Profile',
                onPressed: widget.onConfigure,
              ),
            ]),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              clock(mine?['name']?.toString() ?? 'You', mineZone, mineTime,
                myClock: true),
              if (!livingTogether && partner != null) ...[
                const SizedBox(width: 6),
                clock(partner['name']?.toString() ?? 'Partner',
                  theirZone, theirTime),
              ],
            ]),
            if (!livingTogether && partner != null) ...[
              const SizedBox(height: 5),
              Text(hint, style: Theme.of(context).textTheme.bodySmall),
              if (widget.relationshipMode == 'apart_same_tz' &&
                  knownDifference != null && knownDifference != 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Your saved zones differ. Check your '
                    'relationship setting or time zones.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
