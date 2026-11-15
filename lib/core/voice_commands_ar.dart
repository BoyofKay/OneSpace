import 'voice_commands.dart';

/// R61: Arabic voice commands (Gulf, Levantine, Egyptian and standard
/// phrasings). Matching runs on a normalized copy of the sentence (alef forms,
/// taa marbuta, alef maqsura, Arabic digits) while titles are taken from the
/// original words, so what you said is what gets saved.
class ArabicVoiceRules {
  const ArabicVoiceRules._();

  static final _marks = RegExp('[ً-ْٰـ]');

  /// One-to-one character normalization (keeps positions aligned).
  static String normalize(String s) {
    final b = StringBuffer();
    for (final ch in s.runes) {
      var c = String.fromCharCode(ch);
      switch (c) {
        case 'أ': case 'إ': case 'آ': case 'ٱ': c = 'ا';
        case 'ى': c = 'ي';
        case 'ة': c = 'ه';
        case 'ؤ': c = 'و';
        case 'ئ': c = 'ي';
        case '،': c = ',';
        case '؟': c = '?';
      }
      final d = '٠١٢٣٤٥٦٧٨٩'.indexOf(c);
      if (d >= 0) c = '$d';
      b.write(c);
    }
    return b.toString();
  }

  static RegExp _r(String p) => RegExp(normalize(p));
  static Map<String, T> _norm<T>(Map<String, T> m) => {for (final e in m.entries) normalize(e.key): e.value};
  static final _screens = _norm(screens);
  static final _moods = _norm(moods);
  static final _gestures = _norm(gestures);

  static const screens = <String, String>{
    'اليوم': 'today', 'الرئيسيه': 'today', 'الصفحه الرئيسيه': 'today',
    'التقويم': 'calendar', 'تقويم': 'calendar', 'المواعيد': 'calendar',
    'التذكيرات': 'reminders', 'تذكيرات': 'reminders', 'المنبهات': 'reminders',
    'الملاحظات': 'notes', 'ملاحظات': 'notes',
    'القوائم': 'todo', 'قوائم المهام': 'todo', 'المهام': 'todo', 'قائمه المهام': 'todo',
    'الرحلات': 'trips', 'رحلات': 'trips', 'السفر': 'trips', 'الرحله': 'trips',
    'الذكريات': 'memories', 'ذكريات': 'memories', 'الصور': 'memories',
    'الرسائل': 'letters', 'رسائل': 'letters',
    'الانشطه': 'activities', 'انشطه': 'activities', 'التنسيق': 'activities',
    'المناسبات': 'occasions', 'اعياد الميلاد': 'occasions',
    'جهات الاتصال': 'contacts', 'بطاقات الاتصال': 'contacts',
    'التجارب': 'experiences', 'الافلام': 'experiences', 'قائمه المشاهده': 'experiences',
    'تواصلنا اليومي': 'checkin', 'المشاعر': 'checkin', 'يومياتي': 'checkin',
    'الاعدادات': 'settings', 'الضبط': 'settings', 'البحث': 'search',
    'لمسه حب': 'love', 'الحب': 'love', 'حسابي': 'me', 'ملفي': 'me',
  };

  static const moods = <String, int>{
    'ممتاز': 5, 'ممتازه': 5, 'رائع': 5, 'رائعه': 5, 'سعيد': 5, 'سعيده': 5, 'مبسوط': 5, 'مبسوطه': 5,
    'فرحان': 5, 'فرحانه': 5, 'جيد': 4, 'جيده': 4, 'كويس': 4, 'كويسه': 4, 'تمام': 4, 'بخير': 4,
    'مرتاح': 4, 'مرتاحه': 4, 'منيح': 4, 'منيحه': 4, 'عادي': 3, 'متوسط': 3, 'نص نص': 3,
    'تعبان': 2, 'تعبانه': 2, 'متعب': 2, 'متعبه': 2, 'زعلان': 2, 'زعلانه': 2, 'حزين': 2, 'حزينه': 2,
    'مضغوط': 2, 'مضغوطه': 2, 'قلقان': 2, 'قلقانه': 2, 'وحيد': 2, 'وحيده': 2,
    'سيء': 1, 'سيي': 1, 'سيئ': 1, 'مكتئب': 1, 'مكتئبه': 1, 'تعيس': 1, 'تعيسه': 1,
  };

  static const gestures = <String, String>{
    'حضن': 'hug', 'ضمه': 'hug', 'حضنه': 'hug', 'قبله': 'thinking', 'بوسه': 'thinking',
    'صباح الخير': 'morning', 'مساء الخير': 'thinking', 'تصبح على خير': 'goodnight',
    'تصبحين على خير': 'goodnight', 'احلام سعيده': 'goodnight', 'اشتقت لك': 'miss_you',
    'اشتقتلك': 'miss_you', 'وحشتني': 'miss_you', 'وحشتيني': 'miss_you', 'شكرا': 'thanks',
    'فخور بك': 'proud', 'فخوره بك': 'proud', 'ابتسامه': 'smile', 'افكر فيك': 'thinking',
  };

  static const _days = {'الاثنين': 1, 'الثلاثاء': 2, 'الاربعاء': 3, 'الخميس': 4, 'الجمعه': 5,
    'السبت': 6, 'الاحد': 7};
  static const _num = {'واحده': 1, 'واحد': 1, 'اثنين': 2, 'ثنتين': 2, 'ثلاث': 3, 'ثلاثه': 3,
    'اربع': 4, 'اربعه': 4, 'خمس': 5, 'خمسه': 5, 'ست': 6, 'سته': 6, 'سبع': 7, 'سبعه': 7,
    'ثمان': 8, 'ثمانيه': 8, 'تسع': 9, 'تسعه': 9, 'عشر': 10, 'عشره': 10,
    'احدعش': 11, 'احدي عشر': 11, 'اطنعش': 12, 'اثنا عشر': 12, 'اثني عشر': 12};

  static VoiceCommand parse(String spoken, DateTime now) {
    final heard = spoken.trim();
    var display = heard.replaceAll(_marks, '').replaceAll(_r(r'\s+'), ' ').replaceAll(_r(r'[.!?؟،,]+$'), '').trim();
    var n = normalize(display);
    // Original-spelling text for a matched group.
    String g(RegExpMatch m, int i) {
      final text = m.group(i) ?? '';
      if (text.isEmpty) return '';
      final at = n.indexOf(text, m.start);
      return at < 0 ? text : display.substring(at, at + text.length).trim();
    }
    VoiceCommand c(VoiceAction a, {String title = '', DateTime? when, bool timeGiven = false,
        String target = '', int? number}) =>
      VoiceCommand(a, title: title, when: when, timeGiven: timeGiven, target: target,
        number: number, heard: heard, lang: 'ar');
    if (n.isEmpty) return c(VoiceAction.unknown);
    // Polite openers.
    for (final p in ['لو سمحت ', 'من فضلك ', 'ممكن ', 'يا ون سبيس ', 'ون سبيس ']) {
      if (n.startsWith(p)) { n = n.substring(p.length); display = display.substring(p.length); }
    }

    if (_r(r'^(لا|لا شكرا|شكرا|شكرا لك|خلاص|بس|يكفي|انتهينا|مع السلامه|لا شي|لا شيء|ولا شي|لا ابدا|تمام شكرا)$').hasMatch(n)) {
      return c(VoiceAction.stop);
    }
    if (_r(r'^(مساعده|ساعدني|ماذا (يمكنني|استطيع) ان اقول|(ايش|وش|شو) (اقدر|بقدر) (اقول|احكي)|ماذا اقول)').hasMatch(n)) {
      return c(VoiceAction.help);
    }

    // ---- Reading ----
    var m = _r(r'^(ماذا|ايش|شو|وش|ما|ماهو|ما هو) (لدينا|عندنا|لدي|عندي|برنامجنا|برنامجي|برنامج|جدولنا|جدولي|جدول|في)( .*)?$').firstMatch(n);
    if (m != null && !n.contains('قائمه') && !n.contains('لسته')) {
      final rest = m.group(3) ?? '';
      if (_r(r'(بكره|بكرا|غدا|الغد|باكر)').hasMatch(rest)) {
        return c(VoiceAction.readDay, when: DateTime(now.year, now.month, now.day + 1), target: 'day');
      }
      if (rest.contains('الاسبوع')) return c(VoiceAction.readDay, target: 'week');
      for (final d in _days.entries) {
        if (rest.contains(d.key)) {
          var add = (d.value - now.weekday) % 7;
          if (add == 0) add = 7;
          return c(VoiceAction.readDay, when: DateTime(now.year, now.month, now.day + add), target: 'day');
        }
      }
      return c(VoiceAction.readToday);
    }
    const read = r'^(اقرا|اقري|اقرالي|اقريلي|اسمعني|قل لي|قولي|قللي|قوليلي)( لي)?';
    if (_r('$read (التذكيرات|تذكيراتي|المنبهات|التذكيرات القادمه)').hasMatch(n)) return c(VoiceAction.readReminders);
    if (_r('$read (اخر )?(ملاحظه|الملاحظه|ملاحظاتي|الملاحظات)').hasMatch(n)) return c(VoiceAction.readNotes);
    if (_r('$read (اخر )?(رساله|الرساله|رسالتها|رسالته|الرسائل|رسائلي)').hasMatch(n)) return c(VoiceAction.readLetter);
    m = _r('$read (قائمه|لسته) (.+)\$').firstMatch(n)
      ?? _r(r'^(ماذا|ايش|شو|وش|ما) (في|على) (قائمه|لسته) (.+)$').firstMatch(n);
    if (m != null) return c(VoiceAction.readList, target: g(m, m.groupCount));
    m = _r('$read (نشاط|النشاط) (.+)\$').firstMatch(n);
    if (m != null) return c(VoiceAction.readActivity, target: g(m, 4));
    m = _r('$read (رحله|الرحله|رحلتنا|رحلتنا القادمه|الرحله القادمه)( (.+))?\$').firstMatch(n);
    if (m != null) {
      final which = (m.group(3) ?? '').contains('القادمه') ? '' : g(m, 5);
      return c(VoiceAction.readTrip, target: which.replaceFirst(_r(r'^(الى|ل)\s*'), ''));
    }

    // ---- Questions ----
    if (_r(r'^متي (رحلتنا|سفرتنا|سفرنا|الرحله|سفرنا القادم|رحلتنا القادمه|الرحله القادمه)').hasMatch(n)) {
      return c(VoiceAction.nextTrip);
    }
    if (_r(r'^متي (نلتقي|نتقابل|نشوف بعض|نجتمع|اشوفك|اشوفها|اشوفه|لقاؤنا|لقاونا|لقائنا|لقانا|نكون مع بعض)').hasMatch(n)) {
      return c(VoiceAction.nextReunion);
    }
    m = _r(r'^(كم|قديش|كام) (يوم|يوما|اسبوع)?( ?(باقي|بقي|متبقي|ضل|فاضل))? ?(على|ل|حتى|لين|لحد) ?(.+)$').firstMatch(n);
    if (m != null) return c(VoiceAction.countdown, target: g(m, 6));

    // ---- Quick actions ----
    const send = r'^(ارسل|ابعث|ارسلي|ابعثي|ابعتلها|ابعتله|ارسلها|ارسله)( لها| له| ل\S+)?';
    if (_r('$send (حب|شويه حب|لمسه حب|حبي)\$').hasMatch(n)) return c(VoiceAction.love);
    m = _r('$send (.+?)( لها| له| ل\\S+)?\$').firstMatch(n);
    if (m != null) {
      final kind = _gestures[m.group(3)!.trim()];
      if (kind != null) return c(VoiceAction.gesture, target: kind, title: g(m, 3));
    }
    m = _r(r'^(انا|اشعر|احس|حاسس|حاسه|مزاجي|اليوم انا|انا اليوم|حاسس انا|حاسه انا)( ب| اني| انني)? (.+?)( اليوم| جدا| كثير| مره)*( لان (.+))?$').firstMatch(n);
    if (m != null && _moods.containsKey(m.group(3)!.replaceFirst(_r(r'^(ب|ال)'), ''))) {
      return c(VoiceAction.feeling, number: _moods[m.group(3)!.replaceFirst(_r(r'^(ب|ال)'), '')],
        title: g(m, 6));
    }
    m = _r(r'^(اشطب|علم على|علم|شيل|احذف) (.+?) (من|في|على) (قائمه |لسته )?(.+)$').firstMatch(n);
    if (m != null) return c(VoiceAction.checkOff, title: g(m, 2), target: g(m, 5));
    m = _r(r'^(اشتريت|جبت|حطيت|جهزت|شريت) (ال)?(.+)$').firstMatch(n);
    if (m != null) return c(VoiceAction.checkOff, title: g(m, 3));
    m = _r(r'^(اجل|اخر|اخري|اجلي) (تذكير |التذكير )?(.+?)( (\d+|ساعه|ساعتين|نص ساعه|نصف ساعه|ربع ساعه) ?(دقيقه|دقائق|دقايق|ساعات)?| لبكره| للغد| لبكرا| الي الغد| لبكرة)?$').firstMatch(n);
    if (m != null) {
      var minutes = 30;
      final span = m.group(4) ?? '';
      if (_r(r'(بكره|بكرا|الغد)').hasMatch(span)) {
        minutes = -1;
      } else if (m.group(5) != null) {
        final v = m.group(5)!;
        final digits = int.tryParse(v);
        minutes = digits != null ? ((m.group(6) ?? '').startsWith('س') ? digits * 60 : digits)
          : v == 'ساعه' ? 60 : v == 'ساعتين' ? 120 : v.startsWith('ربع') ? 15 : 30;
      }
      return c(VoiceAction.snooze, title: g(m, 3), number: minutes);
    }
    m = _r(r'^(تم|خلصت|انهيت|انجزت|سويت|اخذت|اتصلت ب|دفعت|عملت) (.+)$').firstMatch(n);
    if (m != null) return c(VoiceAction.reminderDone, title: g(m, 2));

    m = _r(r'^(ابحث|دور|فتش|ابحثي|دوري)( لي)?( عن| على)? (.+)$').firstMatch(n);
    if (m != null) return c(VoiceAction.search, title: g(m, 4));
    m = _r(r'^(افتح|افتحي|روح|روحي|اذهب|اعرض|وريني|ورني|خذني)( على| الى| الي| ل| لصفحه| صفحه)? (.+)$').firstMatch(n);
    if (m != null) {
      final key = _screens[m.group(3)!.trim()];
      if (key != null) return c(VoiceAction.open, target: key);
    }

    // ---- Creating ----
    m = _r(r'^(ذكرني|ذكريني|نبهني|نبهيني|فكرني|فكريني)( ان| ب| بان| اني)? (.+)$').firstMatch(n);
    if (m != null) {
      final w = _when(g(m, 3), now);
      return c(VoiceAction.reminder, title: w.rest, when: w.when, timeGiven: w.timeGiven);
    }
    m = _r(r'^(اضف|اضيف|ضيف|ضيفي|حط|حطي|ضع|زيد) (.+?) (الي|في|على|ل) ?(قائمه|لسته) (.+)$').firstMatch(n);
    if (m != null) return c(VoiceAction.addToList, title: g(m, 2), target: g(m, 5));
    m = _r(r'^(انشئ|اعمل|اعملي|سو|سوي|ابدا|جهز)( لي)? (قائمه|لسته)( جديده)?( باسم| اسمها| عن| ل| لل)? ?(.+)$').firstMatch(n);
    if (m != null) return c(VoiceAction.newList, title: g(m, 6));
    m = _r(r'^(اكتب|سجل|دون|اضف|احفظ|اكتبي|سجلي)( لي)? (ملاحظه)( ان| عن| بان)?:? (.+)$').firstMatch(n)
      ?? _r(r'^(ملاحظه):? (.+)$').firstMatch(n);
    if (m != null) return c(VoiceAction.note, title: g(m, m.groupCount));
    m = _r(r'^(اضف|سجل|انشئ|حط|ضع|احجز|سجلي|ضيف)( لي)? (موعد|حدث|مناسبه|اجتماع|عشاء|غداء|مكالمه)( مع| عن| ل)? ?(.+)$').firstMatch(n);
    if (m != null) {
      final kind = m.group(3)!;
      final w = _when(g(m, 5), now);
      final food = kind == 'عشاء' || kind == 'غداء' || kind == 'مكالمه';
      final title = food ? '${g(m, 3)}${(m.group(4) ?? '').isEmpty ? ' ' : ' ${g(m, 4)} '}${w.rest}'.trim() : w.rest;
      return c(VoiceAction.event, title: title, when: w.when ?? now, timeGiven: w.timeGiven);
    }

    return VoiceCommand(VoiceAction.unknown, title: display, heard: heard, lang: 'ar');
  }

  /// Day/time words out of [text] (original spelling kept for the rest).
  static ({String rest, DateTime? when, bool timeGiven}) whenOf(String text, DateTime now) => _when(text, now);

  static ({String rest, DateTime? when, bool timeGiven}) _when(String text, DateTime now) {
    var disp = ' ${text.trim()} ';
    var norm = normalize(disp);
    void cut(RegExpMatch m) {
      disp = '${disp.substring(0, m.start)} ${disp.substring(m.end)}';
      norm = '${norm.substring(0, m.start)} ${norm.substring(m.end)}';
    }
    final today = DateTime(now.year, now.month, now.day);
    DateTime? day;
    int? hour, minute;
    var pm = false, am = false;

    final rel = _r(r' بعد (\d+|ساعه|ساعتين|نص ساعه|نصف ساعه|ربع ساعه|دقيقه|دقيقتين)( (دقيقه|دقائق|دقايق|ساعه|ساعات))? ').firstMatch(norm);
    if (rel != null && !_r(r' بعد (بكره|بكرا|غد)').hasMatch(norm)) {
      final v = rel.group(1)!;
      final digits = int.tryParse(v);
      final minutes = digits != null ? ((rel.group(3) ?? '').startsWith('س') ? digits * 60 : digits)
        : v == 'ساعه' ? 60 : v == 'ساعتين' ? 120 : v.startsWith('ربع') ? 15 : v == 'دقيقه' ? 1 : v == 'دقيقتين' ? 2 : 30;
      cut(rel);
      return (rest: _tidy(disp), when: now.add(Duration(minutes: minutes)), timeGiven: true);
    }
    RegExpMatch? m = _r(r' بعد (بكره|بكرا|غد) ').firstMatch(norm);
    if (m != null) { day = today.add(const Duration(days: 2)); cut(m); }
    m = day == null ? _r(r' (غدا|بكره|بكرا|الغد|باكر) ').firstMatch(norm) : null;
    if (m != null) { day = today.add(const Duration(days: 1)); cut(m); }
    m = day == null ? _r(r' (اليوم) ').firstMatch(norm) : null;
    if (m != null) { day = today; cut(m); }
    m = _r(r' (الليله|هالليله) ').firstMatch(norm);
    if (m != null) { day ??= today; hour = 20; minute = 0; cut(m); }
    if (day == null) {
      m = _r(r' (يوم )?(الاثنين|الثلاثاء|الاربعاء|الخميس|الجمعه|السبت|الاحد)( الجاي| القادم)? ').firstMatch(norm);
      if (m != null) {
        var add = (_days[m.group(2)!]! - now.weekday) % 7;
        if (add == 0) add = 7;
        day = today.add(Duration(days: add));
        cut(m);
      }
    }
    m = _r(r' (الصبح|الصباح|صباحا|في الصباح|بالصباح) ').firstMatch(norm);
    if (m != null) { am = true; hour ??= 9; cut(m); }
    m = _r(r' (الظهر|الظهيره) ').firstMatch(norm);
    if (m != null) { hour ??= 12; cut(m); }
    m = _r(r' (العصر) ').firstMatch(norm);
    if (m != null) { pm = true; hour ??= 16; cut(m); }
    m = _r(r' (المغرب) ').firstMatch(norm);
    if (m != null) { pm = true; hour ??= 18; cut(m); }
    m = _r(r' (المساء|مساء|مساءا|بالليل|في المساء) ').firstMatch(norm);
    if (m != null) { pm = true; hour ??= 19; cut(m); }

    m = _r(r' (علي |في )?(الساعه|ساعه) (\d{1,2}|[^\s]+)(:(\d{2}))?( (و ?نص|و ?ربع|الا ربع|ونص|وربع))? ').firstMatch(norm);
    if (m != null) {
      final raw = m.group(3)!;
      var h = int.tryParse(raw) ?? _num[raw];
      if (h != null && h <= 23) {
        var mi = int.tryParse(m.group(5) ?? '') ?? 0;
        final frac = m.group(7) ?? '';
        if (frac.contains('نص')) mi = 30;
        if (frac.contains('ربع')) mi = frac.contains('الا') ? 45 : 15;
        if (frac.contains('الا')) h = h - 1;
        if (pm && h < 12) h += 12;
        if (!pm && !am && h >= 1 && h <= 7) h += 12;
        hour = h; minute = mi;
        cut(m);
      }
    } else if (hour != null && pm && hour < 12) {
      hour += 12;
    }

    if (day == null && hour == null) return (rest: _tidy(disp), when: null, timeGiven: false);
    final base = day ?? today;
    var at = DateTime(base.year, base.month, base.day, hour ?? 9, minute ?? 0);
    if (day == null && at.isBefore(now)) at = at.add(const Duration(days: 1));
    return (rest: _tidy(disp), when: at, timeGiven: hour != null);
  }

  static String _tidy(String s) => s.replaceAll(_r(r'\s+'), ' ').trim()
      .replaceFirst(_r(r'^(ان|بان|ب)\s+'), '')
      .replaceFirst(RegExp(r'^ب(?=ال)'), '')
      .replaceFirst(_r(r'\s+(في|على|يوم)$'), '').trim();
}
