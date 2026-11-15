import 'package:material_ui/material_ui.dart';
import 'package:onespace/l10n/phrases.dart';

import 'airports.dart';

/// R67: picks an airport and stores its 3-letter code (as Google Flights does).
class AirportField extends StatefulWidget {
  const AirportField({super.key, required this.label, required this.value,
    required this.onChanged, this.icon = Icons.flight_takeoff_outlined});
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final IconData icon;
  @override
  State<AirportField> createState() => _AirportFieldState();
}

class _AirportFieldState extends State<AirportField> {
  @override
  void initState() {
    super.initState();
    Airports.load().then((_) { if (mounted) setState(() {}); });
  }

  Future<void> pick() async {
    final all = await Airports.load();
    if (!mounted) return;
    final code = await showModalBottomSheet<String>(context: context, isScrollControlled: true,
      showDragHandle: true, builder: (_) => _AirportSheet(all: all, title: widget.label));
    if (code != null) widget.onChanged(code);
  }

  @override
  Widget build(BuildContext context) {
    final v = (widget.value ?? '').trim();
    final known = Airports.byCode(v);
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: pick,
      child: InputDecorator(
        decoration: InputDecoration(labelText: widget.label, prefixIcon: Icon(widget.icon),
          suffixIcon: v.isEmpty ? const Icon(Icons.search)
            : IconButton(tooltip: tt('Clear'), icon: const Icon(Icons.close),
                onPressed: () => widget.onChanged(null)),
          border: const OutlineInputBorder()),
        child: v.isEmpty
          ? Text(tt('Choose an airport'), style: TextStyle(color: Theme.of(context).hintColor))
          : Text(known == null ? v : '${known.code} · ${tt(known.city)}',
              style: Theme.of(context).textTheme.bodyLarge))));
  }
}

class _AirportSheet extends StatefulWidget {
  const _AirportSheet({required this.all, required this.title});
  final List<Airport> all;
  final String title;
  @override
  State<_AirportSheet> createState() => _AirportSheetState();
}

class _AirportSheetState extends State<_AirportSheet> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final hits = Airports.search(widget.all, query, limit: 30);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(height: MediaQuery.of(context).size.height * .75, child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: TextField(
          autofocus: true,
          onChanged: (v) => setState(() => query = v),
          decoration: InputDecoration(labelText: widget.title, prefixIcon: const Icon(Icons.search),
            hintText: tt('City, airport or code (RUH)'), border: const OutlineInputBorder()))),
        Expanded(child: query.trim().isEmpty
          ? Padding(padding: const EdgeInsets.all(24),
              child: Text(tt('Type a city, an airport or its 3-letter code.')))
          : hits.isEmpty
            ? Padding(padding: const EdgeInsets.all(24), child: Text(tt('No airport found.')))
            : ListView(children: [
                for (final a in hits) ListTile(
                  leading: CircleAvatar(child: Text(a.code, style: const TextStyle(fontSize: 12))),
                  title: Text(tt(a.city.isEmpty ? a.name : a.city)),
                  subtitle: Text('${a.name} · ${a.country}'),
                  onTap: () => Navigator.pop(context, a.code)),
              ])),
      ])));
  }
}

/// R67: a small number with − and + (passengers, bags).
class CountStepper extends StatelessWidget {
  const CountStepper({super.key, required this.label, required this.value,
    required this.onChanged, this.min = 0, this.max = 9, this.icon, this.help});
  final String label;
  final int value, min, max;
  final ValueChanged<int> onChanged;
  final IconData? icon;
  final String? help;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      if (icon != null) Padding(padding: const EdgeInsetsDirectional.only(end: 10),
        child: Icon(icon, size: 20)),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tt(label), style: Theme.of(context).textTheme.bodyLarge),
        if (help != null) Text(tt(help!), style: Theme.of(context).textTheme.bodySmall),
      ])),
      IconButton.outlined(tooltip: tt('Less'), icon: const Icon(Icons.remove, size: 18),
        onPressed: value > min ? () => onChanged(value - 1) : null),
      SizedBox(width: 34, child: Text('$value', textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium)),
      IconButton.outlined(tooltip: tt('More'), icon: const Icon(Icons.add, size: 18),
        onPressed: value < max ? () => onChanged(value + 1) : null),
    ]));
}
