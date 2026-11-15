import 'dart:ui' show PlatformDispatcher;

import 'package:material_ui/material_ui.dart';

import 'phrases_ar.dart';

/// R62: the phrase layer. `tt('English text')` shows the Arabic phrase when
/// the app language is Arabic, otherwise the English text unchanged.
class OneSpacePhrases {
  const OneSpacePhrases._();

  /// Language the app is showing ('en' or 'ar'); set from the app's locale.
  static String lang = PlatformDispatcher.instance.locale.languageCode == 'ar' ? 'ar' : 'en';

  static bool get arabic => lang == 'ar';

  /// Called from MaterialApp.builder. When the language changes, every
  /// screen is rebuilt in place so labels switch without losing your place.
  static void follow(BuildContext context) {
    final next = Localizations.localeOf(context).languageCode == 'ar' ? 'ar' : 'en';
    if (next == lang) return;
    lang = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void mark(Element e) { e.markNeedsBuild(); e.visitChildren(mark); }
      WidgetsBinding.instance.rootElement?.visitChildren(mark);
    });
  }

  static final _edges = RegExp(r'^([^A-Za-z]*)(.*?)([\s:·•,.!?…]*)$', dotAll: true);

  static String translate(String en) {
    if (lang != 'ar' || en.isEmpty) return en;
    final exact = arPhrases[en];
    if (exact != null) return exact;
    final m = _edges.firstMatch(en);
    if (m == null) return en;
    final core = arPhrases[m.group(2)!] ?? arPhrases['${m.group(2)}.'];
    if (core == null) return en;
    final tail = m.group(3)!.replaceAll('?', '؟').replaceAll(',', '،');
    return '${m.group(1)}$core$tail';
  }
}

/// Translate a fixed English UI phrase (see [OneSpacePhrases]).
String tt(String en) => OneSpacePhrases.translate(en);
