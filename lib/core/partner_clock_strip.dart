import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'partner_time_zones.dart';
import 'shared_weather.dart';

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
    final hint = knownDifference == null ? '' : PartnerTimeZones.differenceLabel(knownDifference);

    Widget weatherLine(Map<String, dynamic>? member) {
      if (member == null) return const SizedBox.shrink();
      if (member['city_weather_shared'] != true) {
        return Text(
          member['is_me'] == true
            ? 'Choose a city in Profile to share its weather.'
            : "Your partner has not selected a shared weather city.",
          style: Theme.of(context).textTheme.bodySmall,
        );
      }
      final city = member['city_name']?.toString() ?? 'City unavailable';
      final rawTemp = member['temperature_c'];
      final temp = rawTemp is num ? rawTemp.toStringAsFixed(0)
        : rawTemp?.toString() ?? '—';
      final rawCode = member['weather_code'];
      final code = rawCode is num ? rawCode.toInt()
        : int.tryParse(rawCode?.toString() ?? '');
      final high=member['weather_high_c'];
      final low=member['weather_low_c'];
      final rain=member['weather_rain_pct'];
      final last = DateTime.tryParse(
        member['weather_updated_at']?.toString() ?? '');
      final stale = last == null ||
          DateTime.now().difference(last.toLocal()) >
              const Duration(hours: 2);
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start,children: [
          const Icon(Icons.cloud_outlined, size: 17),
          const SizedBox(width: 6),
          Expanded(child: Text(
            '${member['name'] ?? 'Partner'} · $city · $temp°C'
            '${code == null ? '' : ' · ${SharedWeather.condition(code)}'}'
            '${high is num && low is num ? ' · H ${high.toStringAsFixed(0)}° / L ${low.toStringAsFixed(0)}°' : ''}'
            '${rain is num ? ' · Rain ${rain.toStringAsFixed(0)}%' : ''}'
            '${stale ? ' · Weather may be outdated' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          )),
        ]),
      );
    }

    Widget clock(String label, String? zone, DateTime? time, {
      bool myClock = false,
    }) {
      final deviceTime = myClock && time == null ? now : time;
      final zoneLabel = time != null && zone != null
          ? '${PartnerTimeZones.zoneLabel(zone)} · '
            '${PartnerTimeZones.offsetLabel(time.timeZoneOffset)}'
          : myClock ? 'This phone · syncing time zone' : 'Waiting for phone';
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
              Text(deviceTime == null ? "Waiting for partner's phone" :
                    PartnerTimeZones.dateLabel(deviceTime),
                style: Theme.of(context).textTheme.bodySmall),
              Text(zoneLabel, maxLines: 2,
                style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      );
    }

    return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              clock(mine?['name']?.toString() ?? 'You', mineZone, mineTime,
                myClock: true),
              if (!livingTogether && partner != null) ...[
                const SizedBox(width: 6),
                clock(partner['name']?.toString() ?? 'Partner',
                  theirZone, theirTime),
              ],
            ]),
            const SizedBox(height: 6),
            if (!livingTogether) ...[
              weatherLine(mine),
              if (partner != null) weatherLine(partner),
            ],
            if (!livingTogether && (mine?['city_weather_shared'] == true ||
                partner?['city_weather_shared'] == true))
              Align(alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: () => unawaited(launchUrl(
                    Uri.parse('https://open-meteo.com/'),
                    mode: LaunchMode.externalApplication)),
                  child: Text('Weather data by Open-Meteo.com',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      decoration: TextDecoration.underline,
                    )),
                )),

            if (!livingTogether && partner != null && hint.isNotEmpty
                && knownDifference != 0) ...[
              const SizedBox(height: 5),
              Text(hint, style: Theme.of(context).textTheme.bodySmall),
              if (widget.relationshipMode == 'apart_same_tz' &&
                  knownDifference != null && knownDifference != 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Your device zones differ. Check your '
                    'relationship setting or time zones.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ],
        ),
    );
  }
}
