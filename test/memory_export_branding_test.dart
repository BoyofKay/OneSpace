import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/memories/memory_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('story and scrapbook PDFs are built with OneSpace branding', () async {
    final story = await MemoryExport.storyPdf(title: 'Our day', dateLabel: '21 Nov 2026', body: 'Hello');
    expect(story.length, greaterThan(1000));
    final png = File('assets/branding/mark.png').readAsBytesSync();
    final book = await MemoryExport.pagesPdf([png], title: 'Book');
    expect(book.length, greaterThan(1000));
    expect(String.fromCharCodes(story), contains('onespace.live'));
  });
  test('email text and html carry the identity and link', () {
    expect(MemoryExport.emailText('Our day'), contains('https://onespace.live'));
    final html = MemoryExport.emailHtml('<b>x</b>');
    expect(html, contains('icon-512.png'));
    expect(html, contains('&lt;b&gt;'));
  });
}

