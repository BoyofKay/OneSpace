import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:onespace/l10n/phrases.dart';
import '../../core/current_space_cache.dart';
import '../../core/app_env.dart';
import '../../core/editor_scaffold.dart';
import '../../core/form_kit.dart';
import '../../core/item_menu.dart';
import '../calendar/calendar_rules.dart';
import '../counters/smart_duration.dart';
import '../memories/memories_screen.dart';
import '../memories/memory_view_screen.dart';
import '../world/trips_screen.dart';
import 'place_location.dart';
import 'places_map_screen.dart';

/// R77 (Ahmed's friend's idea): our places — where we've been together
/// (visits with dates, captions, photos and stories) and our bucket list.
/// Pick one or more bucket-list places to plan a trip.
class PlaceCategories {
  const PlaceCategories._();
  static const labels = {
    'restaurant': 'Restaurant', 'cafe': 'Café', 'city': 'City', 'beach': 'Beach', 'nature': 'Nature',
    'hotel': 'Stay', 'landmark': 'Landmark', 'shopping': 'Shopping', 'activity': 'Activity',
    'home': 'Home', 'other': 'Other'};
  static const icons = {
    'restaurant': Icons.restaurant_outlined, 'cafe': Icons.local_cafe_outlined,
    'city': Icons.location_city_outlined, 'beach': Icons.beach_access_outlined,
    'nature': Icons.park_outlined, 'hotel': Icons.hotel_outlined, 'landmark': Icons.account_balance_outlined,
    'shopping': Icons.shopping_bag_outlined, 'activity': Icons.attractions_outlined,
    'home': Icons.home_outlined, 'other': Icons.place_outlined};
  static IconData icon(Object? c) => icons[c] ?? Icons.place_outlined;
}

class PlaceRules {
  const PlaceRules._();
  /// "Paris, France"
  static String where(Map<String, dynamic> p) =>
    [p['city'], p['country']].map((x) => (x ?? '').toString().trim()).where((x) => x.isNotEmpty).join(', ');

  /// Title and notes for a trip planned from bucket-list places.
  static Map<String, String> tripPrefill(List<Map<String, dynamic>> places) {
    final names = places.map((p) => p['name'].toString()).toList();
    final cities = places.map((p) => (p['city'] ?? '').toString().trim()).where((c) => c.isNotEmpty).toSet();
    final sameCity = cities.length == 1 && places.every((p) => (p['city'] ?? '').toString().trim() == cities.first);
    final title = sameCity ? 'Trip to ${cities.first}'
      : names.length == 1 ? 'Trip to ${names.first}'
      : 'Trip to ${names.take(2).join(' & ')}${names.length > 2 ? ' +${names.length - 2}' : ''}';
    final notes = [
      'From our bucket list:',
      for (final p in places) '• ${p['name']}${where(p).isEmpty ? '' : ' — ${where(p)}'}',
    ].join('\n');
    return {'title': title, 'notes': notes};
  }
}

class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key, this.initialId});
  final String? initialId;
  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> with SingleTickerProviderStateMixin {
  final db = Supabase.instance.client;
  late final TabController tabs = TabController(length: 2, vsync: this)..addListener(() {
    if (!tabs.indexIsChanging && mounted) setState(() => picking.clear());
  });
  String? space;
  bool personalReady=false;
  List<Map<String, dynamic>> places = [];
  Map<String, List<Map<String, dynamic>>> visits = {};
  String? category;
  bool favoritesOnly = false, loading = true;
  final Set<String> picking = {};

  @override
  void initState() {
    super.initState();
    _load(openInitial: true);
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  Future<void> _load({bool openInitial = false}) async {
    if(mounted)setState((){
      loading=true;space=null;personalReady=false;
      places=[];visits={};picking.clear();
    });
    try {
      var s = await CurrentSpaceCache.instance.get();
      var personal=false;
      if(!OneSpaceEnv.isProduction){
        final scopes=await db.rpc('my_storage_scopes');
        if(scopes is! Map ||
          scopes['private_space_id']?.toString()!=db.auth.currentUser?.id) {
          throw StateError('Personal Places scope unavailable');
        }
        s=scopes['shared_space_id']?.toString();
        personal=true;
      }
      if(s==null&&!personal){if(mounted)setState(()=>loading=false);return;}
      final placeQuery=OneSpaceEnv.isProduction
        ? db.from('places').select().eq('space_id',s!)
        : db.from('places').select();
      final visitsQuery=OneSpaceEnv.isProduction
        ? db.from('place_visits')
          .select('id,place_id,visited_on,caption,memory_id').eq('space_id',s!)
        : db.from('place_visits')
          .select('id,place_id,visited_on,caption,memory_id');
      final rows=await placeQuery.isFilter('archived_at',null)
        .order('updated_at',ascending:false);
      final v=await visitsQuery.order('visited_on',ascending:false);
      final byPlace=<String,List<Map<String,dynamic>>>{};
      for(final x in v){
        byPlace.putIfAbsent(x['place_id'].toString(),()=>[])
          .add(Map<String,dynamic>.from(x));
      }
      if(!mounted)return;
      setState((){
        space=s;personalReady=personal;
        places=List<Map<String,dynamic>>.from(rows);
        visits=byPlace;loading=false;
      });
      if(openInitial&&widget.initialId!=null){
        final hit=places.where((p)=>p['id']==widget.initialId).firstOrNull;
        if(hit!=null)_open(hit);
      }
    }catch(_){if(mounted)setState(()=>loading=false);}
  }

  Future<void> _edit([Map<String, dynamic>? existing]) async {
    final s = space;
    if (s == null && !personalReady) return;
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) =>
      PlaceEditor(spaceId: s ?? '', existing: existing, initialStatus: tabs.index == 1 ? 'wishlist' : 'visited')));
    if (ok == true) await _load();
  }

  Future<void> _open(Map<String, dynamic> p) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
      PlaceDetail(placeId: p['id'].toString(), spaceId: space ?? '')));
    await _load();
  }

  Future<void> _planTrip() async {
    final s = space;
    final chosen = places.where((p) =>
      picking.contains(p['id']) &&
      (OneSpaceEnv.isProduction || p['private_space_id']==null)).toList();
    if (s == null || chosen.isEmpty) return;
    await planTripFromPlaces(context, s, chosen);
    if (mounted) setState(() => picking.clear());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final status = tabs.index == 1 ? 'wishlist' : 'visited';
    final shown = places.where((p) => p['status'] == status
      && (category == null || p['category'] == category)
      && (!favoritesOnly || p['favorite'] == true)).toList();
    final usedCategories = {for (final p in places.where((p) => p['status'] == status)) p['category'].toString()};
    return Scaffold(
      appBar: AppBar(title: Text(tt('Our places')), actions: [
        IconButton(tooltip: tt('Our map'), icon: const Icon(Icons.map_outlined),
          onPressed: space == null && !personalReady ? null : () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
              PlacesMapScreen(spaceId: space ?? '', places: places, visits: visits)));
            await _load();
          }),
      ], bottom: TabBar(controller: tabs, tabs: [
        Tab(icon: const Icon(Icons.favorite_outline), text: tt('Been there')),
        Tab(icon: const Icon(Icons.explore_outlined), text: tt('Bucket list')),
      ])),
      floatingActionButton: picking.isNotEmpty
        ? FloatingActionButton.extended(onPressed: _planTrip, icon: const Icon(Icons.luggage_outlined),
            label: Text(tt('Plan a trip ({})').replaceFirst('{}', '${picking.length}')))
        : space == null && !personalReady ? null
        : AddFab(label: tt(status == 'wishlist' ? 'Add a dream place' : 'Add a place'), onPressed: () => _edit()),
      body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            FilterChip(avatar: const Icon(Icons.star_outline, size: 18), label: Text(tt('Favourites')),
              selected: favoritesOnly, onSelected: (v) => setState(() => favoritesOnly = v)),
            const SizedBox(width: 6),
            for (final c in PlaceCategories.labels.keys.where(usedCategories.contains)) Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: ChoiceChip(avatar: Icon(PlaceCategories.icon(c), size: 18), label: Text(tt(PlaceCategories.labels[c]!)),
                selected: category == c, onSelected: (on) => setState(() => category = on ? c : null))),
          ])),
          if (status == 'wishlist' && shown.isNotEmpty) Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(tt(picking.isEmpty ? 'Tip: tick places to plan a trip with them.' : 'Tick more places, then tap Plan a trip.'),
              style: Theme.of(context).textTheme.bodySmall)),
          if (shown.isEmpty) Padding(padding: const EdgeInsets.all(32), child: Column(children: [
            Icon(status == 'wishlist' ? Icons.explore_outlined : Icons.map_outlined, size: 56,
              color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(tt(status == 'wishlist'
              ? 'Where do you dream of going together? Add places, then plan a trip with them.'
              : 'Add the places you have been together — the café of your first date, cities, beaches — with photos and stories.'),
              textAlign: TextAlign.center),
          ])),
          for (final p in shown) _card(p, status),
        ])),
    );
  }

  Widget _card(Map<String, dynamic> p, String status) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    final id = p['id'].toString();
    final v = visits[id] ?? const [];
    final last = v.isEmpty ? null : DateTime.tryParse(v.first['visited_on'].toString());
    final wishBy = DateTime.tryParse((p['wish_by'] ?? '').toString());
    final lines = <String>[
      if (PlaceRules.where(p).isNotEmpty) PlaceRules.where(p),
      if (status == 'visited' && v.isNotEmpty) '${tt(v.length == 1 ? '1 visit' : '{} visits').replaceFirst('{}', '${v.length}')}'
        '${last == null ? '' : ' · ${tt('last')} ${loc.formatMediumDate(last)}'}',
      if (status == 'wishlist' && wishBy != null)
        tt('Hoping to go by {}').replaceFirst('{}', loc.formatMediumDate(wishBy)),
      if (p['planned_trip_id'] != null) tt('In a planned trip'),
      if (!OneSpaceEnv.isProduction && p['private_space_id'] != null) tt('Only me'),
    ];
    return Card(elevation: 0, child: InkWell(borderRadius: BorderRadius.circular(12),
      onTap: () => _open(p),
      onLongPress: status == 'wishlist' &&
        (OneSpaceEnv.isProduction || p['private_space_id']==null)
        ? () => setState(() => picking.contains(id) ? picking.remove(id) : picking.add(id)) : null,
      child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        CircleAvatar(radius: 22, backgroundColor: theme.colorScheme.primary.withValues(alpha: .12),
          child: Icon(PlaceCategories.icon(p['category']), color: theme.colorScheme.primary)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(p['name'].toString(), style: theme.textTheme.titleSmall,
              maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (p['favorite'] == true) const Padding(padding: EdgeInsetsDirectional.only(start: 4),
              child: Icon(Icons.star, size: 16, color: Colors.amber)),
          ]),
          for (final l in lines) Text(l, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (p['rating'] != null) Row(children: [
            for (var i = 0; i < 5; i++) Icon(i < (p['rating'] as num) ? Icons.star_rounded : Icons.star_border_rounded,
              size: 14, color: Colors.amber),
          ]),
        ])),
        if (status == 'wishlist' &&
            (OneSpaceEnv.isProduction || p['private_space_id']==null))
          Checkbox(value: picking.contains(id),
          onChanged: (on) => setState(() => on == true ? picking.add(id) : picking.remove(id))),
      ]))));
  }
}

/// Opens the trip editor with the places' names, then links them to the trip.
Future<void> planTripFromPlaces(BuildContext context, String spaceId, List<Map<String, dynamic>> chosen) async {
  final db = Supabase.instance.client;
  final prefill = PlaceRules.tripPrefill(chosen);
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TripEditor(
    spaceId: spaceId,
    prefill: {'title': tt(prefill['title']!), 'notes': prefill['notes']!},
    onCreated: (tripId) async {
      try {
        await db.from('places').update({'planned_trip_id': tripId})
          .inFilter('id', [for (final p in chosen) p['id'].toString()]);
      } catch (_) {}
    })));
}

class PlaceDetail extends StatefulWidget {
  const PlaceDetail({super.key, required this.placeId, required this.spaceId});
  final String placeId, spaceId;
  @override
  State<PlaceDetail> createState() => _PlaceDetailState();
}

class _PlaceDetailState extends State<PlaceDetail> {
  final db = Supabase.instance.client;
  Map<String, dynamic>? place;
  List<Map<String, dynamic>> visits = [];
  Map<String, dynamic>? trip;
  bool get _isPersonal=>!OneSpaceEnv.isProduction&&
      place?['private_space_id']!=null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await db.from('places').select().eq('id', widget.placeId).maybeSingle();
      if (p == null) { if (mounted) Navigator.of(context).pop(); return; }
      final v = await db.from('place_visits').select().eq('place_id', widget.placeId).order('visited_on', ascending: false);
      Map<String, dynamic>? t;
      if (p['planned_trip_id'] != null) {
        t = await db.from('shared_trips').select('id,title,start_on,status').eq('id', p['planned_trip_id']).maybeSingle();
      }
      if (mounted) setState(() { place = p; visits = List<Map<String, dynamic>>.from(v); trip = t; });
    } catch (_) {}
  }

  Future<void> _addVisit({bool withPhotos = false}) async {
    final p = place;
    if (p == null) return;
    if (withPhotos && _isPersonal) return; // Private photo storage is not ready.
    if (withPhotos) {
      String? visitId;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MemoryEditorScreen(
        spaceId: widget.spaceId,
        prefill: {'title': p['name'].toString(), 'place': [p['name'], PlaceRules.where(p)].where((x) => x.toString().isNotEmpty).join(' — '),
          'memory_date': CalendarRules.sqlDate(DateTime.now())},
        onSaved: (memoryId) async {
          try {
            if (visitId == null) {
              final m = await db.from('memories').select('memory_date,title').eq('id', memoryId).single();
              final row = await db.from('place_visits').insert({
                'place_id': p['id'], 'space_id': widget.spaceId, 'visited_on': m['memory_date'],
                'caption': m['title'], 'memory_id': memoryId}).select('id').single();
              visitId = row['id'].toString();
            }
          } catch (_) {}
        })));
      await _markVisited();
      await _load();
      return;
    }
    final caption = TextEditingController();
    var day = DateTime.now();
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tt('We were here'), style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 12),
          OutlinedButton.icon(icon: const Icon(Icons.event_outlined),
            label: Text(MaterialLocalizations.of(ctx).formatMediumDate(day)),
            onPressed: () async {
              final d = await showDatePicker(context: ctx, initialDate: day, firstDate: DateTime(1950), lastDate: DateTime.now());
              if (d != null) set(() => day = d);
            }),
          const SizedBox(height: 8),
          TextField(controller: caption, maxLength: 2000, minLines: 1, maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: tt('A caption or a little memory'), border: const OutlineInputBorder())),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tt('Save'))),
        ]))));
    if (ok == true) {
      try {
        await db.from('place_visits').insert({
          'place_id':p['id'],
          if(_isPersonal) 'private_space_id':db.auth.currentUser!.id
          else 'space_id':widget.spaceId,
          'visited_on':CalendarRules.sqlDate(day),
          'caption':caption.text.trim(),
        });
        await _markVisited();
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tt('Could not save. Check your connection and try again.'))));
      }
      await _load();
    }
    caption.dispose();
  }

  /// A bucket-list place becomes "been there" with its first visit.
  Future<void> _markVisited() async {
    if (place?['status'] == 'wishlist') {
      try { await db.from('places').update({'status': 'visited'}).eq('id', widget.placeId); } catch (_) {}
    }
  }

  Future<void> _openMaps() async {
    final p = place!;
    final link = (p['map_url'] ?? '').toString().trim();
    if (link.isNotEmpty) {
      await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
      return;
    }
    if (p['latitude'] != null) {
      await launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${p['latitude']},${p['longitude']}'),
        mode: LaunchMode.externalApplication);
      return;
    }
    final q = [p['name'], p['address'], p['city'], p['country']]
      .map((x) => (x ?? '').toString().trim()).where((x) => x.isNotEmpty).join(', ');
    await launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}'),
      mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final p = place;
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    if (p == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final wish = p['status'] == 'wishlist';
    final first = visits.isEmpty ? null : DateTime.tryParse(visits.last['visited_on'].toString());
    return Scaffold(
      appBar: AppBar(title: Text(tt(wish ? 'Bucket list' : _isPersonal?'My place':'Our place')), actions: [
        IconButton(tooltip: tt(p['favorite'] == true ? 'Remove from favourites' : 'Add to favourites'),
          icon: Icon(p['favorite'] == true ? Icons.star : Icons.star_outline, color: p['favorite'] == true ? Colors.amber : null),
          onPressed: () async {
            await db.from('places').update({'favorite': p['favorite'] != true}).eq('id', p['id']);
            await _load();
          }),
        ItemMenu(kind: 'place', recordId: p['id'].toString(), title: p['name'].toString(), table: 'places',
          onChanged: () { if (mounted) Navigator.of(context).pop(); },
          onOpen: () async {
            await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => PlaceEditor(spaceId: widget.spaceId, existing: p)));
            await _load();
          },
          moreActions: [
            if (wish && !_isPersonal) ItemMenuAction('Plan a trip', Icons.luggage_outlined, () async {
              await planTripFromPlaces(context, widget.spaceId, [p]);
              await _load();
            }),
            ItemMenuAction('Open in Maps', Icons.map_outlined, _openMaps),
          ]),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _addVisit(),
        icon: const Icon(Icons.where_to_vote_outlined), label: Text(tt(wish ? 'We went!' : 'We were here again'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
        Row(children: [
          CircleAvatar(radius: 28, backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(PlaceCategories.icon(p['category']), size: 28)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['name'].toString(), style: theme.textTheme.headlineSmall),
            Text([tt(PlaceCategories.labels[p['category']] ?? 'Other'), if (PlaceRules.where(p).isNotEmpty) PlaceRules.where(p)].join(' · '),
              style: theme.textTheme.bodyMedium),
          ])),
        ]),
        const SizedBox(height: 12),
        // R78: where it is.
        if (p['latitude'] != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: PlaceMiniMap(
          latitude: (p['latitude'] as num).toDouble(), longitude: (p['longitude'] as num).toDouble(),
          wishlist: wish, category: (p['category'] ?? 'other').toString(),
          onTap: _openMaps)),
        if (p['rating'] != null) Row(children: [
          for (var i = 0; i < 5; i++) Icon(i < (p['rating'] as num) ? Icons.star_rounded : Icons.star_border_rounded, color: Colors.amber),
        ]),
        if ((p['address'] ?? '').toString().isNotEmpty) ListTile(contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.place_outlined), title: Text(p['address'].toString()),
          trailing: IconButton(icon: const Icon(Icons.map_outlined), tooltip: tt('Open in Maps'), onPressed: _openMaps)),
        if (first != null) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.history),
          title: Text(tt('First time here: {}').replaceFirst('{}', loc.formatMediumDate(first))),
          subtitle: Text(SmartSpan.between(DateTime.now(), first).sentence)),
        if (wish && p['wish_by'] != null) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.flag_outlined),
          title: Text(tt('Hoping to go by {}').replaceFirst('{}', loc.formatMediumDate(DateTime.parse(p['wish_by'].toString())))),
          subtitle: Text(SmartSpan.between(DateTime.now(), DateTime.parse(p['wish_by'].toString())).sentence)),
        if (trip != null) Card(elevation: 0, child: ListTile(leading: const Icon(Icons.luggage_outlined),
          title: Text(trip!['title'].toString()), subtitle: Text(tt('Planned trip')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => TripDetail(tripId: trip!['id'].toString()))))),
        if (wish && trip == null && !_isPersonal) OutlinedButton.icon(icon: const Icon(Icons.luggage_outlined), label: Text(tt('Plan a trip')),
          onPressed: () async { await planTripFromPlaces(context, widget.spaceId, [p]); await _load(); }),
        if ((p['notes'] ?? '').toString().trim().isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(p['notes'].toString(), style: theme.textTheme.bodyLarge)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text(tt(_isPersonal?'My visits':'Our visits'),
            style: theme.textTheme.titleMedium)),
          if(!_isPersonal) TextButton.icon(
            onPressed: () => _addVisit(withPhotos: true),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(tt('Add with photos'))),
        ]),
        if (visits.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(tt(wish ? 'Not yet — one day!' : 'Add the times you came here, with photos and a story.'))),
        for (final v in visits) Card(elevation: 0, child: ListTile(
          leading: Icon(v['memory_id'] == null ? Icons.where_to_vote_outlined : Icons.photo_library_outlined),
          title: Text(loc.formatMediumDate(DateTime.parse(v['visited_on'].toString()))),
          subtitle: (v['caption'] ?? '').toString().isEmpty ? null : Text(v['caption'].toString()),
          trailing: v['memory_id'] == null ? null : const Icon(Icons.chevron_right),
          onTap: v['memory_id'] == null ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => MemoryViewScreen(memoryId: v['memory_id'].toString(), spaceId: widget.spaceId))),
          onLongPress: () async {
            final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
              title: Text(tt('Remove this visit?')),
              content: Text(tt('Photos and stories stay in Memories.')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tt('Cancel'))),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tt('Remove'))),
              ]));
            if (ok == true) {
              try { await db.from('place_visits').delete().eq('id', v['id']); } catch (_) {}
              await _load();
            }
          })),
      ]),
    );
  }
}

class PlaceEditor extends StatefulWidget {
  const PlaceEditor({super.key, required this.spaceId, this.existing, this.initialStatus = 'visited', this.prefill});
  final String spaceId;
  final Map<String, dynamic>? existing;
  /// R78: from a Google/Apple Maps share (name, address, map_url, coordinates).
  final Map<String, dynamic>? prefill;
  final String initialStatus;
  @override
  State<PlaceEditor> createState() => _PlaceEditorState();
}

class _PlaceEditorState extends State<PlaceEditor> with FormChangeTracker<PlaceEditor> {
  final db = Supabase.instance.client;
  late final TextEditingController name, city, country, address, notes, mapUrl;
  double? lat, lng;
  String? foundLabel;
  bool locating = false;
  late String status, category;
  int? rating;
  DateTime? wishBy, firstVisit;
  late bool favorite, shared;
  SpacePeople? people;
  bool saving = false;
  String? error;

  @override
  String get signature => [name.text, city.text, country.text, address.text, notes.text, status, category,
    rating, wishBy, firstVisit, favorite, shared, mapUrl.text, lat, lng].join('|');

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? widget.prefill ?? const <String, dynamic>{};
    name = TextEditingController(text: (e['name'] ?? '').toString());
    mapUrl = TextEditingController(text: (e['map_url'] ?? '').toString());
    lat = (e['latitude'] as num?)?.toDouble();
    lng = (e['longitude'] as num?)?.toDouble();
    city = TextEditingController(text: (e['city'] ?? '').toString());
    country = TextEditingController(text: (e['country'] ?? '').toString());
    address = TextEditingController(text: (e['address'] ?? '').toString());
    notes = TextEditingController(text: (e['notes'] ?? '').toString());
    status = (e['status'] ?? widget.initialStatus).toString();
    category = (e['category'] ?? 'other').toString();
    rating = (e['rating'] as num?)?.toInt();
    wishBy = DateTime.tryParse((e['wish_by'] ?? '').toString());
    favorite = e['favorite'] == true;
    shared = (e['visibility'] ??
      (!OneSpaceEnv.isProduction&&widget.spaceId.isEmpty?'private':'shared')) == 'shared';
    SpacePeople.load().then((p) { if (mounted) setState(() => people = p); });
  }

  @override
  void dispose() {
    name.dispose(); city.dispose(); country.dispose(); address.dispose(); notes.dispose(); mapUrl.dispose();
    super.dispose();
  }

  /// R78: from the map link, else by name with city and country.
  Future<bool> _locate({bool quiet = false}) async {
    setState(() => locating = true);
    final found = await PlaceLocator.locate(link: mapUrl.text, name: name.text, city: city.text, country: country.text);
    if (!mounted) return false;
    setState(() {
      locating = false;
      if (found != null) { lat = found.latitude; lng = found.longitude; foundLabel = found.label; }
      else if (!quiet) { foundLabel = null; }
    });
    if (found == null && !quiet) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        tt('Could not find it. Paste a Google Maps link, or add the city and country.'))));
    }
    return found != null;
  }

  Future<void> _save() async {
    if (saving || name.text.trim().isEmpty) return;
    if (lat == null && (mapUrl.text.trim().isNotEmpty || city.text.trim().isNotEmpty)) await _locate(quiet: true);
    if (!mounted) return;
    setState(() { saving = true; error = null; });
    final values = <String, dynamic>{
      'name': name.text.trim(), 'city': city.text.trim(), 'country': country.text.trim(),
      'address': address.text.trim(), 'notes': notes.text.trim(), 'status': status, 'category': category,
      'rating': status == 'visited' ? rating : null, 'favorite': favorite,
      'wish_by': status == 'wishlist' && wishBy != null ? CalendarRules.sqlDate(wishBy!) : null,
      'visibility': shared ? 'shared' : 'private',
      'map_url': mapUrl.text.trim(), 'latitude': lat, 'longitude': lng,
    };
    try {
      if (widget.existing == null) {
        if(!OneSpaceEnv.isProduction&&shared&&widget.spaceId.isEmpty){
          throw StateError('Join a partner before sharing a place.');
        }
        final newScope=<String,dynamic>{
          if(!OneSpaceEnv.isProduction&&!shared)
            'private_space_id':db.auth.currentUser!.id
          else 'space_id':widget.spaceId,
        };
        final row = await db.from('places').insert({
          ...values,...newScope,
          'created_by':db.auth.currentUser!.id,
        }).select('id').single();
        if(status=='visited'&&firstVisit!=null){
          await db.from('place_visits').insert({
            'place_id':row['id'],...newScope,
            'visited_on':CalendarRules.sqlDate(firstVisit!),'caption':'',
          });
        }
      } else {
        await db.from('places').update(values).eq('id', widget.existing!['id']);
      }
      markClean();
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not save. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final isNew = widget.existing == null;
    return EditorScaffold(
      title: isNew ? (status == 'wishlist' ? 'New dream place' : 'New place') : 'Edit place',
      isNew: isNew, saving: saving || locating, listenTo: [name, city, country, address, notes, mapUrl],
      isChanged: () => changed, isComplete: () => name.text.trim().isNotEmpty, onSave: _save,
      meta: MetaStrip(personal:widget.spaceId.isEmpty,value: MetaValues(shared: shared), people: people,
        showBelongs: false, showDate: false,
        enabled:isNew&&!saving,
        onChanged:(v)=>setState(() => shared=
          !OneSpaceEnv.isProduction&&widget.spaceId.isEmpty?false:v.shared)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'visited', icon: const Icon(Icons.favorite_outline), label: Text(tt('Been there'))),
            ButtonSegment(value: 'wishlist', icon: const Icon(Icons.explore_outlined), label: Text(tt('Bucket list'))),
          ],
          selected: {status}, onSelectionChanged: (s) => setState(() => status = s.first)),
        const SizedBox(height: 16),
        TextField(controller: name, maxLength: 120, textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: tt(requiredLabel('Name')),
            hintText: tt('Our café, Santorini, the old bridge…'), border: const OutlineInputBorder())),
        Row(children: [
          Expanded(child: TextField(controller: city, maxLength: 120, textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tt('City'), border: const OutlineInputBorder()))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: country, maxLength: 80, textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tt('Country'), border: const OutlineInputBorder()))),
        ]),
        TextField(controller: address, maxLength: 300,
          decoration: InputDecoration(labelText: tt('Address'), prefixIcon: const Icon(Icons.place_outlined),
            border: const OutlineInputBorder())),
        TextField(controller: mapUrl, maxLength: 1000, keyboardType: TextInputType.url,
          onChanged: (_) => setState(() { lat = null; lng = null; foundLabel = null; }),
          decoration: InputDecoration(labelText: tt('Google Maps link (optional)'), prefixIcon: const Icon(Icons.link),
            helperText: tt('In Google Maps: Share › OneSpace, or copy the link here'),
            border: const OutlineInputBorder())),
        Card(elevation: 0, child: ListTile(
          leading: Icon(lat == null ? Icons.location_off_outlined : Icons.location_on, color: lat == null ? null : Colors.redAccent),
          title: Text(tt(lat == null ? 'Not on the map yet' : 'On our map')),
          subtitle: lat == null ? Text(tt('We look it up when you save, or tap Find.'))
            : Text(foundLabel?.isNotEmpty == true ? foundLabel! : '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}',
                maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: locating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : lat == null ? TextButton(onPressed: () => _locate(), child: Text(tt('Find')))
            : IconButton(tooltip: tt('Remove from the map'), icon: const Icon(Icons.close),
                onPressed: () => setState(() { lat = null; lng = null; foundLabel = null; })))),
        ChoiceRow<String>(label: 'Kind', selected: category, options: PlaceCategories.labels,
          icons: PlaceCategories.icons, onSelected: (v) => setState(() => category = v ?? category)),
        if (status == 'visited') ...[
          Text(tt('Our rating'), style: Theme.of(context).textTheme.labelLarge),
          StarRating(value: rating, onChanged: (v) => setState(() => rating = v), maxSize: 32),
          if (isNew) Padding(padding: const EdgeInsets.only(top: 8), child: OutlinedButton.icon(
            icon: const Icon(Icons.event_outlined),
            label: Text(firstVisit == null ? tt('When were you there? (optional)') : loc.formatMediumDate(firstVisit!)),
            onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: firstVisit ?? DateTime.now(),
                firstDate: DateTime(1950), lastDate: DateTime.now());
              if (d != null) setState(() => firstVisit = d);
            })),
        ] else OutlinedButton.icon(icon: const Icon(Icons.flag_outlined),
          label: Text(wishBy == null ? tt('Hope to go by… (optional)') : loc.formatMediumDate(wishBy!)),
          onPressed: () async {
            final now = DateTime.now();
            final d = await showDatePicker(context: context, initialDate: wishBy ?? DateTime(now.year + 1, now.month, now.day),
              firstDate: now, lastDate: DateTime(now.year + 30));
            if (d != null) setState(() => wishBy = d);
          }),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: favorite, onChanged: (v) => setState(() => favorite = v),
          title: Text(tt('One of our favourites'))),
        TextField(controller: notes, minLines: 2, maxLines: 6, maxLength: 4000,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tt(status == 'wishlist' ? 'Why we want to go' : 'What makes it special'),
            border: const OutlineInputBorder())),
        if (error != null) Text(tt(error!), style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 24),
      ]),
    );
  }
}
