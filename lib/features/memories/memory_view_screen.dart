import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onespace/l10n/phrases.dart';

import '../../core/form_kit.dart';
import '../sharing/object_permissions.dart';
import 'memory_export.dart';
import 'memory_photo_layouts.dart';
import 'memory_photo_service.dart';
import 'selfie_studio_screen.dart';

/// Signs one private photo and shows it (cached for a minute).
class SignedMemoryPhoto extends StatefulWidget {
  const SignedMemoryPhoto({super.key, required this.path, this.height = 180, this.fit = BoxFit.cover});
  final String path;
  final double height;
  final BoxFit fit;
  static final Map<String, ({DateTime at, Future<String> url})> _cache = {};
  static Future<String> sign(String path) {
    final hit = _cache[path];
    if (hit != null && DateTime.now().difference(hit.at) < const Duration(seconds: 80)) return hit.url;
    final url = MemoryPhotoService(Supabase.instance.client).signedUrl(path);
    _cache[path] = (at: DateTime.now(), url: url);
    return url;
  }
  @override
  State<SignedMemoryPhoto> createState() => _SignedMemoryPhotoState();
}

class _SignedMemoryPhotoState extends State<SignedMemoryPhoto> {
  late Future<String> url = SignedMemoryPhoto.sign(widget.path);
  @override
  Widget build(BuildContext context) => FutureBuilder<String>(future: url, builder: (ctx, s) {
    if (!s.hasData) {
      return SizedBox(height: widget.height, child: s.hasError
        ? IconButton(onPressed: () => setState(() { SignedMemoryPhoto._cache.remove(widget.path); url = SignedMemoryPhoto.sign(widget.path); }),
            icon: const Icon(Icons.refresh))
        : const Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return GestureDetector(
      onTap: () => showDialog<void>(context: context, builder: (d) => Dialog(insetPadding: const EdgeInsets.all(10),
        child: InteractiveViewer(maxScale: 5, child: Image.network(s.data!, fit: BoxFit.contain)))),
      child: ClipRRect(borderRadius: BorderRadius.circular(10),
        child: Image.network(s.data!, height: widget.height, width: double.infinity, fit: widget.fit,
          errorBuilder: (_, __, ___) => SizedBox(height: widget.height, child: const Center(child: Icon(Icons.broken_image_outlined))))));
  });
}

/// R70 (Ahmed): a story or a daily selfie opens to read, not to edit. Edit
/// is a button; the page can be saved as a PDF or sent by email.
class MemoryViewScreen extends StatefulWidget {
  const MemoryViewScreen({super.key, required this.memoryId, required this.spaceId, this.onEdit});
  final String memoryId, spaceId;
  final Future<void> Function(Map<String, dynamic> memory)? onEdit;
  @override
  State<MemoryViewScreen> createState() => _MemoryViewScreenState();
}

class _MemoryViewScreenState extends State<MemoryViewScreen> {
  final db = Supabase.instance.client;
  Map<String, dynamic>? memory;
  List<Map<String, dynamic>> photos = [];
  SpacePeople? people;
  bool loading = true, exporting = false;
  String? error;

  String get me => db.auth.currentUser?.id ?? '';
  bool get selfie => memory?['memory_type'] == 'daily_selfie';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final m = await db.from('memories').select().eq('id', widget.memoryId).single();
      final p = await db.from('memory_photos').select('id,object_path,caption,created_by,display_order,created_at')
        .eq('memory_id', widget.memoryId).isFilter('archived_at', null).order('display_order').order('created_at');
      final pp = await SpacePeople.load();
      if (!mounted) return;
      setState(() { memory = m; photos = List<Map<String, dynamic>>.from(p); people = pp; loading = false; error = null; });
    } catch (_) {
      if (mounted) setState(() { loading = false; error = 'Could not open this memory.'; });
    }
  }

  bool get editable {
    final m = memory;
    if (m == null) return false;
    return ObjectPermissions.canEdit(visibility: m['visibility'].toString(),
      createdBy: m['created_by'].toString(), userId: me);
  }

  String who(String? id) => id == me ? 'You' : (people?.partnerName ?? 'Partner');

  String dateLabel() {
    final d = DateTime.tryParse((memory?['memory_date'] ?? '').toString());
    return d == null ? '' : MaterialLocalizations.of(context).formatFullDate(d);
  }

  Future<void> export() async {
    final m = memory;
    if (m == null || exporting) return;
    final email = await MemoryExport.askHow(context);
    if (email == null || !mounted) return;
    setState(() => exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final urls = <String>[];
      for (final p in photos) {
        urls.add(await SignedMemoryPhoto.sign(p['object_path'].toString()));
      }
      final bytes = await MemoryExport.download(urls);
      final title = (m['title'] ?? 'Memory').toString();
      final pdf = await MemoryExport.storyPdf(
        title: selfie ? '${tt('Daily selfie')} · ${dateLabel()}' : title,
        dateLabel: selfie ? title : dateLabel(),
        body: (m['body'] ?? '').toString(), photos: bytes,
        captions: [for (final p in photos) selfie
          ? [tt(who(p['created_by']?.toString())), (p['caption'] ?? '').toString()].where((x) => x.isNotEmpty).join(' · ')
          : (p['caption'] ?? '').toString()]);
      await MemoryExport.share(pdf, name: title, email: email);
    } on PlatformException catch (e) {
      if (e.code != 'CANCELLED') messenger.showSnackBar(SnackBar(content: Text(e.message ?? tt('Could not create the PDF.'))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(tt('Could not create the PDF. Check your connection and try again.'))));
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> addMySelfie() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (_) => SelfieStudioScreen(spaceId: widget.spaceId, addToMemoryId: widget.memoryId,
        partnerName: people?.partnerName)));
    if (saved == true && mounted) await load();
  }

  Widget selfieBody(ThemeData theme) {
    final mine = photos.where((p) => p['created_by'] == me).toList();
    final theirs = photos.where((p) => p['created_by'] != me).toList();
    final shared = memory?['visibility'] == 'shared';
    Widget polaroid(Map<String, dynamic>? p, String name, {VoidCallback? onAdd}) => Expanded(child: Transform.rotate(
      angle: name == 'You' ? -.025 : .025,
      child: Container(
        margin: const EdgeInsets.all(6), padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(1, 5))]),
        child: Column(children: [
          AspectRatio(aspectRatio: 1, child: p == null
            ? InkWell(onTap: onAdd, child: Container(color: theme.colorScheme.surfaceContainerHighest,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(onAdd == null ? Icons.hourglass_empty : Icons.add_a_photo_outlined, color: theme.colorScheme.primary, size: 36),
                  const SizedBox(height: 6),
                  Text(tt(onAdd == null ? 'Waiting…' : 'Add your selfie'), textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF3B3533))),
                ])))
            : SignedMemoryPhoto(path: p['object_path'].toString(), height: 400)),
          const SizedBox(height: 6),
          Text(tt(name), style: const TextStyle(color: Color(0xFF3B3533), fontWeight: FontWeight.w700)),
          if (p != null && (p['caption'] ?? '').toString().isNotEmpty)
            Text(tt(p['caption'].toString()), maxLines: 2, textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF3B3533), fontSize: 12)),
        ]))));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        polaroid(mine.firstOrNull, 'You', onAdd: shared || memory?['created_by'] == me ? addMySelfie : null),
        if (shared) polaroid(theirs.firstOrNull, people?.partnerName ?? 'Partner'),
      ]),
      if (shared) Padding(padding: const EdgeInsets.only(top: 10), child: Text(
        tt('A daily selfie is made together: each of you adds your own photo to the same day.'),
        textAlign: TextAlign.center, style: theme.textTheme.bodySmall)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = memory;
    return Scaffold(
      appBar: AppBar(title: Text(tt(selfie ? 'Daily selfie' : 'Story')), actions: [
        if (m != null && editable && !selfie && widget.onEdit != null) IconButton(tooltip: tt('Edit'),
          icon: const Icon(Icons.edit_outlined), onPressed: () async { await widget.onEdit!(m); if (mounted) await load(); }),
        if (m != null) IconButton(tooltip: tt('PDF or email'),
          icon: exporting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.ios_share_outlined),
          onPressed: exporting ? null : export),
      ]),
      body: loading ? const Center(child: CircularProgressIndicator())
        : m == null ? Center(child: Text(tt(error ?? 'Not available')))
        : RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 30), children: [
            Text(tt(m['title'].toString()), style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(tt([dateLabel(), who(m['created_by']?.toString()),
              m['visibility'] == 'private' ? 'Only me' : 'Both of us'].map(tt).join(' · ')),
              style: theme.textTheme.bodySmall),
            const SizedBox(height: 14),
            if (selfie) selfieBody(theme) else ...[
              MemoryPhotoLayout(layout: (m['photo_layout'] ?? 'grid').toString(), photos: photos,
                photo: (p, h) => SignedMemoryPhoto(path: p['object_path'].toString(), height: h)),
              if ((m['body'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                SelectableText(m['body'].toString(), style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
              ],
              if (photos.isEmpty && (m['body'] ?? '').toString().trim().isEmpty)
                Text(tt('Nothing here yet. Tap Edit to add the story and photos.')),
            ],
          ])),
    );
  }
}
