import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:onespace/l10n/phrases.dart';
import '../../core/app_env.dart';
import '../../core/error_reporter.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final located = widget.places.where((p) => p['latitude'] != null && p['longitude'] != null).toList();
    final shown = located.where((p) => filter == 'all' || p['status'] == filter).toList();
    final missing = widget.places.length - located.length;
    final points = [for (final p in shown) LatLng((p['latitude'] as num).toDouble(), (p['longitude'] as num).toDouble())];
    final distinct = points.map((p) => '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}').toSet();
    final options = MapOptions(
      initialCenter: points.isEmpty ? const LatLng(24.7136, 46.6753) : points.first,
      initialZoom: points.isEmpty ? 3 : 13,
      initialCameraFit: distinct.length > 1
        ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(56), maxZoom: 15)
        : null,
      onTap: (_, __) => setState(() => selected = null),
    );
    return Scaffold(
      appBar: AppBar(title: Text(tt('Our map'))),
      body: Stack(children: [
        FlutterMap(
          key: ValueKey('$filter-${points.length}'),
          options: options,
          children: [
            OsmTiles.layer(),
            MarkerLayer(markers: [
              for (var i = 0; i < shown.length; i++) Marker(
                point: points[i], width: 46, height: 46, alignment: Alignment.topCenter,
                child: GestureDetector(
                  onTap: () => setState(() => selected = shown[i]),
                  child: Icon(shown[i]['status'] == 'wishlist' ? Icons.explore : Icons.favorite,
                    size: selected == shown[i] ? 44 : 36,
                    color: shown[i]['status'] == 'wishlist' ? theme.colorScheme.tertiary : Colors.redAccent,
                    shadows: const [Shadow(blurRadius: 4, color: Colors.black38)]))),
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
        if (missing > 0 && selected == null) Positioned(bottom: 16, left: 12, right: 12, child: Card(child: Padding(
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
