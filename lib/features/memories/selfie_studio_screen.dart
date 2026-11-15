import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/editor_scaffold.dart';
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
  const SelfieStudioScreen({super.key, required this.spaceId, this.partnerName});
  final String spaceId;
  final String? partnerName;
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

  @override
  void initState() {
    super.initState();
    _loadWeek();
    WidgetsBinding.instance.addPostFrameCallback((_) => _take(ImageSource.camera));
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _loadWeek() async {
    try {
      final from = CalendarRules.sqlDate(DateTime.now().subtract(const Duration(days: 6)));
      final rows = await _db.from('memories')
          .select('created_by,memory_date')
          .eq('space_id', widget.spaceId)
          .eq('memory_type', 'daily_selfie')
          .isFilter('archived_at', null)
          .gte('memory_date', from);
      if (mounted) setState(() => _week = List<Map<String, dynamic>>.from(rows));
    } catch (_) {/* the strip is a nicety; the studio still works */}
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
      final row = await _db.from('memories').insert({
        'space_id': widget.spaceId, 'created_by': user,
        'title': caption.isEmpty ? 'Daily selfie · $today' : caption,
        'body': '', 'memory_date': today,
        'visibility': _private ? 'private' : 'shared',
        'memory_type': 'daily_selfie', 'photo_layout': 'polaroid',
      }).select('id').single();
      created = row['id'].toString();
      await MemoryPhotoService(_db).addFiles(created, [photo]);
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
    final days = List.generate(7, (i) => DateTime.now().subtract(Duration(days: 6 - i)));
    bool posted(DateTime d, bool mine) => _week.any((r) =>
        r['memory_date']?.toString() == CalendarRules.sqlDate(d) &&
        (r['created_by'] == me) == mine);
    Widget dot(bool on, Color c) => Container(
        width: 9, height: 9, margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(shape: BoxShape.circle,
            color: on ? c : scheme.outlineVariant));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tt('This week'), style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (final d in days)
          Column(children: [
            Text(tt(MaterialLocalizations.of(context).narrowWeekdays[d.weekday % 7]),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Row(children: [dot(posted(d, true), scheme.primary), dot(posted(d, false), scheme.tertiary)]),
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
      meta: MetaStrip(value: MetaValues(shared: !_private), showBelongs: false, showDate: false,
        enabled: !_saving, onChanged: (v) => setState(() => _private = !v.shared)),
      body: ListView(padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 24), children: [
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
