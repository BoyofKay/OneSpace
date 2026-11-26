import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onespace/l10n/phrases.dart';

/// R65: a short "What's new" sheet, shown once per release after an update.
/// Bump [release] and rewrite [_items] when there is something worth telling.
class WhatsNew {
  const WhatsNew._();
  static const release = 'r74';
  static const _key = 'whats_new_seen_v1';

  static const _items = <(IconData, String, String, String, String)>[
    (Icons.event_available_outlined, 'In your phone calendar', 'Turn on Me › Settings › Show in my phone calendar to see your events, trips and special dates in Google, Samsung or iPhone calendar.',
      'في تقويم هاتفك', 'فعّل «أنا» ← «الإعدادات» ← «عرض في تقويم هاتفي» لترى مواعيدكما ورحلاتكما وتواريخكما المميزة في تقويم Google أو Samsung أو iPhone.'),
    (Icons.support_agent_outlined, 'Help, even when signed out', 'Questions and answers, Contact us and Report a problem are now on the sign-in screen too.',
      'مساعدة حتى دون تسجيل الدخول', 'الأسئلة والأجوبة و«تواصل معنا» و«الإبلاغ عن مشكلة» موجودة الآن في شاشة الدخول أيضًا.'),
    (Icons.forum_outlined, 'Talk about experiences', 'Each movie, show or book has a real conversation now — reply to a message, mention your partner — and your ratings show on the card. Tap a pick again to clear it.',
      'تحدّثا عن التجارب', 'لكل فيلم أو مسلسل أو كتاب محادثة حقيقية الآن — ردّ على رسالة وأشِر إلى شريكك — وتظهر تقييماتكما على البطاقة. اضغط على اختيارك مرة أخرى لإلغائه.'),
    (Icons.qr_code_2_outlined, 'Invite with a QR code', 'Your partner can scan the invitation from your phone. Reports of a technical issue can include a screenshot.',
      'دعوة برمز QR', 'يمكن لشريكك مسح الدعوة من هاتفك. ويمكن إرفاق لقطة شاشة عند الإبلاغ عن مشكلة تقنية.'),
    (Icons.bolt_outlined, 'Quicker everyday forms', 'Days off as a range, platform chips for movies and music, Daily feeling and Letter in Quick add, and send the partner invitation by WhatsApp, SMS or email.',
      'نماذج أسرع', 'الإجازات كفترة، اختيارات جاهزة للمنصات، شعور اليوم والرسالة في الإضافة السريعة، وإرسال دعوة الشريك عبر واتساب أو رسالة أو بريد.'),
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
      return SafeArea(child: SingleChildScrollView(child:Padding(
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
      )));
    });
  }
}
