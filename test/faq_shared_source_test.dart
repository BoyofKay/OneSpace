import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/support/faq_content.dart';

/// 27 Nov 2026 (owner): one FAQ for the app and the website. The app list is
/// generated from tools/faq/source/*.json (a copy of the website's content/faq).
void main() {
  test('App FAQ matches the shared source exactly', () {
    final files = Directory('tools/faq/source').listSync().whereType<File>()
        .where((f) => f.path.endsWith('.json')).toList()..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty);
    final expected = <String>[];
    for (final f in files) {
      final g = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      for (final i in (g['items'] as List).cast<Map<String, dynamic>>()) {
        if (const ['both', 'app'].contains(i['where'] ?? 'both')) expected.add((i['q'] as Map)['en'] as String);
      }
    }
    expect(faqEntries.map((e) => e.qEn).toList(), expected,
        reason: 'Run python3 tools/faq/sync_faq.py ../onespace-app after changing the FAQ');
    for (final e in faqEntries) {
      expect(e.blocks, isNotEmpty);
      expect(e.qAr.trim(), isNotEmpty);
      for (final b in e.blocks) {
        expect(b.en.length, b.ar.length);
        expect(['p', 'steps', 'bullets'], contains(b.kind));
      }
    }
  });

  test('Every feature has a "How do I use" answer that opens its video tutorial', () {
    final howTo = faqEntries.where((e) => e.topicEn == 'How to use each feature').toList();
    expect(howTo.length, greaterThanOrEqualTo(14));
    final videos = howTo.where((e) => e.tutorial != null).toList();
    expect(videos.length, 17, reason: 'one video tutorial per feature (D110)');
    for (final e in videos) {
      expect(e.tutorialUrl, startsWith('https://onespace.live/tutorials.html#'));
    }
  });
}
