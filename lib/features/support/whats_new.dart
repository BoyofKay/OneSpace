import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onespace/l10n/phrases.dart';

/// R65: a short "What's new" sheet, shown once per release after an update.
/// Bump [release] and rewrite [_items] when there is something worth telling.
class WhatsNew {
  const WhatsNew._();
  static const release = 'r67';
  static const _key = 'whats_new_seen_v1';

  static const _items = <(IconData, String, String, String, String)>[
    (Icons.flight_takeoff_outlined, 'Trips, step by step', 'Airports by code, one way or round trip, who is traveling and passengers. The status moves on by itself: Planning, Booked, Traveling, Past.',
      'الرحلات خطوة بخطوة', 'المطارات برموزها، ذهاب فقط أو ذهاب وعودة، من سيسافر وعدد المسافرين. وتتغير الحالة تلقائيًا: تخطيط، محجوزة، في السفر، سابقة.'),
    (Icons.travel_explore, 'Google Flights, filled in', 'Search opens already filled from your trip. Share a flight back to OneSpace and it is read for you.',
      'Google Flights جاهز', 'يفتح البحث مملوءًا من رحلتك. شارك الرحلة الجوية إلى OneSpace وستُقرأ تفاصيلها تلقائيًا.'),
    (Icons.card_giftcard_outlined, 'Occasions and gifts', 'Start from a holiday or special date, a reminder to start preparing, and gifts that move from ideas to reserved to bought.',
      'المناسبات والهدايا', 'ابدأ من عطلة أو تاريخ مميز، مع تذكير لبدء التحضير، وهدايا تنتقل من الأفكار إلى المحجوز إلى المشترى.'),
    (Icons.format_paint_outlined, 'Easier note formatting', 'Big buttons with words: title, heading, bold, highlight, colours, lists and checklists.',
      'تنسيق أسهل للملاحظات', 'أزرار كبيرة بأسمائها: عنوان، عنوان فرعي، عريض، تظليل، ألوان، قوائم وقوائم تحقق.'),
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
