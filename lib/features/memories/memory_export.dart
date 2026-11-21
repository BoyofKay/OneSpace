import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:onespace/l10n/phrases.dart';

/// R70: memories, daily selfies and scrapbooks as a PDF, saved and shared or
/// sent by email. Text uses Noto Sans with Noto Naskh Arabic for Arabic.
class MemoryExport {
  MemoryExport._();
  static const _channel = MethodChannel('onespace/scrapbook_export');
  static pw.ThemeData? _theme;

  static const site = 'https://onespace.live';
  static const tagline = 'Two of Us. One Space.';
  static const _brand = PdfColor.fromInt(0xFFB4536B);
  static pw.MemoryImage? _logo;
  static Future<pw.MemoryImage?> _mark() async {
    if (_logo != null) return _logo;
    try {
      final bytes = await rootBundle.load('assets/branding/mark.png');
      return _logo = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) { return null; }
  }

  /// The OneSpace identity at the top of a memory PDF.
  static pw.Widget _brandHeader(pw.MemoryImage? logo) => pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 14),
    padding: const pw.EdgeInsets.only(bottom: 8),
    decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _brand, width: .6))),
    child: pw.Row(children: [
      if (logo != null) pw.Image(logo, width: 26, height: 26),
      if (logo != null) pw.SizedBox(width: 8),
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('OneSpace', style: pw.TextStyle(fontSize: 15, color: _brand, fontWeight: pw.FontWeight.bold)),
        pw.Text(tagline, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ]),
      pw.Spacer(),
      pw.UrlLink(destination: site, child: pw.Text('onespace.live',
        style: const pw.TextStyle(fontSize: 9, color: _brand, decoration: pw.TextDecoration.underline))),
    ]));

  /// The OneSpace identity on every page's foot, with a link.
  static pw.Widget _brandFooter(pw.Context ctx, String footer) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text(footer, style: const pw.TextStyle(fontSize: 8, color: _brand)),
      pw.UrlLink(destination: site, child: pw.Text('Made with OneSpace · onespace.live',
        style: const pw.TextStyle(fontSize: 8, color: _brand))),
      pw.Text('${ctx.pageNumber}/${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ]);

  /// The email text that goes with a shared memory.
  static String emailText(String name) =>
    '"$name" was shared with you from OneSpace.\n\n'
    'OneSpace: $tagline\nThe app for couples to plan, remember and stay close.\n$site';
  static String emailHtml(String name) =>
    '<div style="font-family:Arial,sans-serif;color:#3B2F33">'
    '<table role="presentation" style="border-bottom:2px solid #B4536B;padding-bottom:8px;margin-bottom:14px"><tr>'
    '<td><img src="$site/assets/icon-512.png" width="40" height="40" alt="OneSpace" style="border-radius:8px"></td>'
    '<td style="padding-left:10px"><div style="font-size:20px;font-weight:bold;color:#B4536B">OneSpace</div>'
    '<div style="font-size:12px;color:#666">$tagline</div></td></tr></table>'
    '<p>&ldquo;${_html(name)}&rdquo; was shared with you from OneSpace. The PDF is attached.</p>'
    '<p style="font-size:13px;color:#666">The app for couples to plan, remember and stay close.<br>'
    '<a href="$site" style="color:#B4536B">onespace.live</a></p></div>';
  static String _html(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  static Future<pw.ThemeData> _fonts() async {
    final ready = _theme;
    if (ready != null) return ready;
    final latin = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final arabic = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf'));
    return _theme = pw.ThemeData.withFont(base: latin, bold: latin, fontFallback: [arabic]);
  }

  static bool isArabic(String s) => RegExp(r'[؀-ۿ]').hasMatch(s);
  static pw.TextDirection _dir(String s) => isArabic(s) ? pw.TextDirection.rtl : pw.TextDirection.ltr;

  /// Downloads photos from their (signed) addresses; skips any that fail.
  static Future<List<Uint8List>> download(List<String> urls) async {
    final out = <Uint8List>[];
    for (final u in urls) {
      try {
        final r = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 20));
        if (r.statusCode == 200) out.add(r.bodyBytes);
      } catch (_) {}
    }
    return out;
  }

  /// A story or a daily selfie: title, date, photos, then the words.
  static Future<Uint8List> storyPdf({required String title, required String dateLabel,
      String body = '', List<Uint8List> photos = const [], List<String> captions = const [],
      String footer = 'OneSpace · our story'}) async {
    final theme = await _fonts();
    final doc = pw.Document(theme: theme, title: title, creator: 'OneSpace · onespace.live', producer: 'OneSpace');
    const accent = _brand;
    final logo = await _mark();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 40, marginRight: 40, marginTop: 44, marginBottom: 40),
      header: (ctx) => ctx.pageNumber == 1 ? _brandHeader(logo) : pw.SizedBox(),
      footer: (ctx) => _brandFooter(ctx, footer),
      build: (ctx) => [
        pw.Text(title, textDirection: _dir(title),
          style: pw.TextStyle(fontSize: 26, color: const PdfColor.fromInt(0xFF3B2F33))),
        pw.SizedBox(height: 4),
        pw.Text(dateLabel, textDirection: _dir(dateLabel), style: const pw.TextStyle(fontSize: 11, color: accent)),
        pw.Container(margin: const pw.EdgeInsets.symmetric(vertical: 12), height: 1, color: accent),
        if (photos.length == 1) pw.Center(child: pw.ClipRRect(horizontalRadius: 6, verticalRadius: 6,
          child: pw.Image(pw.MemoryImage(photos.first), height: 420, fit: pw.BoxFit.contain))),
        if (photos.length > 1) pw.Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < photos.length; i++) pw.Container(width: 250,
            padding: const pw.EdgeInsets.fromLTRB(6, 6, 6, 14),
            decoration: pw.BoxDecoration(color: PdfColors.white,
              border: pw.Border.all(color: PdfColors.grey300, width: .5)),
            child: pw.Column(children: [
              pw.Image(pw.MemoryImage(photos[i]), height: 200, fit: pw.BoxFit.cover),
              if (i < captions.length && captions[i].isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text(captions[i], textDirection: _dir(captions[i]), style: const pw.TextStyle(fontSize: 9))),
            ])),
        ]),
        if (body.trim().isNotEmpty) pw.SizedBox(height: 16),
        for (final para in body.trim().split(RegExp(r'\n\s*\n')))
          if (para.trim().isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(para.trim(), textDirection: _dir(para), textAlign: isArabic(para) ? pw.TextAlign.right : pw.TextAlign.left,
              style: const pw.TextStyle(fontSize: 12, lineSpacing: 3))),
      ]));
    return doc.save();
  }

  /// Scrapbook pages already drawn as pictures: one picture per PDF page,
  /// framed exactly like a story or daily selfie PDF (OneSpace header on the
  /// first page, the same footer on every page).
  static Future<Uint8List> pagesPdf(List<Uint8List> pages, {required String title,
      String footer = 'OneSpace · our scrapbook'}) async {
    final doc = pw.Document(theme: await _fonts(), title: title, creator: 'OneSpace · onespace.live', producer: 'OneSpace');
    final logo = await _mark();
    final images = [for (final png in pages) pw.MemoryImage(png)];
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 40, marginRight: 40, marginTop: 44, marginBottom: 40),
      header: (ctx) => ctx.pageNumber == 1 ? _brandHeader(logo) : pw.SizedBox(),
      footer: (ctx) => _brandFooter(ctx, footer),
      build: (ctx) => [
        pw.Text(title, textDirection: _dir(title),
          style: pw.TextStyle(fontSize: 26, color: const PdfColor.fromInt(0xFF3B2F33))),
        pw.SizedBox(height: 12),
        for (final image in images) pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          height: 600,
          alignment: pw.Alignment.center,
          child: pw.Image(image, fit: pw.BoxFit.contain)),
      ]));
    return doc.save();
  }

  /// Asks: save/share the PDF, or send it by email. Null when closed.
  static Future<bool?> askHow(BuildContext context) => showModalBottomSheet<bool>(
    context: context, showDragHandle: true, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.picture_as_pdf_outlined), title: Text(tt('Save or share as PDF')),
        subtitle: Text(tt('Saved in Downloads › OneSpace, then share it anywhere')),
        onTap: () => Navigator.pop(ctx, false)),
      ListTile(leading: const Icon(Icons.email_outlined), title: Text(tt('Send by email')),
        subtitle: Text(tt('Opens your email with the PDF attached')),
        onTap: () => Navigator.pop(ctx, true)),
      const SizedBox(height: 8),
    ])));

  static Future<void> share(Uint8List pdf, {required String name, bool email = false}) =>
    _channel.invokeMethod<Object>('sharePdf', {'bytes': pdf, 'name': name, 'email': email,
      'subject': '$name · OneSpace', 'text': emailText(name), 'html': emailHtml(name)});
}
