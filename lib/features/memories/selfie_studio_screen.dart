import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/editor_scaffold.dart';
import '../../core/account_content_scope.dart';
import '../../core/app_env.dart';
import '../../core/form_kit.dart';
import '../calendar/calendar_rules.dart';
import 'memory_photo_service.dart';
import 'package:onespace/l10n/phrases.dart';

/// R55: a purpose-built studio for the Daily selfie.
///
/// Front camera first, a polaroid preview, a one-line caption, who can see
/// it, and a 7-day strip showing which days each of you posted. Nothing is
/// saved until Save, so cancelling never leaves an empty memory behind.
class SelfieStudioScreen extends StatefulWidget {
  const SelfieStudioScreen({super.key, required this.spaceId, this.partnerName, this.addToMemoryId});
  final String spaceId;
  final String? partnerName;
  /// R70: add my photo to this day's selfie (made together, two ways).
  final String? addToMemoryId;
  @override
  State<SelfieStudioScreen> createState() => _SelfieStudioScreenState();
}

class _SelfieStudioScreenState extends State<SelfieStudioScreen> {
  final _db = Supabase.instance.client;
  final _caption = TextEditingController();
  XFile? _photo;
  Uint8List? _bytes;
  bool _private = false, _saving = false;
  String? _error;
  List<Map<String, dynamic>> _week = const [];
  /// Weeks back from this week shown in the strip (0 = this week).
  int _weeksBack = 0;
  DateTime get _accountStart {
    final raw = _db.auth.currentUser?.createdAt;
    final d = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    final day = d ?? DateTime.now();
    return DateTime(day.year, day.month, day.day);
  }
  /// R70: today's shared selfie from my partner that still waits for mine.
  String? _joinId;

  @override
  void initState() {
    super.initState();
    _joinId = widget.addToMemoryId;
    if(!OneSpaceEnv.isProduction && widget.spaceId.isEmpty)_private=true;
    _loadWeek();
    if (_joinId == null) _findTodayToJoin();
    WidgetsBinding.instance.addPostFrameCallback((_) => _take(ImageSource.camera));
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _loadWeek() async {
    try {
      // Every selfie since the account was created, so the strip can go back.
      final from = CalendarRules.sqlDate(_accountStart);
      var query=_db.from('memories').select('created_by,memory_date');
      if(OneSpaceEnv.isProduction)query=query.eq('space_id',widget.spaceId);
      final rows=await query.eq('memory_type', 'daily_selfie')
          .isFilter('archived_at', null).gte('memory_date', from);
      if (mounted) setState(() => _week = List<Map<String, dynamic>>.from(rows));
    } catch (_) {/* the strip is a nicety; the studio still works */}
  }

  Future<void> _findTodayToJoin() async {
    if(widget.spaceId.isEmpty)return; // No current couple to join.
    final me = _db.auth.currentUser?.id;
    if (me == null) return;
    try {
      final rows = await _db.from('memories').select('id,created_by,memory_photos(created_by,archived_at)')
          .eq('space_id', widget.spaceId).eq('memory_type', 'daily_selfie')
          .eq('visibility', 'shared').isFilter('archived_at', null)
          .eq('memory_date', CalendarRules.sqlDate(DateTime.now())).limit(5);
      for (final r in rows) {
        final pics = (r['memory_photos'] as List? ?? const [])
            .where((p) => p is Map && p['archived_at'] == null).toList();
        if (r['created_by'] != me && !pics.any((p) => (p as Map)['created_by'] == me)) {
          if (mounted) setState(() => _joinId = r['id'].toString());
          return;
        }
      }
    } catch (_) {/* a new selfie is made instead */}
  }

  Future<void> _take(ImageSource source) async {
    try {
      final photo = await ImagePicker().pickImage(
          source: source,
          preferredCameraDevice: CameraDevice.front,
          imageQuality: 82, maxWidth: 1600, maxHeight: 1600);
      if (photo == null || !mounted) return;
      final bytes = await photo.readAsBytes();
      if (mounted) setState(() {_photo = photo; _bytes = bytes; _error = null;});
    } catch (_) {
      if (mounted) setState(() => _error = 'The camera could not open. Try the gallery instead.');
    }
  }

  Future<void> _save() async {
    final user = _db.auth.currentUser?.id;
    final photo = _photo;
    if (user == null || photo == null) return;
    setState(() {_saving = true; _error = null;});
    String? created;
    try {
      final today = CalendarRules.sqlDate(DateTime.now());
      final caption = _caption.text.trim();
      final join = _joinId;
      if (join != null) {
        // Two ways: my photo joins the same day's selfie.
        final photoId = await MemoryPhotoService(_db).addFileReturningId(join, photo);
        if (caption.isNotEmpty) {
          await _db.from('memory_photos').update({'caption': caption}).eq('id', photoId);
        }
        if (mounted) Navigator.pop(context, true);
        return;
      }
      final scopes=await AccountContentScope.load(_db,
          legacySpaceId:widget.spaceId.isEmpty?null:widget.spaceId);
      final row = await _db.from('memories').insert({
        ...scopes.fieldsForNew(shared: !_private),
        'created_by': user,
        'title': caption.isEmpty ? 'Daily selfie · $today' : caption,
        'body': '', 'memory_date': today,
        'memory_type': 'daily_selfie', 'photo_layout': 'polaroid',
      }).select('id').single();
      created = row['id'].toString();
      final photoId = await MemoryPhotoService(_db).addFileReturningId(created, photo);
      if (caption.isNotEmpty) {
        await _db.from('memory_photos').update({'caption': caption}).eq('id', photoId);
      }
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = 'Selfie could not be saved: ${e.message}');
    } catch (_) {
      if (mounted) {
        setState(() => _error = created == null
            ? 'Selfie could not be saved. Please try again.'
            : 'The memory was created but the photo did not upload. Open it from Memories to retry.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _weekStrip(BuildContext context) {
    final me = _db.auth.currentUser?.id;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day).subtract(Duration(days: 7 * _weeksBack));
    final days = List.generate(7, (i) => end.subtract(Duration(days: 6 - i)));
    final canGoBack = days.first.isAfter(_accountStart);
    final loc = MaterialLocalizations.of(context);
    bool posted(DateTime d, bool mine) => _week.any((r) =>
        r['memory_date']?.toString() == CalendarRules.sqlDate(d) &&
        (r['created_by'] == me) == mine);
    Widget dot(bool on, Color c) => Container(
        width: 9, height: 9, margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(shape: BoxShape.circle,
            color: on ? c : scheme.outlineVariant));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(_weeksBack == 0 ? tt('This week')
            : '${loc.formatShortMonthDay(days.first)} – ${loc.formatShortMonthDay(days.last)}',
          style: Theme.of(context).textTheme.labelLarge)),
        IconButton(tooltip: tt('Previous week'), visualDensity: VisualDensity.compact,
          onPressed: canGoBack ? () => setState(() => _weeksBack++) : null,
          icon: const Icon(Icons.chevron_left)),
        IconButton(tooltip: tt('Next week'), visualDensity: VisualDensity.compact,
          onPressed: _weeksBack > 0 ? () => setState(() => _weeksBack--) : null,
          icon: const Icon(Icons.chevron_right)),
      ]),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (final d in days)
          Column(children: [
            Text(tt(MaterialLocalizations.of(context).narrowWeekdays[d.weekday % 7]),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Row(children: [dot(posted(d, true), scheme.primary), dot(posted(d, false), scheme.tertiary)]),
            Text('${d.day}', style: Theme.of(context).textTheme.labelSmall),
          ]),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        dot(true, scheme.primary), const SizedBox(width: 4),
        Text(tt('You'), style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(width: 14),
        dot(true, scheme.tertiary), const SizedBox(width: 4),
        Text(tt(widget.partnerName ?? 'Your partner'), style: Theme.of(context).textTheme.labelSmall),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return EditorScaffold(
      title: tt('Daily selfie'),
      isNew: true,
      isChanged: () => _photo != null,
      isComplete: () => _photo != null,
      missingHint: 'Take or choose a photo first',
      saving: _saving,
      saveLabel: tt('Save selfie'),
      listenTo: [_caption],
      onSave: _save,
      meta: _joinId != null ? null : MetaStrip(personal:widget.spaceId.isEmpty,value: MetaValues(shared: !_private), showBelongs: false, showDate: false,
        enabled: !_saving && (widget.spaceId.isNotEmpty || OneSpaceEnv.isProduction),
        onChanged: (v) => setState(() => _private = !v.shared)),
      body: ListView(padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 24), children: [
        if (_joinId != null) Card(elevation: 0, color: scheme.secondaryContainer,
          child: ListTile(leading: const Icon(Icons.favorite_outline),
            title: Text(tt('Add yours to today’s selfie')),
            subtitle: Text(tt('Your photo sits next to ${widget.partnerName ?? 'your partner'}’s in the same memory.')))),
        Center(child: GestureDetector(
          onTap: () => _take(ImageSource.camera),
          child: Container(
            width: 280,
            padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 38),
            decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .16),
                    blurRadius: 14, offset: const Offset(0, 6))]),
            child: AspectRatio(aspectRatio: 1, child: _bytes == null
                ? Container(color: scheme.surfaceContainerHighest,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.photo_camera_front_outlined, size: 54, color: scheme.primary),
                      const SizedBox(height: 8),
                      Text(tt('Tap to take today’s selfie')),
                    ]))
                : Image.memory(_bytes!, fit: BoxFit.cover)),
          ),
        )),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          FilledButton.tonalIcon(onPressed: _saving ? null : () => _take(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_front_outlined),
              label: Text(tt(_photo == null ? tt('Camera') : tt('Retake')))),
          const SizedBox(width: 10),
          OutlinedButton.icon(onPressed: _saving ? null : () => _take(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined), label: Text(tt('Gallery'))),
        ]),
        const SizedBox(height: 18),
        TextField(controller: _caption, maxLength: 80, textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: tt('Caption (optional)'),
                hintText: tt('Today in a few words'), border: OutlineInputBorder())),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(tt(_error!), style: TextStyle(color: scheme.error))),
        const SizedBox(height: 22),
        _weekStrip(context),
      ]),
    );
  }
}
