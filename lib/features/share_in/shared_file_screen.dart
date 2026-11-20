import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/editor_scaffold.dart';
import '../../core/app_env.dart';
import '../calendar/calendar_rules.dart';
import '../memories/memory_photo_service.dart';
import '../../core/form_kit.dart';
import 'share_intake_rules.dart';
import 'package:onespace/l10n/phrases.dart';

/// R55: save a photo or PDF shared from another app.
/// Default: Items to sort, only me. A photo can go straight to Memories.
class SharedFileScreen extends StatefulWidget {
  const SharedFileScreen({super.key, required this.spaceId, required this.file});
  final String spaceId;
  final SharedFile file;
  @override
  State<SharedFileScreen> createState() => _SharedFileScreenState();
}

class _SharedFileScreenState extends State<SharedFileScreen> {
  static const bucket = 'onespace-share-in';
  final db = Supabase.instance.client;
  late final title = TextEditingController(text: widget.file.title);
  late final note = TextEditingController(text: widget.file.note);
  bool shared = !OneSpaceEnv.isProduction, saving = false, toMemory = false;
  String? error;

  @override
  void dispose() {
    title.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = db.auth.currentUser?.id;
    if (user == null || title.text.trim().isEmpty) return;
    if(!OneSpaceEnv.isProduction&&(!shared||widget.spaceId.isEmpty)){
      setState(()=>error='Private file storage is not enabled yet. '
        'Connect with a partner to save files in your shared space.');
      return;
    }
    setState(() { saving = true; error = null; });
    final bytes = Uint8List.fromList(widget.file.bytes);
    try {
      if (toMemory && widget.file.isImage) {
        final memory = await db.from('memories').insert({
          'space_id': widget.spaceId, 'created_by': user,
          'title': title.text.trim(), 'body': note.text.trim(),
          'memory_date': CalendarRules.sqlDate(DateTime.now()),
          'visibility': shared ? 'shared' : 'private',
        }).select('id').single();
        await MemoryPhotoService(db).addFiles(memory['id'].toString(),
            [XFile.fromData(bytes, name: widget.file.name, mimeType: widget.file.mime)]);
      } else {
        final path = '$user/${const Uuid().v4()}.${widget.file.extension}';
        final storage = db.storage.from(bucket);
        await storage.uploadBinary(path, bytes,
            fileOptions: FileOptions(contentType: widget.file.mime, upsert: false));
        try {
          await db.from('items_to_sort').insert({
            'space_id': widget.spaceId, 'created_by': user,
            'title': title.text.trim(), 'note': note.text.trim(),
            'visibility': shared ? 'shared' : 'private',
            'file_path': path, 'file_name': widget.file.name.isEmpty ? null : widget.file.name,
            'file_mime': widget.file.mime, 'file_size': bytes.length,
          });
        } catch (_) {
          try { await storage.remove([path]); } catch (_) {}
          rethrow;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          tt(toMemory && widget.file.isImage ? 'Saved to Memories.' : 'Saved to Items to sort.'))));
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() { saving = false; error = 'Could not save: ${e.message}'; });
    } on StorageException catch (e) {
      if (mounted) setState(() { saving = false; error = 'Could not upload: ${e.message}'; });
    } catch (_) {
      if (mounted) setState(() { saving = false; error = 'Could not save this file. Please retry.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = widget.file;
    final kb = (f.bytes.length / 1024).round();
    return EditorScaffold(
      title: f.isImage ? tt('Save shared photo') : tt('Save shared PDF'),
      isNew: true,
      isChanged: () => true,
      isComplete: () => title.text.trim().isNotEmpty &&
        (OneSpaceEnv.isProduction || widget.spaceId.isNotEmpty),
      listenTo: [title, note],
      saving: saving,
      onSave: _save,
      meta: MetaStrip(value: MetaValues(shared: shared), showBelongs: false, showDate: false,
        enabled: !saving&&OneSpaceEnv.isProduction,
        onChanged: (v) => setState(() => shared = v.shared)),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        if(!OneSpaceEnv.isProduction) Padding(
          padding:const EdgeInsets.only(bottom:10),
          child:Text(tt('Personal file storage is not enabled yet. '
            'Files can only be saved to your current shared space; '
            'private links and notes can still be saved to your personal inbox.'),
            style:Theme.of(context).textTheme.bodySmall)),
        if (f.isImage)
          ClipRRect(borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 260),
              child: Image.memory(Uint8List.fromList(f.bytes), fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => SizedBox(height: 80,
                  child: Center(child: Text(tt('Preview not available')))))))
        else
          Card(elevation: 0, color: theme.colorScheme.surfaceContainerHighest, child: ListTile(
            leading: Icon(Icons.picture_as_pdf_outlined, color: theme.colorScheme.primary, size: 34),
            title: Text(tt(f.name.isEmpty ? 'PDF' : f.name), maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(tt(kb >= 1024 ? '${(kb / 1024).toStringAsFixed(1)} MB' : '$kb KB')))),
        const SizedBox(height: 16),
        TextField(controller: title, maxLength: 180,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: requiredLabel(tt('Title')),
            border: const OutlineInputBorder())),
        TextField(controller: note, maxLength: 5000, minLines: 2, maxLines: 5,
          decoration: InputDecoration(labelText: tt('Note (optional)'),
            border: OutlineInputBorder())),
        if (f.isImage) ...[
          ChoiceRow<bool>(label: tt('Save to'), options: const {false: 'Items to sort', true: 'Memories'},
            icons: const {false: Icons.inbox_outlined, true: Icons.photo_album_outlined},
            selected: toMemory, onSelected: (v) => setState(() => toMemory = v ?? toMemory)),
        ],
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text(tt(error!), style: TextStyle(color: theme.colorScheme.error))),
      ]),
    );
  }
}
