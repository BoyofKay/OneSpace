import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:onespace/l10n/phrases.dart';
import '../../core/app_env.dart';
import '../../core/error_reporter.dart';
import 'place_location.dart';
import 'places_screen.dart';

/// OpenStreetMap tiles. The tile server requires every app to identify itself; requests from unidentified or
/// example apps get a "blocked" image. Failures are reported once per run and shown on the map screen.
class OsmTiles {
  OsmTiles._();
  static final ValueNotifier<int> failures = ValueNotifier<int>(0);
  static TileLayer layer() => TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    // Sent as "flutter_map (<id>)"; must be this app's real package id.
    userAgentPackageName: OneSpaceEnv.isProduction ? 'live.onespace.app' : 'onespace.qa',
    maxNativeZoom: 19,
    errorTileCallback: (tile, error, stack) {
      failures.value = failures.value + 1;
      ErrorReporter.report('Map tile failed to load: $error', stack, context: 'map tiles');
    },
  );
}

/// R78 (Ahmed): our places as pins on a map — hearts where we've been,
/// compasses where we dream of going. OpenStreetMap tiles (free, no key).
class PlacesMapScreen extends StatefulWidget {
  const PlacesMapScreen({super.key, required this.spaceId, required this.places, this.visits = const {}});
  final String spaceId;
  final List<Map<String, dynamic>> places;
  final Map<String, List<Map<String, dynamic>>> visits;
  @override
  State<PlacesMapScreen> createState() => _PlacesMapScreenState();
}

class _PlacesMapScreenState extends State<PlacesMapScreen> {
  String filter = 'all';
  Map<String, dynamic>? selected;
  // R83: pin a point on the map, then add it as "Been here" or to the bucket list.
  late List<Map<String, dynamic>> places = List.of(widget.places);
  LatLng? pin;
  Map<String, String>? pinInfo;
  bool pinMode = false, lookingUp = false;
  int _lookup = 0;

  Future<void> _drop(LatLng p) async {
    final ticket = ++_lookup;
    setState(() { pin = p; pinInfo = null; selected = null; pinMode = false; lookingUp = true; });
    final info = await PlaceLocator.reverse(p.latitude, p.longitude,
      language: Localizations.localeOf(context).languageCode);
    if (!mounted || ticket != _lookup) return;
    setState(() { pinInfo = info; lookingUp = false; });
  }

  Future<void> _addPinned(String status) async {
    final p = pin;
    if (p == null) return;
    final info = pinInfo ?? const <String, String>{};
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => PlaceEditor(
      spaceId: widget.spaceId, initialStatus: status,
      prefill: {'latitude': p.latitude, 'longitude': p.longitude, 'name': info['name'] ?? '',
        'city': info['city'] ?? '', 'country': info['country'] ?? '', 'address': info['address'] ?? ''})));
    if (ok != true || !mounted) return;
    setState(() { pin = null; pinInfo = null; });
    try {
      final rows = await Supabase.instance.client.from('places').select()
        .eq('space_id', widget.spaceId).isFilter('archived_at', null);
      if (mounted) setState(() => places = List<Map<String, dynamic>>.from(rows));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final located = places.where((p) => p['latitude'] != null && p['longitude'] != null).toList();
    final shown = located.where((p) => filter == 'all' || p['status'] == filter).toList();
    final missing = places.length - located.length;
    final points = [for (final p in shown) LatLng((p['latitude'] as num).toDouble(), (p['longitude'] as num).toDouble())];
    final distinct = points.map((p) => '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}').toSet();
    final options = MapOptions(
      initialCenter: points.isEmpty ? const LatLng(24.7136, 46.6753) : points.first,
      initialZoom: points.isEmpty ? 3 : 13,
      initialCameraFit: distinct.length > 1
        ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(56), maxZoom: 15)
        : null,
      onTap: (_, p) { if (pinMode) { _drop(p); } else { setState(() { selected = null; pin = null; }); } },
      onLongPress: (_, p) => _drop(p),
    );
    return Scaffold(
      appBar: AppBar(title: Text(tt('Our map'))),
      floatingActionButton: pin != null || selected != null ? null : FloatingActionButton.extended(
        onPressed: () => setState(() => pinMode = !pinMode),
        icon: Icon(pinMode ? Icons.close : Icons.add_location_alt_outlined),
        label: Text(tt(pinMode ? 'Cancel' : 'Pin a place'))),
      body: Stack(children: [
        FlutterMap(
          key: ValueKey(filter),
          options: options,
          children: [
            OsmTiles.layer(),
            MarkerLayer(markers: [
              for (var i = 0; i < shown.length; i++) Marker(
                point: points[i], width: 46, height: 46, alignment: Alignment.topCenter,
                child: GestureDetector(
                  onTap: () => setState(() { selected = shown[i]; pin = null; pinMode = false; }),
                  child: Icon(shown[i]['status'] == 'wishlist' ? Icons.explore : Icons.favorite,
                    size: selected == shown[i] ? 44 : 36,
                    color: shown[i]['status'] == 'wishlist' ? theme.colorScheme.tertiary : Colors.redAccent,
                    shadows: const [Shadow(blurRadius: 4, color: Colors.black38)]))),
              if (pin != null) Marker(point: pin!, width: 48, height: 48, alignment: Alignment.topCenter,
                child: Icon(Icons.location_on, size: 46, color: theme.colorScheme.primary,
                  shadows: const [Shadow(blurRadius: 4, color: Colors.black38)])),
            ]),
            RichAttributionWidget(attributions: [
              TextSourceAttribution('OpenStreetMap contributors',
                onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright'))),
            ]),
          ]),
        Positioned(top: 8, left: 8, right: 8, child: Wrap(spacing: 6, children: [
          for (final e in const {'all': 'All', 'visited': 'Been there', 'wishlist': 'Bucket list'}.entries)
            ChoiceChip(label: Text(tt(e.value)), selected: filter == e.key,
              onSelected: (_) => setState(() { filter = e.key; selected = null; })),
        ])),
        if (pinMode) Positioned(top: 56, left: 12, right: 12, child: Card(color: theme.colorScheme.primaryContainer,
          child: Padding(padding: const EdgeInsets.all(12),
            child: Text(tt('Tap the map where the place is. Tip: you can also press and hold anywhere.'))))),
        if (pin != null) Positioned(bottom: 16, left: 12, right: 12, child: Card(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(
                lookingUp ? tt('Finding what is here…')
                  : (pinInfo?['name'] ?? '').isNotEmpty ? pinInfo!['name']!
                  : [pinInfo?['city'], pinInfo?['country']].where((x) => (x ?? '').isNotEmpty).join(', ').isNotEmpty
                    ? [pinInfo?['city'], pinInfo?['country']].where((x) => (x ?? '').isNotEmpty).join(', ')
                    : tt('Pinned place'),
                style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
              IconButton(tooltip: tt('Remove pin'), icon: const Icon(Icons.close),
                onPressed: () => setState(() { pin = null; pinInfo = null; })),
            ]),
            Text('${pin!.latitude.toStringAsFixed(5)}, ${pin!.longitude.toStringAsFixed(5)}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(onPressed: () => _addPinned('visited'),
                icon: const Icon(Icons.favorite), label: Text(tt('Been here'))),
              FilledButton.tonalIcon(onPressed: () => _addPinned('wishlist'),
                icon: const Icon(Icons.explore), label: Text(tt('Add to bucket list'))),
            ]),
          ])))),
        if (missing > 0 && selected == null && pin == null && !pinMode) Positioned(bottom: 16, left: 12, right: 12, child: Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(tt(missing == 1 ? '1 place is not on the map yet — open it, tap Edit and Find.'
              : '{} places are not on the map yet — open them, tap Edit and Find.').replaceFirst('{}', '$missing'))))),
        ValueListenableBuilder<int>(valueListenable: OsmTiles.failures, builder: (context, n, _) => n < 3
          ? const SizedBox.shrink()
          : Positioned(top: 56, left: 12, right: 12, child: Card(color: theme.colorScheme.errorContainer, child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(tt('The map pictures could not load. Check your internet connection and try again.')))))),
        if (points.isEmpty && missing == 0) Center(child: Card(child: Padding(padding: const EdgeInsets.all(16),
          child: Text(tt('Add places to see them here.'))))),
        if (selected != null) Positioned(bottom: 16, left: 12, right: 12, child: Card(child: ListTile(
          leading: Icon(PlaceCategories.icon(selected!['category'])),
          title: Text(selected!['name'].toString()),
          subtitle: Text([
            tt(selected!['status'] == 'wishlist' ? 'Bucket list' : 'Been there'),
            if (PlaceRules.where(selected!).isNotEmpty) PlaceRules.where(selected!),
            if ((widget.visits[selected!['id'].toString()] ?? const []).isNotEmpty)
              tt('{} visits').replaceFirst('{}', '${widget.visits[selected!['id'].toString()]!.length}'),
          ].join(' · ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => PlaceDetail(placeId: selected!['id'].toString(), spaceId: widget.spaceId)))))),
      ]),
    );
  }
}

/// A small map on a place's page.
class PlaceMiniMap extends StatelessWidget {
  const PlaceMiniMap({super.key, required this.latitude, required this.longitude, this.wishlist = false, this.onTap});
  final double latitude, longitude;
  final bool wishlist;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(height: 170, child: FlutterMap(
      options: MapOptions(initialCenter: LatLng(latitude, longitude), initialZoom: 14,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
        onTap: onTap == null ? null : (_, __) => onTap!()),
      children: [
        OsmTiles.layer(),
        MarkerLayer(markers: [Marker(point: LatLng(latitude, longitude), width: 40, height: 40,
          alignment: Alignment.topCenter,
          child: Icon(wishlist ? Icons.explore : Icons.favorite, size: 36,
            color: wishlist ? Theme.of(context).colorScheme.tertiary : Colors.redAccent))]),
        const SimpleAttributionWidget(source: Text('OpenStreetMap')),
      ])),
  );
}
