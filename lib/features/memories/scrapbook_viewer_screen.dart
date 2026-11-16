import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onespace/l10n/phrases.dart';

import 'memory_export.dart';
import 'memory_photo_service.dart';
import 'scrapbook_page_canvas.dart';
import 'scrapbook_studio_screen.dart';

/// R70 (Ahmed): tapping a scrapbook opens it to read, page by page (swipe).
/// Edit opens the studio; the whole book can be saved as a PDF or sent by email.
class ScrapbookViewerScreen extends StatefulWidget {
  const ScrapbookViewerScreen({super.key, required this.spaceId, required this.memoryId});
  final String spaceId, memoryId;
  @override
  State<ScrapbookViewerScreen> createState() => _ScrapbookViewerScreenState();
}

class _ScrapbookViewerScreenState extends State<ScrapbookViewerScreen> {
  final db = Supabase.instance.client;
  final controller = PageController();
  final keys = <String, GlobalKey>{};
  Map<String, dynamic>? memory;
  List<Map<String, dynamic>> pages = [], photos = [];
  final signed = <String, String>{};
  bool loading = true, canEdit = false, exporting = false;
  int index = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final me = db.auth.currentUser?.id;
      final m = await db.from('memories').select('id,title,created_by,visibility,memory_date')
        .eq('id', widget.memoryId).single();
      final p = await db.from('scrapbook_pages').select().eq('memory_id', widget.memoryId).order('page_order');
      final ph = await db.from('memory_photos').select('id,object_path').eq('memory_id', widget.memoryId)
        .isFilter('archived_at', null).limit(200);
      final inv = await db.from('scrapbook_invites').select('invited_user_id,status').eq('memory_id', widget.memoryId);
      final service = MemoryPhotoService(db);
      final urls = <String, String>{};
      final used = {for (final page in p) for (var n = 1; n <= 4; n++) if (page['photo_${n}_id'] != null) page['photo_${n}_id'].toString()};
      for (final row in ph) {
        if (!used.contains(row['id'].toString())) continue;
        try { urls[row['id'].toString()] = await service.signedUrl(row['object_path'].toString()); } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        memory = m;
        pages = List<Map<String, dynamic>>.from(p)
          ..sort((a, b) => ((a['page_order'] as num?) ?? 0).compareTo((b['page_order'] as num?) ?? 0));
        photos = List<Map<String, dynamic>>.from(ph);
        signed..clear()..addAll(urls);
        canEdit = m['created_by'] == me || inv.any((i) => i['invited_user_id'] == me && i['status'] == 'accepted');
        index = index.clamp(0, pages.isEmpty ? 0 : pages.length - 1);
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { loading = false; error = 'Could not open this scrapbook.'; });
    }
  }

  Future<void> edit() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
      ScrapbookStudioScreen(spaceId: widget.spaceId, memoryId: widget.memoryId)));
    if (mounted) await load();
  }

  /// Draws each page and puts them in one PDF.
  Future<void> export() async {
    if (exporting || pages.isEmpty) return;
    final email = await MemoryExport.askHow(context);
    if (email == null || !mounted) return;
    setState(() => exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    final start = index;
    try {
      for (final url in signed.values) {
        await precacheImage(NetworkImage(url), context);
      }
      final shots = <Uint8List>[];
      for (var i = 0; i < pages.length; i++) {
        controller.jumpToPage(i);
        await Future<void>.delayed(const Duration(milliseconds: 350));
        await WidgetsBinding.instance.endOfFrame;
        final key = keys[pages[i]['id'].toString()];
        final box = key?.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (box == null) continue;
        final image = await box.toImage(pixelRatio: 2.5);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (data != null) shots.add(data.buffer.asUint8List());
      }
      controller.jumpToPage(start);
      if (shots.isEmpty) throw StateError('No pages');
      final title = (memory?['title'] ?? 'Scrapbook').toString();
      final pdf = await MemoryExport.pagesPdf(shots, title: title);
      await MemoryExport.share(pdf, name: title, email: email);
    } on PlatformException catch (e) {
      if (e.code != 'CANCELLED') messenger.showSnackBar(SnackBar(content: Text(e.message ?? tt('Could not create the PDF.'))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(tt('Could not create the PDF. Check your connection and try again.'))));
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pics = {for (final p in photos) p['id'].toString(): p};
    return Scaffold(
      appBar: AppBar(title: Text(tt((memory?['title'] ?? 'Scrapbook').toString()), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (canEdit) IconButton(tooltip: tt('Edit'), icon: const Icon(Icons.edit_outlined), onPressed: edit),
          IconButton(tooltip: tt('PDF or email'), onPressed: exporting ? null : export,
            icon: exporting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.ios_share_outlined)),
        ]),
      body: loading ? const Center(child: CircularProgressIndicator())
        : pages.isEmpty ? Center(child: Text(tt(error ?? 'This scrapbook has no pages yet.')))
        : Column(children: [
            Expanded(child: PageView.builder(
              controller: controller, itemCount: pages.length,
              onPageChanged: (v) => setState(() => index = v),
              itemBuilder: (_, i) {
                final key = keys.putIfAbsent(pages[i]['id'].toString(), () => GlobalKey());
                return Center(child: Padding(padding: const EdgeInsets.all(14), child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: RepaintBoundary(key: key, child: ScrapbookPageCanvas(page: pages[i], photos: pics, signedUrls: signed)))));
              })),
            Padding(padding: const EdgeInsets.only(bottom: 16), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(tooltip: tt('Previous page'), onPressed: index == 0 ? null
                : () => controller.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                icon: const Icon(Icons.chevron_left)),
              Text('${index + 1} / ${pages.length}', style: theme.textTheme.titleMedium),
              IconButton(tooltip: tt('Next page'), onPressed: index >= pages.length - 1 ? null
                : () => controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                icon: const Icon(Icons.chevron_right)),
            ])),
            if (exporting) Padding(padding: const EdgeInsets.only(bottom: 12),
              child: Text(tt('Preparing the PDF, page by page…'), style: theme.textTheme.bodySmall)),
          ]),
    );
  }
}
