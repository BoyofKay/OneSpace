import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onespace/l10n/phrases.dart';

/// R65: a short "What's new" sheet, shown once per release after an update.
/// Bump [release] and rewrite [_items] when there is something worth telling.
class WhatsNew {
  const WhatsNew._();
  static const release = 'r66';
  static const _key = 'whats_new_seen_v1';

  static const _items = <(IconData, String, String, String, String)>[
    (Icons.repeat, 'One way to repeat', 'Reminders, events and to-do lists now repeat the same way — daily, weekdays, chosen days, monthly, yearly, with an end date.',
      'طريقة واحدة للتكرار', 'التذكيرات والمواعيد وقوائم المهام تتكرر بالطريقة نفسها — يوميًا، أيام العمل، أيام محددة، شهريًا، سنويًا، مع تاريخ انتهاء.'),
    (Icons.place_outlined, 'Events: place and reminder', 'Add a location (opens in Maps) and "Remind us before" in one tap.',
      'المواعيد: المكان والتذكير', 'أضف موقعًا (يفتح في الخرائط) و«ذكّرنا قبلها» بضغطة واحدة.'),
    (Icons.hourglass_bottom_outlined, 'Countdowns on Activities', 'A date can show "N days remaining" on the Activity card. "Remind us" now sends real alerts.',
      'عد تنازلي في الأنشطة', 'يمكن للتاريخ أن يعرض «متبقٍ N يومًا» على بطاقة النشاط. و«ذكّرنا» يرسل تنبيهات حقيقية الآن.'),
    (Icons.link, 'Remind me about anything', 'A reminder can be about a list, event, note, occasion, activity or trip — pick the kind, then the item.',
      'ذكّرني بأي شيء', 'يمكن ربط التذكير بقائمة أو موعد أو ملاحظة أو مناسبة أو نشاط أو رحلة — اختر النوع ثم العنصر.'),
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
