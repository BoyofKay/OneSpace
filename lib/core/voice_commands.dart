import 'voice_commands_ar.dart';

/// R60–R61: what a spoken sentence asks OneSpace to do. Pure and tested; the
/// assistant (voice_assistant.dart) turns a command into an action and a
/// spoken reply.
///
/// Creating things opens the item's own page pre-filled (nothing is saved
/// until Save). Quick, reversible actions happen right away and are confirmed
/// out loud: adding to or checking off a list, marking a reminder done or
/// snoozing it, recording how you feel, sending a gesture.
enum VoiceAction {
  reminder, note, event, newList, addToList, open, search, love, help,
  readToday, readDay, readReminders, readNotes, readList, readLetter, readActivity, readTrip,
  checkOff, reminderDone, snooze, feeling, gesture, countdown, nextTrip, nextReunion,
  stop, unknown,
}

class VoiceCommand {
  const VoiceCommand(this.action, {this.title = '', this.when, this.timeGiven = false,
    this.target = '', this.heard = '', this.number, this.lang = 'en'});
  final VoiceAction action;
  final String title;
  final DateTime? when;
  /// The sentence named a clock time (not just a day).
  final bool timeGiven;
  /// Screen key for open, list name for list actions, gesture kind, etc.
  final String target;
  final String heard;
  /// Mood 1–5 for feeling; minutes for snooze (-1 = until tomorrow morning).
  final int? number;
  /// 'en' or 'ar' — the language the person spoke (replies follow it).
  final String lang;

  VoiceCommand copyWith({VoiceAction? action, String? title, DateTime? when}) => VoiceCommand(
    action ?? this.action, title: title ?? this.title, when: when ?? this.when, timeGiven: timeGiven,
    target: target, heard: heard, number: number, lang: lang);

  @override
  String toString() => '$action|$title|$when|$timeGiven|$target|$number|$lang';
}

class VoiceCommandRules {
  const VoiceCommandRules._();

  /// Screens that "open …" understands, by spoken name.
  static const screens = <String, String>{
    'today': 'today', 'home': 'today',
    'calendar': 'calendar', 'events': 'calendar', 'schedule': 'calendar',
    'reminders': 'reminders', 'reminder': 'reminders',
    'notes': 'notes', 'note': 'notes',
    'to do': 'todo', 'to-do': 'todo', 'todo': 'todo', 'to dos': 'todo', 'to-dos': 'todo',
    'lists': 'todo', 'to do lists': 'todo', 'to-do lists': 'todo', 'todo lists': 'todo', 'checklists': 'todo',
    'trips': 'trips', 'trip': 'trips', 'travel': 'trips', 'flights': 'trips',
    'memories': 'memories', 'memory': 'memories', 'photos': 'memories',
    'letters': 'letters', 'letter': 'letters',
    'activities': 'activities', 'activity': 'activities', 'coordinate': 'activities',
    'occasions': 'occasions', 'birthdays': 'occasions',
    'contacts': 'contacts', 'contact cards': 'contacts',
    'experiences': 'experiences', 'watchlist': 'experiences', 'movies': 'experiences',
    'check in': 'checkin', 'check-in': 'checkin', 'daily connection': 'checkin', 'feelings': 'checkin',
    'settings': 'settings', 'search': 'search', 'items to sort': 'sort',
    'a little love': 'love', 'love': 'love', 'gestures': 'love',
    'profile': 'me', 'me': 'me',
  };

  /// Spoken mood words → 1 (very low) … 5 (great).
  static const moods = <String, int>{
    'great': 5, 'amazing': 5, 'wonderful': 5, 'fantastic': 5, 'happy': 5, 'excellent': 5,
    'good': 4, 'fine': 4, 'well': 4, 'alright': 3, 'okay': 3, 'ok': 3, 'meh': 3, 'so so': 3,
    'tired': 2, 'low': 2, 'sad': 2, 'stressed': 2, 'down': 2, 'anxious': 2, 'lonely': 2,
    'bad': 1, 'awful': 1, 'terrible': 1, 'horrible': 1,
  };

  /// Spoken gesture → gesture kind (A little love).
  static const gestures = <String, String>{
    'hug': 'hug', 'kiss': 'thinking', 'heart': 'thinking', 'love': 'thinking',
    'thinking of you': 'thinking', 'i miss you': 'miss_you', 'miss you': 'miss_you',
    'smile': 'smile', 'good morning': 'morning', 'good night': 'goodnight',
    'goodnight': 'goodnight', 'sweet dreams': 'goodnight', 'thank you': 'thanks', 'thanks': 'thanks',
    "i'm proud of you": 'proud', 'proud of you': 'proud', 'you got this': 'support',
  };

  static bool isArabic(String s) => RegExp(r'[؀-ۿ]').hasMatch(s);

  static VoiceCommand parse(String spoken, DateTime now) {
    if (isArabic(spoken)) return ArabicVoiceRules.parse(spoken, now);
    final heard = spoken.trim();
    var t = heard.toLowerCase().replaceAll(RegExp(r'[.!?,;]+$'), '').replaceAll('’', "'")
        .replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceFirst(RegExp(r'^(hey onespace|ok onespace|onespace|please|can you|could you)\s*,?\s*'), '');
    t = t.replaceFirst(RegExp(r'\s*please$'), '');
    VoiceCommand c(VoiceAction a, {String title = '', DateTime? when, bool timeGiven = false,
        String target = '', int? number}) =>
      VoiceCommand(a, title: title, when: when, timeGiven: timeGiven, target: target,
        number: number, heard: heard);
    if (t.isEmpty) return c(VoiceAction.unknown);

    if (RegExp(r"^(no|nope|nothing|stop|cancel|bye|goodbye|done|that'?s (all|it)|that is all|no thanks?( you)?|thanks?( you)?|i'?m good|all good)( thanks?( you)?)?$")
        .hasMatch(t)) {
      return c(VoiceAction.stop);
    }
    if (RegExp(r'^(help|what can (i|you) (say|do)|what do you understand)').hasMatch(t)) return c(VoiceAction.help);

    // ---- Reading ----
    if (RegExp(r"^(what'?s|what is) (on )?(for )?today|^(read|tell me) (me )?(my |our )?(day|today)|^my day|^what do (i|we) have today|^what'?s (my|our) day")
        .hasMatch(t)) {
      return c(VoiceAction.readToday);
    }
    var m = RegExp(r"^(what'?s|what is|what do (i|we) have)( on)? (tomorrow|this week|on (monday|tuesday|wednesday|thursday|friday|saturday|sunday)|(monday|tuesday|wednesday|thursday|friday|saturday|sunday))$")
        .firstMatch(t);
    if (m != null) {
      final day = m.group(4)!;
      if (day == 'this week') return c(VoiceAction.readDay, target: 'week');
      return c(VoiceAction.readDay, when: _when(' ${day.replaceFirst('on ', '')} ', now).when, target: 'day');
    }
    if (RegExp(r'^(read|tell me|what are) (me )?(my |our |the )?(upcoming |next )?reminders').hasMatch(t)) {
      return c(VoiceAction.readReminders);
    }
    if (RegExp(r'^(read|tell me) (me )?(my |our |the )?(latest |last |newest )?notes?$').hasMatch(t)) {
      return c(VoiceAction.readNotes);
    }
    if (RegExp(r"^(read|open) (me )?([a-z]+'s |my partner's |my |the |our )?(last |latest |newest )?letters?$").hasMatch(t)) {
      return c(VoiceAction.readLetter);
    }
    m = RegExp(r"^(read|what'?s on|what is on|tell me) (me )?(the |my |our )?(.+?) list$").firstMatch(t);
    if (m != null) return c(VoiceAction.readList, target: _clean(m.group(4)!));
    m = RegExp(r'^(read|tell me about) (me )?(the |our |my )?(.+?) activity$').firstMatch(t);
    if (m != null) return c(VoiceAction.readActivity, target: _clean(m.group(4)!));
    m = RegExp(r'^(read|tell me about) (me )?(the |our |my )?(next )?(.*?) ?trip$').firstMatch(t);
    if (m != null) return c(VoiceAction.readTrip, target: m.group(4) != null ? '' : _clean(m.group(5)!));

    // ---- Questions ----
    if (RegExp(r"^when('?s| is) (our |the |my )?next (trip|vacation|holiday|flight|journey)").hasMatch(t)) {
      return c(VoiceAction.nextTrip);
    }
    if (RegExp(r"^when (do|will|are) we (see each other|meet|be together|together)|^when('?s| is) (our |the )?next (reunion|visit|meet ?up)")
        .hasMatch(t)) {
      return c(VoiceAction.nextReunion);
    }
    m = RegExp(r"^how (many|long) (days |weeks )?(is it |are there |left )?(until|till|to|before) (our |my |the )?(.+)$")
        .firstMatch(t);
    if (m != null) return c(VoiceAction.countdown, target: _clean(m.group(6)!));

    // ---- Quick actions ----
    if (RegExp(r'^(send (a )?(little )?love|send (a )?gesture|love my)$').hasMatch(t)) return c(VoiceAction.love);
    if (t.startsWith('send ')) {
      var rest = t.substring(5).replaceFirst(RegExp(r' to \w+$'), '').trim();
      final tries = <String>[rest, rest.replaceFirst(RegExp(r'^\S+ '), '')];
      for (final x in tries) {
        final phrase = x.replaceFirst(RegExp(r'^(a|an|her|him) '), '');
        final kind = gestures[phrase];
        if (kind != null) return c(VoiceAction.gesture, target: kind, title: phrase);
      }
    }
    m = RegExp(r"^(i'?m feeling|i am feeling|today i feel|i feel|i'?m doing|i am|i'?m|feeling)( really| very| pretty| so| a bit| quite| kind of| a little)? ([a-z ]+?)( today)?(,? because (.+))?$")
        .firstMatch(t);
    if (m != null && moods.containsKey(m.group(3))) {
      return c(VoiceAction.feeling, number: moods[m.group(3)], title: _cap(m.group(6) ?? ''));
    }
    m = RegExp(r'^(check off|tick off|cross off|check|tick|mark) (.+?) (on|off|from|in) (the |my |our )?(.+?)( list)?( as done)?$')
        .firstMatch(t);
    if (m != null && !m.group(2)!.contains('reminder')) {
      return c(VoiceAction.checkOff, title: _clean(m.group(2)!), target: _clean(m.group(5)!));
    }
    m = RegExp(r'^i (bought|got|picked up|grabbed|packed) (.+)$').firstMatch(t);
    if (m != null) return c(VoiceAction.checkOff, title: _clean(m.group(2)!));
    m = RegExp(r'^snooze (the |my )?(.+?)( reminder)?( for (\d+|an|a|half an|one|two|three) (minutes?|mins?|hours?)| until tomorrow| till tomorrow| to tomorrow)?$')
        .firstMatch(t);
    if (m != null) {
      var minutes = 30;
      if ((m.group(4) ?? '').contains('tomorrow')) {
        minutes = -1;
      } else if (m.group(5) != null) {
        final raw = m.group(5)!;
        final n = int.tryParse(raw) ?? _numbers[raw] ?? 1;
        minutes = raw == 'half an' ? 30 : (m.group(6)!.startsWith('h') ? n * 60 : n);
      }
      return c(VoiceAction.snooze, title: _clean(m.group(2)!), number: minutes);
    }
    m = RegExp(r'^(mark|set) (the |my )?(.+?) reminder (as )?(done|complete|completed|finished)$').firstMatch(t);
    if (m != null) return c(VoiceAction.reminderDone, title: _clean(m.group(3)!));
    m = RegExp(r'^i (took|did|called|paid|finished|completed|sent|watered|fed|walked|cleaned) (my |the )?(.+)$').firstMatch(t);
    if (m != null) return c(VoiceAction.reminderDone, title: _clean(m.group(3)!));
    m = RegExp(r'^(done with|finished) (my |the )?(.+)$').firstMatch(t);
    if (m != null) return c(VoiceAction.reminderDone, title: _clean(m.group(3)!));

    m = RegExp(r'^(search( for)?|find|look for|look up) (.+)$').firstMatch(t);
    if (m != null) return c(VoiceAction.search, title: _clean(m.group(3)!));

    m = RegExp(r'^(open|go to|show( me)?|take me to) (the |my |our )?(.+)$').firstMatch(t);
    if (m != null) {
      final name = m.group(4)!.replaceFirst(RegExp(r'\s+(page|screen|tab)$'), '').trim();
      final key = screens[name];
      if (key != null) return c(VoiceAction.open, target: key);
    }

    // ---- Creating ----
    m = RegExp(r'^(remind me( to| about| that)?|set a reminder( to| for)?|reminder( to)?) (.+)$').firstMatch(t);
    if (m != null) {
      final parsed = _when(m.group(5)!, now);
      return c(VoiceAction.reminder, title: _cap(parsed.rest), when: parsed.when, timeGiven: parsed.timeGiven);
    }
    m = RegExp(r'^(add|put) (.+?) (to|on|in) (the |my |our )?(.+?) list$').firstMatch(t);
    if (m != null) return c(VoiceAction.addToList, title: _cap(_clean(m.group(2)!)), target: _clean(m.group(5)!));
    m = RegExp(r'^(new|create|start|make)( a)? (new )?(to-?do |to do )?list( called| named| for)? (.+)$').firstMatch(t);
    if (m != null) return c(VoiceAction.newList, title: _cap(_clean(m.group(6)!)));
    m = RegExp(r'^(take|add|write|make|new|save)( a| an)? note( that| about| saying)?:? (.+)$').firstMatch(t)
      ?? RegExp(r'^note:? (.+)$').firstMatch(t);
    if (m != null) return c(VoiceAction.note, title: _cap(_clean(m.group(m.groupCount)!)));
    m = RegExp(r'^(add|create|new|schedule|put|plan|book)( an| a)? (event|appointment|meeting|date|dinner|lunch|call)?( called| for)?:? ?(.+?)( (to|on|in) (the |my |our )?calendar)?$')
        .firstMatch(t);
    if (m != null && (m.group(3) != null || t.startsWith('schedule') || m.group(6) != null)) {
      final kind = m.group(3);
      final what = kind == 'dinner' || kind == 'lunch' || kind == 'call' ? '$kind ${m.group(5)}' : m.group(5)!;
      final parsed = _when(what, now);
      return c(VoiceAction.event, title: _cap(parsed.rest), when: parsed.when ?? now, timeGiven: parsed.timeGiven);
    }

    return VoiceCommand(VoiceAction.unknown, title: _cap(heard), heard: heard);
  }

  static String _clean(String s) => s.trim().replaceFirst(RegExp(r'^(to |that |about |the |my |our )'), '').trim();
  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static const _days = {'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4,
    'friday': 5, 'saturday': 6, 'sunday': 7};
  static const _numbers = {'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
    'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12,
    'fifteen': 15, 'twenty': 20, 'thirty': 30, 'forty five': 45, 'a': 1, 'an': 1, 'half an': 30};

  static ({String rest, DateTime? when, bool timeGiven}) _when(String text, DateTime now) {
    var rest = ' $text ';
    DateTime? day;
    int? hour, minute;

    final rel = RegExp(r' in (\d+|[a-z]+(?: [a-z]+)?) (minute|minutes|min|mins|hour|hours) ').firstMatch(rest);
    if (rel != null) {
      final raw = rel.group(1)!;
      final n = int.tryParse(raw) ?? _numbers[raw];
      if (n != null) {
        final unit = rel.group(2)!.startsWith('h') ? Duration(hours: n) : Duration(minutes: raw == 'half an' ? 30 : n);
        rest = rest.replaceFirst(rel.group(0)!, ' ');
        return (rest: _tidy(rest), when: now.add(unit), timeGiven: true);
      }
    }

    final today = DateTime(now.year, now.month, now.day);
    if (RegExp(r' (tomorrow|tmrw) ').hasMatch(rest)) {
      day = today.add(const Duration(days: 1));
      rest = rest.replaceFirst(RegExp(r' (tomorrow|tmrw) '), ' ');
    } else if (RegExp(r' (today|tonight|this evening|this morning|this afternoon) ').hasMatch(rest)) {
      final w = RegExp(r' (today|tonight|this evening|this morning|this afternoon) ').firstMatch(rest)!.group(1)!;
      day = today;
      if (w == 'tonight' || w == 'this evening') hour = 20;
      if (w == 'this morning') hour = 9;
      if (w == 'this afternoon') hour = 15;
      rest = rest.replaceFirst(' $w ', ' ');
    } else {
      final d = RegExp(r' (on |next |this )?(monday|tuesday|wednesday|thursday|friday|saturday|sunday) ').firstMatch(rest);
      if (d != null) {
        var add = (_days[d.group(2)!]! - now.weekday) % 7;
        if (add == 0) add = 7;
        day = today.add(Duration(days: add));
        rest = rest.replaceFirst(d.group(0)!, ' ');
      }
    }

    final clock = RegExp(r' (at |by |around )?(\d{1,2})(?::(\d{2}))? ?(am|pm|a\.m\.|p\.m\.|o.?clock)? ').allMatches(rest)
        .where((x) => x.group(1) != null || x.group(4) != null).firstOrNull;
    if (clock != null) {
      var h = int.parse(clock.group(2)!);
      final mi = int.tryParse(clock.group(3) ?? '') ?? 0;
      final ap = clock.group(4) ?? '';
      if (ap.startsWith('p') && h < 12) h += 12;
      if (ap.startsWith('a') && h == 12) h = 0;
      if (ap.isEmpty && h >= 1 && h <= 7) h += 12;
      if (h <= 23 && mi <= 59) {
        hour = h; minute = mi;
        rest = rest.replaceFirst(clock.group(0)!, ' ');
      }
    } else if (RegExp(r' (at )?(noon|midday) ').hasMatch(rest)) {
      hour = 12; minute = 0;
      rest = rest.replaceFirst(RegExp(r' (at )?(noon|midday) '), ' ');
    } else if (RegExp(r' in the (morning|afternoon|evening) ').hasMatch(rest)) {
      final p = RegExp(r' in the (morning|afternoon|evening) ').firstMatch(rest)!;
      hour = {'morning': 9, 'afternoon': 15, 'evening': 19}[p.group(1)!];
      minute = 0;
      rest = rest.replaceFirst(p.group(0)!, ' ');
    }

    if (day == null && hour == null) return (rest: _tidy(rest), when: null, timeGiven: false);
    final base = day ?? today;
    var at = DateTime(base.year, base.month, base.day, hour ?? 9, minute ?? 0);
    if (day == null && at.isBefore(now)) at = at.add(const Duration(days: 1));
    return (rest: _tidy(rest), when: at, timeGiven: hour != null);
  }

  static String _tidy(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim()
      .replaceFirst(RegExp(r'^(to |that |about |for )'), '')
      .replaceFirst(RegExp(r' (at|on|by)$'), '').trim();

  /// "A, B, and C." for speech ([and] / [sep] change for Arabic).
  static String joinForSpeech(List<String> parts,
      {String empty = 'Nothing planned.', String and = 'and', String sep = ', '}) {
    final p = parts.where((x) => x.trim().isNotEmpty).toList();
    if (p.isEmpty) return empty;
    if (p.length == 1) return '${p.first}.';
    return '${p.sublist(0, p.length - 1).join(sep)}$sep$and ${p.last}.';
  }

  /// Loose title match used to find a list, reminder, item or activity by
  /// what was said ("groceries" finds "Groceries for the week").
  static int matchScore(String candidate, String spoken) {
    final a = normalize(candidate), b = normalize(spoken);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 100;
    if (a.contains(b) || b.contains(a)) return 80;
    final aw = a.split(' ').where((w) => w.length > 2).toSet();
    final bw = b.split(' ').where((w) => w.length > 2).toSet();
    if (aw.isEmpty || bw.isEmpty) return 0;
    final common = aw.intersection(bw).length;
    return common == 0 ? 0 : (60 * common / bw.length).round();
  }

  static String normalize(String s) => ArabicVoiceRules.normalize(s.toLowerCase())
      .replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), ' ')
      .replaceAll(RegExp(r'\b(the|a|an|my|our|list)\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Picks the best match (score ≥ 50) or null.
  static T? best<T>(Iterable<T> items, String Function(T) title, String spoken) {
    T? top;
    var score = 0;
    for (final i in items) {
      final s = matchScore(title(i), spoken);
      if (s > score) { score = s; top = i; }
    }
    return score >= 50 ? top : null;
  }
}
