import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onespace/l10n/phrases.dart';

/// R65: a short "What's new" sheet, shown once per release after an update.
/// Bump [release] and rewrite [_items] when there is something worth telling.
class WhatsNew {
  const WhatsNew._();
  static const release = 'r65';
  static const _key = 'whats_new_seen_v1';

  static const _items = <(IconData, String, String, String, String)>[
    (Icons.help_outline, 'Help is in Me', 'Questions and answers, Contact us and Report a technical issue now live in the Me tab.',
      'المساعدة في «أنا»', 'الأسئلة والأجوبة و«تواصل معنا» و«الإبلاغ عن مشكلة تقنية» موجودة الآن في تبويب «أنا».'),
    (Icons.favorite_outline, 'More little love', 'Eight new gestures — I love you, a kiss, safe travels, date night and more.',
      'لمسات حب أكثر', 'ثماني لفتات جديدة — أحبك، قبلة، رحلة آمنة، موعدنا، والمزيد.'),
    (Icons.palette_outlined, 'New looks', 'Five new color themes and background patterns, plus Ramadan and National Day decorations. Me → Settings → Appearance.',
      'مظهر جديد', 'خمس سمات ألوان جديدة ونقوش للخلفية، وزينة رمضان واليوم الوطني. «أنا» ← «الإعدادات» ← «المظهر».'),
    (Icons.translate, 'Better Arabic', 'More screens and messages now read naturally in Arabic.',
      'عربية أفضل', 'مزيد من الشاشات والرسائل أصبحت تُقرأ بالعربية بشكل طبيعي.'),
  ];

  /// Shows the sheet if this release hasn't been seen on this phone. A brand-new
  /// install just records the release (nothing is "new" to a new person).
  static Future<void> maybeShow(BuildContext context) async {
    try {
      final prefs = SharedPreferencesAsync();
      final seen = await prefs.getString(_key);
      await prefs.setString(_key, release);
      if (seen == null || seen == release || !context.mounted) return;
      await show(context);
    } catch (_) {}
  }

  static Future<void> show(BuildContext context) {
    final ar = OneSpacePhrases.arabic;
    return showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ar ? 'ما الجديد' : "What's new", style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          for (final (icon, en, enBody, arTitle, arBody) in _items) Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 18, backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(icon, size: 20, color: theme.colorScheme.onPrimaryContainer)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ar ? arTitle : en, style: theme.textTheme.titleSmall),
                Text(ar ? arBody : enBody, style: theme.textTheme.bodyMedium),
              ])),
            ])),
          const SizedBox(height: 4),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: () => Navigator.pop(ctx), child: Text(ar ? 'رائع' : 'Got it'))),
        ]),
      ));
    });
  }
}
