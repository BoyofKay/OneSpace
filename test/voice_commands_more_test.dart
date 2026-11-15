import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/voice_commands.dart';
import 'package:onespace/core/voice_commands_ar.dart';

void main() {
  // Sunday 15 Nov 2026, 10:00.
  final now = DateTime(2026, 11, 15, 10);
  VoiceCommand p(String s) => VoiceCommandRules.parse(s, now);

  group('English, new commands', () {
    test('reading', () {
      expect(p('read the groceries list').action, VoiceAction.readList);
      expect(p('read the groceries list').target, 'groceries');
      expect(p("read Kay's last letter").action, VoiceAction.readLetter);
      expect(p('read the heater activity').target, 'heater');
      expect(p('read our next trip').action, VoiceAction.readTrip);
      expect(p('read our next trip').target, '');
      expect(p('read the Paris trip').target, 'paris');
      final tomorrow = p("what's tomorrow");
      expect(tomorrow.action, VoiceAction.readDay);
      expect(tomorrow.when, DateTime(2026, 11, 16, 9));
      expect(p("what's on this week").target, 'week');
    });
    test('quick actions', () {
      final off = p('check off milk on the groceries list');
      expect(off.action, VoiceAction.checkOff);
      expect(off.title, 'milk');
      expect(off.target, 'groceries');
      expect(p('i bought the eggs').title, 'eggs');
      final done = p('i took my vitamins');
      expect(done.action, VoiceAction.reminderDone);
      expect(done.title, 'vitamins');
      expect(p('mark the rent reminder as done').title, 'rent');
      final sn = p('snooze the vitamins reminder for 2 hours');
      expect(sn.action, VoiceAction.snooze);
      expect(sn.number, 120);
      expect(p('snooze vitamins until tomorrow').number, -1);
      final f = p("I'm feeling great today");
      expect(f.action, VoiceAction.feeling);
      expect(f.number, 5);
      expect(p('i am tired').number, 2);
      expect(p('send Kay a hug').target, 'hug');
      expect(p('send good morning').target, 'morning');
      expect(p('send a hug to Kay').target, 'hug');
    });
    test('questions and stop', () {
      expect(p('how many days until our anniversary').target, 'anniversary');
      expect(p("when's our next trip").action, VoiceAction.nextTrip);
      expect(p('when do we see each other again').action, VoiceAction.nextReunion);
      expect(p("no thanks").action, VoiceAction.stop);
      expect(p("that's all").action, VoiceAction.stop);
    });
    test('matching', () {
      expect(VoiceCommandRules.matchScore('Groceries for the week', 'groceries'), greaterThanOrEqualTo(50));
      expect(VoiceCommandRules.best(['Packing', 'Groceries'], (x) => x, 'grocery list'), isNull);
      expect(VoiceCommandRules.best(['Packing', 'Groceries'], (x) => x, 'groceries'), 'Groceries');
    });
  });

  group('Arabic', () {
    test('normalize keeps length', () {
      const s = 'أضف حليب إلى قائمة المشتريات ٣';
      expect(ArabicVoiceRules.normalize(s).length, s.length);
      expect(ArabicVoiceRules.normalize(s), 'اضف حليب الي قايمه المشتريات 3');
    });
    test('reminder with tomorrow at 5 in the evening', () {
      final c = p('ذكرني أن أتصل بالعيادة بكرة الساعة 5 المساء');
      expect(c.action, VoiceAction.reminder);
      expect(c.lang, 'ar');
      expect(c.title, 'أتصل بالعيادة');
      expect(c.when, DateTime(2026, 11, 16, 17));
    });
    test('reminder in half an hour', () {
      final c = p('ذكرني بالدواء بعد نص ساعة');
      expect(c.title, 'الدواء');
      expect(c.when, DateTime(2026, 11, 15, 10, 30));
    });
    test('lists', () {
      final a = p('أضف حليب إلى قائمة المشتريات');
      expect(a.action, VoiceAction.addToList);
      expect(a.title, 'حليب');
      expect(a.target, 'المشتريات');
      expect(p('اقرأ قائمة المشتريات').action, VoiceAction.readList);
      expect(p('اقرأ قائمة المشتريات').target, 'المشتريات');
      final off = p('اشطب الحليب من قائمة المشتريات');
      expect(off.action, VoiceAction.checkOff);
      expect(off.title, 'الحليب');
      expect(p('اعمل قائمة جديدة باسم السفر').title, 'السفر');
    });
    test('note, event, open, search', () {
      expect(p('اكتب ملاحظة كلمة سر الواي فاي على الراوتر').title, 'كلمة سر الواي فاي على الراوتر');
      final e = p('أضف موعد طبيب الأسنان يوم الخميس الساعة 4 العصر');
      expect(e.action, VoiceAction.event);
      expect(e.title, 'طبيب الأسنان');
      expect(e.when, DateTime(2026, 11, 19, 16));
      expect(p('افتح التقويم').target, 'calendar');
      expect(p('افتح الملاحظات').target, 'notes');
      expect(p('ابحث عن جواز السفر').title, 'جواز السفر');
    });
    test('reading and questions', () {
      expect(p('ماذا لدينا اليوم').action, VoiceAction.readToday);
      expect(p('ايش عندنا بكرة').action, VoiceAction.readDay);
      expect(p('اقرأ تذكيراتي').action, VoiceAction.readReminders);
      expect(p('اقرأ آخر رسالة').action, VoiceAction.readLetter);
      expect(p('متى رحلتنا القادمة').action, VoiceAction.nextTrip);
      expect(p('متى نلتقي').action, VoiceAction.nextReunion);
      final cd = p('كم يوم باقي على عيد ميلادها');
      expect(cd.action, VoiceAction.countdown);
      expect(cd.target, 'عيد ميلادها');
    });
    test('feelings, gestures, done, snooze, stop', () {
      expect(p('أنا تعبان اليوم').number, 2);
      expect(p('حاسة إني مبسوطة').number, 5);
      expect(p('ارسل لها حضن').target, 'hug');
      expect(p('ابعث صباح الخير').target, 'morning');
      expect(p('خلصت الدواء').action, VoiceAction.reminderDone);
      final s = p('أجّل الدواء ساعة');
      expect(s.action, VoiceAction.snooze);
      expect(s.number, 60);
      expect(p('لا شكرا').action, VoiceAction.stop);
    });
  });
}
