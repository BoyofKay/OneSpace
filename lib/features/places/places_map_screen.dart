import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:onespace/l10n/phrases.dart';
import '../../core/app_env.dart';
import '../../core/error_reporter.dart';
import '../../core/form_kit.dart';
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

/// Category icon = what sort of place; coral = visited, teal = bucket list.
/// Partner-coloured initial badges show who can see a pin: both for shared,
/// only the creator for a private place. Never imply that the creator visited it.
class PlaceMapPin extends StatelessWidget {
  const PlaceMapPin({super.key, required this.place, this.selected = false,
    this.meInitial = 'M', this.partnerInitial = 'P', this.showPeople = true,
    this.hasPartner = true});
  final Map<String, dynamic> place;
  final bool selected, showPeople, hasPartner;
  final String meInitial, partnerInitial;

  static const visitedColor = Color(0xFFC14C55);
  static const wishlistColor = Color(0xFF087D83);
  static const meColor = Color(0xFF3C59A8);
  static const partnerColor = Color(0xFF9A4B7A);

  Widget _initial(String value, Color color) => Container(
    width: 20, height: 20,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1.5)),
    alignment: Alignment.center,
    child: Text(value.isEmpty ? '?' : value.substring(0, 1).toUpperCase(),
      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)));

  @override
  Widget build(BuildContext context) {
    final visited = place['status'] != 'wishlist';
    final shared = place['visibility'] != 'private';
    final status = tt(visited ? 'Been there' : 'Bucket list');
    final kind = tt(PlaceCategories.labels[place['category']] ?? 'Place');
    return Semantics(label: '${place['name'] ?? kind}, $kind, $status, '
      '${tt(shared ? 'Shared' : 'Only me')}',
      child: SizedBox(width: 62, height: 62, child: Stack(
        alignment: Alignment.topCenter, children: [
          Container(width: selected ? 50 : 46, height: selected ? 50 : 46,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: visited ? visitedColor : wishlistColor,
              borderRadius: BorderRadius.circular(visited ? 25 : 12),
              border: Border.all(color: Colors.white, width: selected ? 3 : 2),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6,
                offset: Offset(0, 3))]),
            child: Icon(PlaceCategories.icon(place['category']), color: Colors.white,
              size: selected ? 28 : 25)),
          if (showPeople) Positioned(bottom: 3, child: Row(
            mainAxisSize: MainAxisSize.min,
            children: shared
              ? [_initial(meInitial, meColor), if (hasPartner) _initial(partnerInitial, partnerColor)]
              : [_initial(meInitial, meColor)])),
        ])));
  }
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
  String _meInitial = 'M', _partnerInitial = 'P';
  bool _hasPartner = false;
  /// A new controller whenever the map is rebuilt for another filter.
  MapController _map = MapController();
  LatLng? _me;
  bool _locating = false;
  double _rotation = 0;

  Future<void> _locateMe() async {
    if (_locating) return;
    setState(() => _locating = true);
    String? problem;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        problem = 'Turn on location on your phone to see where you are.';
      } else {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          problem = 'Allow location for OneSpace in your phone settings to see where you are.';
        } else {
          final at = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 15)));
          if (!mounted) return;
          final here = LatLng(at.latitude, at.longitude);
          setState(() => _me = here);
          _map.move(here, 15);
        }
      }
    } catch (_) {
      problem = 'Your location could not be found. Try again outside or near a window.';
    } finally {
      if (mounted) setState(() => _locating = false);
    }
    if (problem != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tt(problem))));
    }
  }

  Future<void> _search() async {
    final text = TextEditingController();
    final query = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(scrollable:true,
      title: Text(tt('Search the map')),
      content: TextField(controller: text, autofocus: true, textInputAction: TextInputAction.search,
        decoration: InputDecoration(hintText: tt('A place, street or city'),
          prefixIcon: const Icon(Icons.search)),
        onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tt('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, text.text), child: Text(tt('Search'))),
      ]));
    text.dispose();
    final q = (query ?? '').trim();
    if (q.isEmpty || !mounted) return;
    final hit = await PlaceLocator.search(q);
    if (!mounted) return;
    if (hit == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tt('Nothing found. Try adding the city or country.'))));
      return;
    }
    final at = LatLng(hit.latitude, hit.longitude);
    _map.move(at, 15);
    await _drop(at);
  }

  @override
  void initState() {
    super.initState();
    _loadInitials();
  }

  Future<void> _loadInitials() async {
    final people = await SpacePeople.load();
    if (!mounted || people == null) return;
    var mine = 'M';
    try {
      final profile = await Supabase.instance.client.from('profiles')
        .select('display_name').eq('id', people.me).maybeSingle();
      final value = (profile?['display_name'] ?? '').toString().trim();
      if (value.isNotEmpty) mine = value.substring(0, 1).toUpperCase();
    } catch (_) {}
    if (mounted) setState(() {
      _meInitial = mine;
      _hasPartner = people.partnerId != null;
      final partner = people.partnerName.trim();
      _partnerInitial = partner.isEmpty ? 'P' : partner.substring(0, 1).toUpperCase();
    });
  }

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
      final query=OneSpaceEnv.usesLegacyBackend
        ? Supabase.instance.client.from('places').select()
          .eq('space_id',widget.spaceId)
        : Supabase.instance.client.from('places').select();
      final rows=await query.isFilter('archived_at',null);
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
      onPositionChanged: (camera, _) {
        if ((camera.rotation - _rotation).abs() > 1) setState(() => _rotation = camera.rotation);
      },
    );
    return Scaffold(
      appBar: AppBar(title: Text(tt('Our map')), actions: [
        IconButton(tooltip: tt('Search the map'), icon: const Icon(Icons.search), onPressed: _search),
      ]),
      floatingActionButton: pin != null || selected != null ? null : FloatingActionButton.extended(
        onPressed: () => setState(() => pinMode = !pinMode),
        icon: Icon(pinMode ? Icons.close : Icons.add_location_alt_outlined),
        label: Text(tt(pinMode ? 'Cancel' : 'Pin a place'))),
      body: Stack(children: [
        FlutterMap(
          key: ValueKey(filter),
          mapController: _map,
          options: options,
          children: [
            OsmTiles.layer(),
            MarkerLayer(markers: [
              for (var i = 0; i < shown.length; i++) Marker(
                point: points[i], width: 62, height: 62, alignment: Alignment.topCenter,
                child: GestureDetector(
                  onTap: () => setState(() { selected = shown[i]; pin = null; pinMode = false; }),
                  child: PlaceMapPin(place: shown[i], selected: selected == shown[i],
                    meInitial: _meInitial, partnerInitial: _partnerInitial,
                    hasPartner: _hasPartner))),
              if (_me != null) Marker(point: _me!, width: 22, height: 22,
                child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle,
                  color: Colors.blue, border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)]))),
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
              onSelected: (_) => setState(() { filter = e.key; selected = null; _map = MapController(); _rotation = 0; })),
        ])),
        Positioned(top: 53, left: 8, right: 8,
          child: IgnorePointer(child: Center(child: DecoratedBox(
            decoration: BoxDecoration(color: theme.colorScheme.surface.withValues(alpha: .94),
              borderRadius: BorderRadius.circular(12)),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.check_circle, size: 15, color: PlaceMapPin.visitedColor),
                    const SizedBox(width: 4), Text(tt('Been there'), style: theme.textTheme.labelSmall)]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.bookmark, size: 15, color: PlaceMapPin.wishlistColor),
                    const SizedBox(width: 4), Text(tt('Bucket list'), style: theme.textTheme.labelSmall)]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.people_outline, size: 15),
                    const SizedBox(width: 4), Text(tt('Initials = who can see it'),
                      style: theme.textTheme.labelSmall)]),
                ])))))),
        if (pinMode) Positioned(top: 102, left: 12, right: 12, child: Card(color: theme.colorScheme.primaryContainer,
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
          : Positioned(top: 102, left: 12, right: 12, child: Card(color: theme.colorScheme.errorContainer, child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(tt('The map pictures could not load. Check your internet connection and try again.')))))),
        // Map controls: north up and my location.
        Positioned(right: 12, bottom: pin != null || selected != null ? 170 : 96,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FloatingActionButton.small(heroTag: 'map-north', tooltip: tt('Point north'),
              onPressed: () { _map.rotate(0); setState(() => _rotation = 0); },
              child: Transform.rotate(angle: -_rotation * 3.1415926535 / 180,
                child: const Icon(Icons.navigation_outlined))),
            const SizedBox(height: 8),
            FloatingActionButton.small(heroTag: 'map-me', tooltip: tt('Show my location'),
              onPressed: _locating ? null : _locateMe,
              child: _locating ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location)),
          ])),
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
  const PlaceMiniMap({super.key, required this.latitude, required this.longitude,
    this.wishlist = false, this.category = 'other', this.onTap});
  final double latitude, longitude;
  final bool wishlist;
  final String category;
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
        MarkerLayer(markers: [Marker(point: LatLng(latitude, longitude), width: 62, height: 62,
          alignment: Alignment.topCenter, child: PlaceMapPin(
            place: {'status': wishlist ? 'wishlist' : 'visited', 'category': category},
            showPeople: false))]),
        const SimpleAttributionWidget(source: Text('OpenStreetMap')),
      ])),
  );
}
