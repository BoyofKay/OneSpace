import 'package:material_ui/material_ui.dart';

import 'partner_time_zones.dart';
import 'package:onespace/l10n/phrases.dart';

/// Search the IANA zone catalogue. This requires no GPS/location permissions.
class TimeZoneSelector extends StatelessWidget {
  const TimeZoneSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final String? selected;
  final ValueChanged<String?> onChanged;

  Future<void> choose(BuildContext context) async {
    final search = TextEditingController();
    final zones = PartnerTimeZones.all();
    try {
      final selectedZone = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, update) {
            final text = search.text.trim().toLowerCase();
            final filtered = text.isEmpty
                ? zones.where((z) => [
                    'Asia/Riyadh','America/New_York','America/Los_Angeles',
                    'Europe/London','Africa/Cairo','Asia/Dubai','Etc/UTC'
                  ].contains(z)).toList()
                : zones.where((z) => z.toLowerCase().contains(text)).toList();
            return SafeArea(
              child: FractionallySizedBox(
                heightFactor: 0.75,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(children: [
                    Text(tt('Choose your time zone'),
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 5),
                    Text(tt('Search by region or city. No location access needed.'),
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    TextField(
                      controller: search,
                      autofocus: true,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: tt('Search time zones'),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => update(() {}),
                    ),
                    const SizedBox(height: 6),
                    Expanded(child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (ctx, index) {
                        final zone = filtered[index];
                        return ListTile(
                          dense: true,
                          title: Text(tt(zone.replaceAll('_',' '))),
                          trailing: zone == selected
                              ? const Icon(Icons.check) : null,
                          onTap: () => Navigator.of(sheetContext).pop(zone),
                        );
                      },
                    )),
                    if (text.isEmpty)
                      Text('${tt('Type to search all')} ${zones.length} ${tt('regions.')}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ),
            );
          },
        ),
      );
      if (selectedZone != null) onChanged(selectedZone);
    } finally {
      search.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => choose(context),
    borderRadius: BorderRadius.circular(12),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: tt('Your time zone'),
        border: OutlineInputBorder(),
        suffixIcon: Icon(Icons.travel_explore_outlined),
      ),
      child: Text(tt(selected == null
          ? 'Not set — tap to choose'
          : selected!.replaceAll('_',' '))),
    ),
  );
}
