/// R60: what a spoken sentence asks OneSpace to do. Pure and tested; the
/// runner (voice_assistant.dart) turns a command into navigation or speech.
///
/// Creating things always opens the item's own page pre-filled, so nothing is
/// saved until the person taps Save — except adding an item to an existing
/// to-do list, which is instant and can be undone.
enum VoiceAction {
  reminder, note, event, newList, addToList, open, readToday, readReminders,
  readNotes, love, search, help, unknown,
}

class VoiceCommand {
  const VoiceCommand(this.action, {this.title = '', this.when, this.timeGiven = false,
    this.target = '', this.heard = ''});
  final VoiceAction action;
  final String title;
  final DateTime? when;
  /// The sentence named a clock time (not just a day).
  final bool timeGiven;
  /// Screen name for [VoiceAction.open], list name for [VoiceAction.addToList].
  final String target;
  final String heard;

  @override
  String toString() => '$action|$title|$when|$timeGiven|$target';
}

class VoiceCommandRules {
  const VoiceCommandRules._();

  /// Screens that "open …" / "go to …" understands, by spoken name.
  static const screens = <String, String>{
    'today': 'today', 'home': 'today',
    'calendar': 'calendar', 'events': 'calendar', 'schedule': 'calendar',
    'reminders': 'reminders', 'reminder': 'reminders',
    'notes': 'notes', 'note': 'notes',
    'to do': 'todo', 'to-do': 'todo', 'todo': 'todo', 'to dos': 'todo', 'to-dos': 'todo',
    'lists': 'todo', 'to do lists': 'todo', 'to-do lists': 'todo', 'todo lists': 'todo', 'checklists': 'todo',
    'trips': 'trips', 'trip': 'trips', 'travel': 'trips',
    'memories': 'memories', 'memory': 'memories', 'photos': 'memories',
    'letters': 'letters', 'letter': 'letters',
    'activities': 'activities', 'activity': 'activities', 'coordinate': 'activities',
    'occasions': 'occasions', 'birthdays': 'occasions',
    'contacts': 'contacts', 'contact cards': 'contacts',
    'experiences': 'experiences', 'watchlist': 'experiences', 'movies': 'experiences',
    'check in': 'checkin', 'check-in': 'checkin', 'daily connection': 'checkin', 'feelings': 'checkin',
    'settings': 'settings', 'search': 'search', 'items to sort': 'sort',
    'a little love': 'love', 'love': 'love', 'gestures': 'love',
  };

  static VoiceCommand parse(String spoken, DateTime now) {
    final heard = spoken.trim();
    var t = heard.toLowerCase().replaceAll(RegExp(r'[.!?,]+$'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceFirst(RegExp(r'^(hey onespace|ok onespace|onespace|please)\s*,?\s*'), '');
    t = t.replaceFirst(RegExp(r'\s*please$'), '');
    if (t.isEmpty) return VoiceCommand(VoiceAction.unknown, heard: heard);

    if (RegExp(r'^(help|what can (i|you) (say|do))').hasMatch(t)) {
      return VoiceCommand(VoiceAction.help, heard: heard);
    }
    if (RegExp(r"^(what'?s|what is) (on )?(for )?today|^(read|tell me) (my )?today|^my day|^what do (i|we) have today")
        .hasMatch(t)) {
      return VoiceCommand(VoiceAction.readToday, heard: heard);
    }
    if (RegExp(r'^(read|tell me|what are) (me )?(my |our )?reminders').hasMatch(t)) {
      return VoiceCommand(VoiceAction.readReminders, heard: heard);
    }
    if (RegExp(r'^(read|tell me) (me )?(my |our )?(latest |last )?notes?').hasMatch(t)) {
      return VoiceCommand(VoiceAction.readNotes, heard: heard);
    }
    if (RegExp(r'^(send (a )?(little )?love|send (a )?gesture|love my)').hasMatch(t)) {
      return VoiceCommand(VoiceAction.love, heard: heard);
    }

    var m = RegExp(r'^(search( for)?|find|look for) (.+)$').firstMatch(t);
    if (m != null) return VoiceCommand(VoiceAction.search, title: _clean(m.group(3)!), heard: heard);

    m = RegExp(r'^(open|go to|show( me)?|take me to) (the |my |our )?(.+)$').firstMatch(t);
    if (m != null) {
      final name = m.group(4)!.replaceFirst(RegExp(r'\s+(page|screen|tab)$'), '').trim();
      final key = screens[name];
      if (key != null) return VoiceCommand(VoiceAction.open, target: key, heard: heard);
    }

    m = RegExp(r'^(remind me( to| about| that)?|set a reminder( to| for)?|reminder( to)?) (.+)$').firstMatch(t);
    if (m != null) {
      final parsed = _when(m.group(5)!, now);
      return VoiceCommand(VoiceAction.reminder, title: _cap(parsed.rest), when: parsed.when,
        timeGiven: parsed.timeGiven, heard: heard);
    }

    m = RegExp(r'^(add|put) (.+?) (to|on) (the |my |our )?(.+?) list$').firstMatch(t);
    if (m != null) {
      return VoiceCommand(VoiceAction.addToList, title: _cap(_clean(m.group(2)!)),
        target: _clean(m.group(5)!), heard: heard);
    }
    m = RegExp(r'^(new|create|start|make)( a)? (to-?do |to do )?list( called| named| for)? (.+)$').firstMatch(t);
    if (m != null) return VoiceCommand(VoiceAction.newList, title: _cap(_clean(m.group(5)!)), heard: heard);

    m = RegExp(r'^(take|add|write|make|new)( a)? note( that| about| saying)?:? (.+)$').firstMatch(t)
      ?? RegExp(r'^note:? (.+)$').firstMatch(t);
    if (m != null) {
      final body = _clean(m.group(m.groupCount)!);
      return VoiceCommand(VoiceAction.note, title: _cap(body), heard: heard);
    }

    m = RegExp(r'^(add|create|new|schedule|put|plan)( an| a)? (event|appointment|meeting|date)?( called| for)?:? ?(.+?)( (to|on|in) (the |my |our )?calendar)?$')
        .firstMatch(t);
    if (m != null && (m.group(3) != null || t.startsWith('schedule') || m.group(6) != null)) {
      final parsed = _when(m.group(5)!, now);
      return VoiceCommand(VoiceAction.event, title: _cap(parsed.rest), when: parsed.when ?? now,
        timeGiven: parsed.timeGiven, heard: heard);
    }

    return VoiceCommand(VoiceAction.unknown, title: _cap(heard), heard: heard);
  }

  static String _clean(String s) => s.trim().replaceFirst(RegExp(r'^(to |that |about )'), '').trim();
  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static const _days = {'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4,
    'friday': 5, 'saturday': 6, 'sunday': 7};
  static const _numbers = {'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
    'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12,
    'fifteen': 15, 'twenty': 20, 'thirty': 30, 'forty five': 45, 'a': 1, 'an': 1, 'half an': 30};

  /// Pulls a day/time out of [text]; returns the rest as the title.
  static ({String rest, DateTime? when, bool timeGiven}) _when(String text, DateTime now) {
    var rest = ' $text ';
    DateTime? day;
    int? hour, minute;

    // "in 10 minutes" / "in two hours" / "in half an hour"
    final rel = RegExp(r' in (\d+|[a-z]+(?: [a-z]+)?) (minute|minutes|min|hour|hours) ').firstMatch(rest);
    if (rel != null) {
      final raw = rel.group(1)!;
      final n = int.tryParse(raw) ?? _numbers[raw];
      if (n != null) {
        final unit = rel.group(2)!.startsWith('h') ? Duration(hours: n) : Duration(minutes: raw == 'half an' ? 30 : n);
        final at = now.add(unit);
        rest = rest.replaceFirst(rel.group(0)!, ' ');
        return (rest: _tidy(rest), when: at, timeGiven: true);
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
        final target = _days[d.group(2)!]!;
        var add = (target - now.weekday) % 7;
        if (add == 0 || d.group(1)?.trim() == 'next') add = add == 0 ? 7 : add;
        day = today.add(Duration(days: add));
        rest = rest.replaceFirst(d.group(0)!, ' ');
      }
    }

    // "at 5", "at 5pm", "at 5:30 pm", "at 17:30", "at noon", "in the morning"
    final clock = RegExp(r' (at |by |around )?(\d{1,2})(?::(\d{2}))? ?(am|pm|a\.m\.|p\.m\.|o.?clock)? ').allMatches(rest)
        .where((x) => x.group(1) != null || x.group(4) != null).firstOrNull;
    if (clock != null) {
      var h = int.parse(clock.group(2)!);
      final mi = int.tryParse(clock.group(3) ?? '') ?? 0;
      final ap = clock.group(4) ?? '';
      if (ap.startsWith('p') && h < 12) h += 12;
      if (ap.startsWith('a') && h == 12) h = 0;
      if (ap.isEmpty && h >= 1 && h <= 7) h += 12; // "at 5" means 5 pm
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

  /// Short spoken summary lines, used for "what's on today".
  static String joinForSpeech(List<String> parts, {String empty = 'Nothing planned.'}) {
    final p = parts.where((x) => x.trim().isNotEmpty).toList();
    if (p.isEmpty) return empty;
    if (p.length == 1) return '${p.first}.';
    return '${p.sublist(0, p.length - 1).join(', ')}, and ${p.last}.';
  }
}
