import '../../core/preferred_currency.dart';
import '../../core/editor_scaffold.dart';
import '../../core/form_kit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/current_space_cache.dart';
import '../../core/app_env.dart';
import '../calendar/calendar_event_editor.dart';
import '../connect/shared_experiences_screen.dart';
import '../coordinate/activity_detail_screen.dart';
import '../notes/notes_screen.dart';
import '../occasions/occasions_screen.dart';
import '../plans/plans_screen.dart';
import '../reminders/reminders_screen.dart';
import '../world/trips_screen.dart';
import '../world/trip_flight_options_section.dart';
import 'items_to_sort_screen.dart';
import 'share_intake_rules.dart';
import 'share_suggestions.dart';
import '../places/place_location.dart';
import '../places/places_screen.dart';
import 'package:onespace/l10n/phrases.dart';

/// R52 (spec 4.1, backlog B-16): everything shared into OneSpace lands here.
/// The first choice is always "Save to Items to sort" (one tap, sort later).
/// Below it, up to three destinations suggested from WHAT was shared, then
/// "More…" with every destination. Nothing reaches the partner until a
/// destination is saved as Shared.
///
/// When [trayItem] is given, this screen sorts that tray item: on success the
/// tray item is marked sorted and leaves the list.
class ShareIntakeScreen extends StatefulWidget {
  const ShareIntakeScreen({super.key, this.shared, this.trayItem});
  final IncomingShare? shared;
  final Map<String, dynamic>? trayItem;
  @override State<ShareIntakeScreen> createState() => _ShareIntakeScreenState();
}

class _ShareIntakeScreenState extends State<ShareIntakeScreen> {
  final db = Supabase.instance.client;
  late final TextEditingController title, url, notes, price, currency, specs;
  String? spaceId, error, selectedActivity, selectedOccasion, selectedTrip;
  bool loading = true, saving = false, onlyMe = false, showMore = false;
  ShareDestination? destination;
  String category = 'other';
  List<Map<String, dynamic>> activities = [], occasions = [], trips = [];

  bool get sorting => widget.trayItem != null;

  IncomingShare get current => IncomingShare(
      title: title.text.trim(), link: url.text.trim(), note: notes.text.trim());

  @override void initState() {
    super.initState();
    final tray = widget.trayItem;
    final content = widget.shared;
    title = TextEditingController(text: tray?['title']?.toString() ?? content?.title ?? '');
    url = TextEditingController(text: tray?['link']?.toString() ?? content?.link ?? '');
    notes = TextEditingController(text: tray?['note']?.toString() ?? content?.note ?? '');
    price = TextEditingController();
    currency = TextEditingController(text: PreferredCurrency.code);
    specs = TextEditingController();
    // Shared-in content is private by default until a destination is chosen.
    onlyMe = tray == null ? false : tray['visibility'] != 'shared';
    load();
  }

  @override void dispose() {
    for (final c in [title, url, notes, price, currency, specs]) { c.dispose(); }
    super.dispose();
  }

  Future<void> load() async {
    try {
      var id=await CurrentSpaceCache.instance.get();
      if(!OneSpaceEnv.usesLegacyBackend){
        final scopes=await db.rpc('my_storage_scopes');
        if(scopes is! Map ||
            scopes['private_space_id']?.toString()!=db.auth.currentUser?.id){
          throw StateError('Personal Share-in scope unavailable');
        }
        id=scopes['shared_space_id']?.toString();
      }
      if(id==null){
        if(mounted)setState((){
          spaceId=null;loading=false;
          if(!OneSpaceEnv.usesLegacyBackend)onlyMe=true;
          else error='Connect a shared space first.';
        });
        return;
      }
      if(mounted)setState(()=>spaceId=id);
      final activityQuery=OneSpaceEnv.usesLegacyBackend
        ? db.from('activities').select('id,title,visibility,archived_at').eq('space_id',id)
        : db.from('activities').select('id,title,visibility,archived_at');
      final rows=await activityQuery.isFilter('archived_at', null)
          .order('updated_at', ascending: false).limit(100);
      final planQuery=OneSpaceEnv.usesLegacyBackend
          ?db.from('occasion_plans').select('id,title,occasion_on,status').eq('space_id',id)
          :db.from('occasion_plans').select('id,title,occasion_on,status,space_id,private_space_id');
      final plans=await planQuery.isFilter('archived_at',null)
          .not('status','in','(celebrated,cancelled)')
          .order('occasion_on',ascending:true).limit(60);
      final tripQuery=OneSpaceEnv.usesLegacyBackend
          ?db.from('shared_trips').select().eq('space_id',id)
          :db.from('shared_trips').select();
      final tripRows=await tripQuery.isFilter('archived_at',null)
          .not('status','in','(completed,cancelled)')
          .order('updated_at',ascending:false).limit(60);
      if (!mounted) return;
      setState(() {
        trips = List<Map<String, dynamic>>.from(tripRows);
        selectedTrip = trips.isEmpty ? null : trips.first['id'].toString();
        activities = List<Map<String, dynamic>>.from(rows);
        occasions = List<Map<String, dynamic>>.from(plans);
        selectedActivity = activities.isEmpty ? null : activities.first['id'].toString();
        selectedOccasion = occasions.isEmpty ? null : occasions.first['id'].toString();
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { loading = false; });
    }
  }

  String? _validate({bool requireBody = false}) {
    final name = title.text.trim(), link = url.text.trim();
    if (name.isEmpty) return 'Add a title.';
    if (link.isNotEmpty && !ShareIntakeRules.isWebLink(link)) {
      return 'Only http or https links can be saved.';
    }
    if (requireBody && link.isEmpty && notes.text.trim().isEmpty) return 'Add a link or note first.';
    return null;
  }

  String get _bodyWithLink {
    final body = notes.text.trim(), link = url.text.trim();
    return body + (link.isEmpty ? '' : (body.isEmpty ? '' : '\n\n') + link);
  }

  /// One tap: keep it in the tray, private to me.
  Future<void> saveToTray() async {
    final problem = _validate();
    if (problem != null) { setState(() => error = problem); return; }
    if ((spaceId == null && OneSpaceEnv.usesLegacyBackend) || saving) return;
    setState(() { saving = true; error = null; });
    try {
      await db.from('items_to_sort').insert({
        if(!OneSpaceEnv.usesLegacyBackend)
          'private_space_id':db.auth.currentUser!.id
        else 'space_id':spaceId,
        'created_by':db.auth.currentUser!.id,
        'title': title.text.trim().length > 180 ? title.text.trim().substring(0, 180) : title.text.trim(),
        'link': url.text.trim().isEmpty ? null : url.text.trim(),
        'note': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'visibility': 'private',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tt('Saved to Items to sort. Sort it whenever you like.'))));
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => const ItemsToSortScreen()));
    } catch (_) {
      if (mounted) setState(() { saving = false; error = 'Could not save. Please try again.'; });
    }
  }

  Future<void> _markSorted(String to) async {
    final tray = widget.trayItem;
    if (tray == null) return;
    try {
      await db.from('items_to_sort').update({
        'sorted_at': DateTime.now().toUtc().toIso8601String(), 'sorted_to': to,
      }).eq('id', tray['id'].toString());
    } catch (_) {/* The item stays in the tray; nothing is lost. */}
  }

  Future<void> saveToDestination() async {
    final d = destination;
    if (d == null || saving ||
        (spaceId == null && (OneSpaceEnv.usesLegacyBackend ||
          (d != ShareDestination.note && d != ShareDestination.todo &&
           d != ShareDestination.newActivity && d != ShareDestination.trip &&
           d != ShareDestination.experience &&
           d != ShareDestination.placeVisited &&
           d != ShareDestination.placeWishlist) ||
          !onlyMe))) return;
    final problem = _validate(requireBody: d == ShareDestination.activityOption);
    if (problem != null) { setState(() => error = problem); return; }
    setState(() { saving = true; error = null; });
    final name = title.text.trim(), link = url.text.trim(), body = notes.text.trim();
    final visibility = onlyMe ? 'private' : 'shared';
    try {
      Widget? next;
      bool done = true;
      switch (d) {
        case ShareDestination.newActivity:
          final personal=!OneSpaceEnv.usesLegacyBackend&&onlyMe;
          final created=await db.from('activities').insert({
            if(personal) 'private_space_id':db.auth.currentUser!.id
            else 'space_id':spaceId,
            'created_by':db.auth.currentUser!.id,
            'title':name,'body':_bodyWithLink,'visibility':visibility,
          }).select('id').single();
          final id = created['id'].toString();
          if (link.isNotEmpty && !personal) {
            try {
              await db.from('activity_components').insert({
                'activity_id': id, 'kind': 'link', 'label': name,
                'payload': {'value': link, 'note': body},
              });
            } catch (_) {/* The link is kept in the description. */}
          }
          next = ActivityScreen(id: id);
        case ShareDestination.activityOption:
          if (selectedActivity == null) {
            setState(() { saving = false; error = 'Choose an Activity first.'; });
            return;
          }
          final amount = price.text.trim().isEmpty ? null : double.tryParse(price.text.trim());
          if (price.text.trim().isNotEmpty && (amount == null || amount < 0)) {
            setState(() { saving = false; error = 'Enter a valid price or leave it blank.'; });
            return;
          }
          await db.from('activity_components').insert({
            'activity_id': selectedActivity,
            'kind': link.isEmpty ? 'note' : 'option',
            'label': name,
            'payload': link.isEmpty ? {'value': body} : {
              'value': link, 'url': link, 'note': body, 'price': price.text.trim(),
              'currency': currency.text.trim().toUpperCase(),
              'specs': specs.text.trim(), 'state': 'considering',
            },
          });
          next = ActivityScreen(id: selectedActivity!);
        case ShareDestination.experience:
          final personal=!OneSpaceEnv.usesLegacyBackend&&onlyMe;
          final created=await db.from('shared_experiences').insert({
            if(personal) 'private_space_id':db.auth.currentUser!.id
            else 'space_id':spaceId,
            'created_by':db.auth.currentUser!.id,
            if(!OneSpaceEnv.usesLegacyBackend)
              'visibility':personal?'private':'shared',
            'category':category,'title':name,
            'description':body,'source_url':link,
          }).select('id').single();
          next = SharedExperiencesScreen(initialExperienceId: created['id'].toString());
        case ShareDestination.giftIdea:
          if (selectedOccasion == null) {
            setState(() { saving = false; error = 'Plan an occasion first, then add gift ideas to it.'; });
            return;
          }
          await db.from('occasion_budget_items').insert({
            'plan_id': selectedOccasion, 'title': name.length > 200 ? name.substring(0, 200) : name,
            'source_url': link.isEmpty ? null : link,
            'notes': body.isEmpty ? null : (body.length > 2500 ? body.substring(0, 2500) : body),
            'status': 'wish',
          });
          next = OccasionsScreen(initialPlanId: selectedOccasion);
        case ShareDestination.todo:
          final personal = !OneSpaceEnv.usesLegacyBackend && visibility=='private';
          String? pair = spaceId;
          if (!OneSpaceEnv.usesLegacyBackend && !personal) {
            final scopes=await db.rpc('my_storage_scopes');
            pair=scopes is Map ? scopes['shared_space_id']?.toString() : null;
          }
          if (!personal && (pair==null || pair.isEmpty)) {
            if(mounted) setState((){
              saving=false;
              error='Connect with a partner to share a checklist.';
            });
            return;
          }
          await db.from('tasks').insert({
            if(personal) 'private_space_id':db.auth.currentUser!.id
            else 'space_id':pair,
            'created_by':db.auth.currentUser!.id,
            'title':name,'status':'open','visibility':visibility,
          });
          next = const PlansScreen();
        case ShareDestination.note:
          final personal = !OneSpaceEnv.usesLegacyBackend && visibility == 'private';
          String? pairedSpace = spaceId;
          if (!OneSpaceEnv.usesLegacyBackend && !personal) {
            final scopes = await db.rpc('my_storage_scopes');
            pairedSpace = scopes is Map ? scopes['shared_space_id']?.toString() : null;
          }
          if (!personal && (pairedSpace == null || pairedSpace.isEmpty)) {
            if (mounted) setState(() {
              saving = false;
              error = tt('Connect with a partner before saving shared notes.');
            });
            return;
          }
          final created = await db.from('notes').insert({
            if (personal) 'private_space_id': db.auth.currentUser!.id
            else 'space_id': pairedSpace,
            'created_by': db.auth.currentUser!.id,
            'title': name, 'body': _bodyWithLink, 'visibility': visibility,
          }).select('id').single();
          next = NotesScreen(initialNoteId: created['id'].toString());
        case ShareDestination.reminder:
          done = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
            builder: (_) => ReminderEditorScreen(spaceId: spaceId!,
              initialTitle: name, initialDetails: _bodyWithLink))) == true;
        case ShareDestination.event:
          done = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
            builder: (_) => CalendarEventEditor(spaceId: spaceId!,
              initialDate: DateTime.now(), initialTitle: name,
              initialDetails: _bodyWithLink))) == true;
        case ShareDestination.flightOption:
          final trip = trips.where((t) => t['id'].toString() == selectedTrip).firstOrNull;
          if (trip == null) {
            setState(() { saving = false; error = 'Choose a trip first, or save it as a new Trip.'; });
            return;
          }
          final draft = await readFlight('$name\n$body\n$link');
          if (!mounted) return;
          done = await editFlightOption(context, tripId: trip['id'].toString(), trip: trip, draft: draft);
          next = TripDetail(tripId: trip['id'].toString());
        case ShareDestination.placeVisited:
        case ShareDestination.placeWishlist:
          // R78: name and address from the shared text; the pin from the link.
          final parts = MapsLinkRules.splitShare(name, body, link);
          final loc = await PlaceLocator.fromLink(link);
          if (!mounted) return;
          final placeName = (parts.name.isNotEmpty ? parts.name : (MapsLinkRules.nameIn(link) ?? name)).trim();
          done = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
            builder: (_) => PlaceEditor(spaceId: spaceId ?? '',
              initialStatus: d == ShareDestination.placeWishlist ? 'wishlist' : 'visited',
              prefill: {
                'name': placeName.length > 120 ? placeName.substring(0, 120) : placeName,
                'address': parts.address.length > 300 ? parts.address.substring(0, 300) : parts.address,
                'map_url': link.length > 1000 ? '' : link,
                'status': d == ShareDestination.placeWishlist ? 'wishlist' : 'visited',
                if (loc != null) 'latitude': loc.latitude,
                if (loc != null) 'longitude': loc.longitude,
              }))) == true;
          next = const PlacesScreen();
        case ShareDestination.trip:
          // R67: a shared flight starts the trip with its airports and dates.
          final draft = await readFlight('$name\n$body\n$link');
          if (!mounted) return;
          String day(DateTime d) => d.toIso8601String().substring(0, 10);
          done = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
            builder: (_) => TripEditor(spaceId: spaceId ?? '',
              prefill: {'title': name, 'notes': _bodyWithLink,
                if (draft.origin != null) 'origin': draft.origin!,
                if (draft.destination != null) 'destination': draft.destination!,
                if (draft.departure != null) 'start_on': day(draft.departure!),
                if (draft.returnOn != null) 'end_on': day(draft.returnOn!)}))) == true;
      }
      if (!mounted) return;
      if (!done) { setState(() => saving = false); return; }
      await _markSorted(d.name);
      if (!mounted) return;
      if (next != null) {
        await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => next!));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tt('Saved as')} ${d.label}.')));
        Navigator.of(context).pop();
      }
    } on PostgrestException catch (e) {
      if (mounted) setState(() { saving = false; error = e.message; });
    } catch (_) {
      if (mounted) setState(() { saving = false; error = 'Could not save. Nothing was shared; please try again.'; });
    }
  }

  Widget _destinationChip(ShareDestination d) => ChoiceChip(
    avatar: Icon(d.icon, size: 18), showCheckmark: false,
    label: Text(tt(d.label)),
    selected: destination == d,
    onSelected: (_) {
      final solo = !OneSpaceEnv.usesLegacyBackend && spaceId == null;
      final supported = d == ShareDestination.newActivity ||
        d == ShareDestination.todo || d == ShareDestination.note ||
        d == ShareDestination.trip || d == ShareDestination.experience ||
        d == ShareDestination.placeVisited || d == ShareDestination.placeWishlist;
      if (solo && !supported) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tt('Connect with a partner to use this destination. '
            'Your personal inbox, Notes, Activities, To-do and Places are available.'))));
        return;
      }
      setState(() { destination = d; error = null; });
    });

  Widget _destinationDetails(BuildContext context) {
    final d = destination;
    if (d == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 10),
      if (d == ShareDestination.activityOption) ...[
        if (loading) const LinearProgressIndicator(),
        if (activities.isEmpty && !loading)
          Text(tt('There are no Activities yet. Choose "New Activity" instead.'))
        else if (activities.isNotEmpty) ChoicePickerField<String>(label: tt('Activity'), required: true, icon: Icons.hub_outlined,
          options: {for (final a in activities) a['id'].toString():
            '${a['title']}${a['visibility'] == 'private' ? tt(' · Only me') : ''}'},
          selected: selectedActivity,
          onSelected: (v) => setState(() => selectedActivity = v)),
        if (url.text.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(flex: 2, child: TextField(controller: price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tt('Price (optional)'), border: OutlineInputBorder()))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: currency, maxLength: 3,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: tt('Currency'), border: OutlineInputBorder(),
                counterText: ''))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: specs, maxLength: 2500, minLines: 2, maxLines: 4,
            decoration: InputDecoration(labelText: tt('Specifications or pros/cons'),
              border: OutlineInputBorder())),
        ],
        Text(tt('Follows the Activity\'s own privacy.'), style: theme.textTheme.bodySmall),
      ],
      if (d == ShareDestination.giftIdea) ...[
        if (occasions.isEmpty && !loading)
          Text(tt('There is no upcoming occasion yet. Plan one in Occasions first.'))
        else if (occasions.isNotEmpty) ChoicePickerField<String>(label: tt('Occasion'), required: true, icon: Icons.card_giftcard_outlined,
          options: {for (final o in occasions) o['id'].toString():
            '${o['title']}${o['occasion_on'] == null ? '' : ' · ${o['occasion_on']}'}'},
          selected: selectedOccasion,
          onSelected: (v) => setState(() => selectedOccasion = v)),
        Text(tt('Saved as a gift idea in that occasion\'s plan.'), style: theme.textTheme.bodySmall),
      ],
      if (d == ShareDestination.flightOption) ...[
        if (trips.isEmpty && !loading)
          Text(tt('There is no upcoming trip yet. Choose "Trip" to start one with this flight.'))
        else if (trips.isNotEmpty) ChoicePickerField<String>(label: tt('Trip'), required: true,
          icon: Icons.flight_takeoff_outlined,
          options: {for (final t in trips) t['id'].toString():
            '${t['title']}${t['start_on'] == null ? '' : ' · ${t['start_on']}'}'},
          selected: selectedTrip,
          onSelected: (v) => setState(() => selectedTrip = v)),
        Text(tt('OneSpace reads the airports, dates, airline and price it can find; check them before saving.'),
          style: theme.textTheme.bodySmall),
      ],
      if (d == ShareDestination.experience) ...[
        ChoiceRow<String>(label: tt('Watchlist'), options: experienceTypes, selected: category,
          onSelected: (v) => setState(() => category = v ?? category)),
        Text(tt('Shared experiences are visible to both of you.'), style: theme.textTheme.bodySmall),
      ],
      if (d == ShareDestination.reminder || d == ShareDestination.event || d == ShareDestination.trip)
        Text('${tt('Opens the')} ${d.label.toLowerCase()} ${tt('page with this filled in; choose the date and save there.')}',
          style: theme.textTheme.bodySmall),
    ]);
  }

  /// Destinations that carry their own privacy (or open a page that asks).
  bool get _ownPrivacy {
    final d = destination;
    return d == ShareDestination.activityOption || d == ShareDestination.giftIdea
        || d == ShareDestination.flightOption
        || (OneSpaceEnv.usesLegacyBackend&&d==ShareDestination.experience)
        || d == ShareDestination.reminder
        || d == ShareDestination.event || d == ShareDestination.trip;
  }

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final share = current;
    final suggested = ShareSuggestions.forShare(share);
    final others = ShareSuggestions.more(share);
    final d = destination;
    final showStrip = d == null ? false : !_ownPrivacy;
    return EditorScaffold(
      title: sorting ? tt('Sort item') : tt('Save to OneSpace'),
      isNew: true,
      isChanged: () => title.text.isNotEmpty || url.text.isNotEmpty || notes.text.isNotEmpty,
      isComplete: () => (spaceId != null ||
        (!OneSpaceEnv.usesLegacyBackend && onlyMe &&
         (d == null || d == ShareDestination.todo || d == ShareDestination.note ||
          d == ShareDestination.newActivity || d == ShareDestination.trip ||
          d == ShareDestination.experience ||
          d == ShareDestination.placeVisited ||
          d == ShareDestination.placeWishlist))) &&
        title.text.trim().isNotEmpty && (d != null || !sorting),
      missingHint: sorting && d == null ? tt('Choose where it should go') : tt('Give it a title'),
      listenTo: [title, url, notes],
      saving: saving,
      saveLabel: d == null ? tt('Save to Items to sort') : 'Save as ${d.label}',
      onSave: d == null ? saveToTray : saveToDestination,
      meta: showStrip ? MetaStrip(value: MetaValues(shared: !onlyMe), showBelongs: false, showDate: false,
        enabled: !saving, onChanged: (v) => setState(() => onlyMe = !v.shared)) : null,
      body: ListView(padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24), children: [
        FormSection(tt('1 · What it is')),
        TextField(controller: title, maxLength: 120,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: tt('Title *'), border: OutlineInputBorder())),
        const SizedBox(height: 6),
        TextField(controller: url, maxLength: 1800, keyboardType: TextInputType.url,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: tt('Link'), prefixIcon: Icon(Icons.link),
            border: OutlineInputBorder())),
        const SizedBox(height: 6),
        TextField(controller: notes, maxLength: 5000, minLines: 2, maxLines: 5,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: tt('Comment'), border: OutlineInputBorder())),
        FormSection(sorting ? '2 · Where it goes' : '2 · Where it goes (or sort it later)'),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final x in suggested) _destinationChip(x),
          ActionChip(
            avatar: Icon(showMore ? Icons.expand_less : Icons.expand_more, size: 18),
            label: Text(tt(showMore ? tt('Fewer') : tt('More…'))),
            onPressed: () => setState(() => showMore = !showMore)),
        ]),
        if (showMore) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [for (final x in others) _destinationChip(x)]),
        ],
        if (!sorting && d == null) Padding(padding: const EdgeInsets.only(top: 8),
          child: Text(tt('No choice yet? Save it to Items to sort (only you) and decide later.'),
            style: theme.textTheme.bodySmall)),
        if (d != null && !sorting) Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(
          onPressed: () => setState(() => destination = null),
          icon: const Icon(Icons.inbox_outlined), label: Text(tt('Sort it later instead')))),
        _destinationDetails(context),
        if (error != null) Padding(padding: const EdgeInsets.all(6),
          child: Text(tt(error!), style: TextStyle(color: theme.colorScheme.error))),
      ]),
    );
  }
}
