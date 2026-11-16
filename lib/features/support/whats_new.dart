import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onespace/l10n/phrases.dart';

/// R65: a short "What's new" sheet, shown once per release after an update.
/// Bump [release] and rewrite [_items] when there is something worth telling.
class WhatsNew {
  const WhatsNew._();
  static const release = 'r69';
  static const _key = 'whats_new_seen_v1';

  static const _items = <(IconData, String, String, String, String)>[
    (Icons.cake_outlined, 'Birthdays & special dates', 'Settings now has places for your birthday, your partner\'s, your anniversary and your own dates. They show in the calendar and start occasions.',
      'أعياد الميلاد والتواريخ المميزة', 'في الإعدادات أماكن لعيد ميلادك وميلاد شريكك وذكرى زواجكما وتواريخكما الخاصة. تظهر في التقويم وتبدأ منها المناسبات.'),
    (Icons.payments_outlined, 'Your currency', 'Choose a preferred currency next to the language; every price and budget starts with it. Holidays now include Ramadan and the Eids.',
      'عملتك', 'اختر عملتك المفضلة بجانب اللغة؛ تبدأ بها كل الأسعار والميزانيات. وأصبحت العطلات تشمل رمضان والأعياد.'),
    (Icons.photo_camera_front_outlined, 'Selfies together', 'Your daily selfie and your partner\'s sit side by side in the same day. Memories open to read, with PDF and email.',
      'سيلفي معًا', 'سيلفي اليوم لك ولشريكك جنبًا إلى جنب في اليوم نفسه. والذكريات تُفتح للقراءة مع PDF والبريد.'),
    (Icons.auto_stories_outlined, 'Scrapbooks, reworked', '22 designs, type and tap right on the page, a Save button, remove pages, and read page by page.',
      'دفاتر الذكريات من جديد', '22 تصميمًا، اكتب واضغط على الصفحة مباشرة، زر حفظ، حذف الصفحات، وتصفّح صفحة بصفحة.'),
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
