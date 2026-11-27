import 'dart:convert';

/// R67: what we could read from a shared flight (Google Flights or a booking
/// site). Every field is optional; the person checks it before saving.
class FlightDraft {
  FlightDraft({this.origin, this.destination, this.departure, this.returnOn,
    this.airline, this.price, this.currency, this.link, this.provider, this.stops});
  String? origin, destination, airline, currency, link, provider;
  DateTime? departure, returnOn;
  double? price;
  int? stops;

  bool get isEmpty => origin == null && destination == null && departure == null &&
    airline == null && price == null;

  /// "RUH → PHL · Saudia" (or what is known of it).
  String get title => [
    if (origin != null || destination != null) '${origin ?? '?'} → ${destination ?? '?'}',
    if (airline != null) airline!,
  ].join(' · ');
}

/// R67: Google Flights search links and reading shared flight links/text.
class FlightLinks {
  FlightLinks._();

  static String _d(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// A Google Flights search already filled in. Google reads the plain
  /// sentence in `q` (airports, dates, one way, passengers).
  static Uri googleFlights({String? from, String? to, DateTime? depart, DateTime? back,
      bool oneWay = false, int adults = 1, int children = 0, int infants = 0}) {
    final words = <String>['Flights'];
    if (from != null && from.trim().isNotEmpty) words.add('from ${from.trim()}');
    if (to != null && to.trim().isNotEmpty) words.add('to ${to.trim()}');
    if (depart != null) {
      words.add('on ${_d(depart)}');
      if (!oneWay && back != null) words.add('through ${_d(back)}');
    }
    if (oneWay) words.add('one way');
    final who = <String>[
      if (adults > 0) '$adults adult${adults == 1 ? '' : 's'}',
      if (children > 0) '$children child${children == 1 ? '' : 'ren'}',
      if (infants > 0) '$infants infant${infants == 1 ? '' : 's'}',
    ];
    if (who.isNotEmpty) words.add('for ${who.join(' and ')}');
    return Uri.https('www.google.com', '/travel/flights', {'q': words.join(' '), 'hl': 'en'});
  }

  static const _hosts = <String, String>{
    'google.': 'Google Flights', 'skyscanner': 'Skyscanner', 'kayak': 'Kayak',
    'expedia': 'Expedia', 'booking.com': 'Booking.com', 'almosafer': 'Almosafer',
    'wego': 'Wego', 'momondo': 'Momondo', 'tripadvisor': 'Tripadvisor', 'trip.com': 'Trip.com',
    'kiwi.com': 'Kiwi.com', 'flyin': 'Flyin', 'tajawal': 'Tajawal', 'cheapflights': 'Cheapflights',
    'saudia.com': 'Saudia', 'flynas.com': 'flynas', 'flyadeal.com': 'flyadeal',
    'emirates.com': 'Emirates', 'qatarairways.com': 'Qatar Airways', 'etihad.com': 'Etihad',
    'turkishairlines.com': 'Turkish Airlines', 'egyptair.com': 'EgyptAir',
    'aa.com': 'American Airlines', 'united.com': 'United', 'delta.com': 'Delta',
    'britishairways.com': 'British Airways', 'lufthansa.com': 'Lufthansa',
  };

  static const airlines = <String>[
    'Saudia', 'flynas', 'flyadeal', 'Emirates', 'Qatar Airways', 'Etihad', 'Turkish Airlines',
    'EgyptAir', 'Gulf Air', 'Royal Jordanian', 'Oman Air', 'Kuwait Airways', 'flydubai',
    'Air Arabia', 'Lufthansa', 'British Airways', 'Air France', 'KLM', 'Swiss', 'Austrian',
    'Iberia', 'ITA Airways', 'Aer Lingus', 'Virgin Atlantic', 'American Airlines', 'American',
    'United', 'Delta', 'JetBlue', 'Alaska Airlines', 'Southwest', 'Air Canada', 'Qantas',
    'Singapore Airlines', 'Cathay Pacific', 'Pegasus', 'Royal Air Maroc', 'Ethiopian Airlines',
    'Kenya Airways', 'Air India', 'IndiGo', 'Pakistan International', 'SAS', 'Finnair', 'LOT',
  ];

  /// The site a link comes from ("Google Flights", "Skyscanner", an airline…).
  static String? providerFor(String? link) {
    final host = Uri.tryParse(link ?? '')?.host.toLowerCase() ?? '';
    if (host.isEmpty) return null;
    for (final e in _hosts.entries) {
      if (host.contains(e.key)) return e.value;
    }
    return host.replaceFirst(RegExp(r'^www\.'), '');
  }

  /// True when shared content looks like a flight (a flight search or booking link).
  static bool looksLikeFlight(String text) {
    final t = text.toLowerCase();
    return t.contains('google.com/travel/flights') || t.contains('/flights') ||
      t.contains('skyscanner') || t.contains('kayak.') || t.contains('flight');
  }

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  static const _symbols = {'\$': 'USD', '€': 'EUR', '£': 'GBP', 'ر.س': 'SAR', 'SR': 'SAR', 'E£': 'EGP'};

  /// Reads a shared flight. [isAirport] says whether a 3-letter word is a real
  /// airport code; [cityCode] turns a city name ("Riyadh") into a code.
  static FlightDraft parse(String text, {DateTime? today,
      bool Function(String code)? isAirport, String? Function(String city)? cityCode}) {
    final now = today ?? DateTime.now();
    final draft = FlightDraft();
    final url = RegExp(r'https?://[^\s<>"]+').firstMatch(text)?.group(0);
    if (url != null) {
      draft.link = url;
      draft.provider = providerFor(url);
      _fromGoogleTfs(url, draft);
    }
    final body = url == null ? text : text.replaceAll(url, ' ');

    // Airports: "(RUH)" or a known code standing alone.
    if (draft.origin == null || draft.destination == null) {
      final codes = <String>[];
      for (final m in RegExp(r'\b([A-Z]{3})\b').allMatches(body)) {
        final c = m.group(1)!;
        if (['USD', 'SAR', 'EUR', 'GBP', 'EGP', 'AED', 'QAR', 'KWD', 'BHD', 'OMR', 'JOD'].contains(c)) continue;
        if (isAirport != null && !isAirport(c)) continue;
        if (!codes.contains(c)) codes.add(c);
      }
      if (codes.length >= 2) {
        draft.origin ??= codes[0];
        draft.destination ??= codes[1];
      }
    }
    // Cities: "from Riyadh to Philadelphia".
    if ((draft.origin == null || draft.destination == null) && cityCode != null) {
      final m = RegExp(r'from ([A-Za-z .\-]+?) to ([A-Za-z .\-]+?)(?:[,·|\n]| on | for |$)',
        caseSensitive: false).firstMatch(body);
      if (m != null) {
        draft.origin ??= cityCode(m.group(1)!.trim());
        draft.destination ??= cityCode(m.group(2)!.trim());
      }
    }
    // Dates: ISO, "Dec 20", "20 Dec".
    if (draft.departure == null) {
      final dates = <DateTime>[];
      for (final m in RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b').allMatches(body)) {
        dates.add(DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!)));
      }
      final word = RegExp(r'\b(?:([A-Za-z]{3})[a-z]*\.? (\d{1,2})|(\d{1,2}) ([A-Za-z]{3})[a-z]*)\b(?:,? (\d{4}))?');
      for (final m in word.allMatches(body)) {
        final mon = _months[(m.group(1) ?? m.group(4) ?? '').toLowerCase()];
        final day = int.tryParse(m.group(2) ?? m.group(3) ?? '');
        if (mon == null || day == null || day < 1 || day > 31) continue;
        var year = int.tryParse(m.group(5) ?? '') ?? now.year;
        var d = DateTime(year, mon, day);
        if (m.group(5) == null && d.isBefore(DateTime(now.year, now.month, now.day))) d = DateTime(year + 1, mon, day);
        dates.add(d);
      }
      if (dates.isNotEmpty) draft.departure = dates.first;
      if (dates.length > 1 && !dates[1].isBefore(dates.first)) draft.returnOn = dates[1];
    }
    // Price: "SAR 4,250", "4,250 SAR", "$1,234".
    final price = RegExp(r'\b([A-Z]{3})\s?([\d,]+(?:\.\d{1,2})?)\b|\b([\d,]+(?:\.\d{1,2})?)\s?([A-Z]{3})\b|(\$|€|£|E£)\s?([\d,]+(?:\.\d{1,2})?)')
      .firstMatch(body);
    if (price != null) {
      final code = price.group(1) ?? price.group(4) ?? _symbols[price.group(5)];
      final amount = double.tryParse((price.group(2) ?? price.group(3) ?? price.group(6) ?? '').replaceAll(',', ''));
      if (code != null && amount != null && (isAirport == null || !isAirport(code) || _symbols.containsValue(code))) {
        draft.currency = code;
        draft.price = amount;
      }
    }
    // Stops.
    final lower = body.toLowerCase();
    if (lower.contains('nonstop') || lower.contains('non-stop') || lower.contains('direct')) {
      draft.stops = 0;
    } else {
      final s = RegExp(r'(\d) stops?').firstMatch(lower);
      if (s != null) draft.stops = int.parse(s.group(1)!);
    }
    // Airline.
    for (final a in airlines) {
      if (RegExp('\\b${RegExp.escape(a)}\\b', caseSensitive: false).hasMatch(body)) {
        draft.airline = a;
        break;
      }
    }
    if (draft.airline == null && draft.provider != null &&
        !['Google Flights', 'Skyscanner', 'Kayak', 'Expedia', 'Booking.com', 'Almosafer', 'Wego',
          'Momondo', 'Tripadvisor', 'Trip.com', 'Kiwi.com', 'Flyin', 'Tajawal', 'Cheapflights']
          .contains(draft.provider) && airlines.contains(draft.provider)) {
      draft.airline = draft.provider;
    }
    return draft;
  }

  /// Google Flights links carry the search in `tfs` (base64). The airports
  /// and dates sit inside as plain text: a date is "YYYY-MM-DD" and an
  /// airport is a 3-letter code, in the order of the trip.
  static void _fromGoogleTfs(String url, FlightDraft draft) {
    final uri = Uri.tryParse(url);
    final tfs = uri?.queryParameters['tfs'];
    if (tfs == null || tfs.isEmpty) return;
    String raw;
    try {
      var b = tfs.replaceAll('-', '+').replaceAll('_', '/');
      while (b.length % 4 != 0) {
        b += '=';
      }
      raw = latin1.decode(base64.decode(b));
    } catch (_) {
      return;
    }
    final dates = [for (final m in RegExp(r'(\d{4})-(\d{2})-(\d{2})').allMatches(raw))
      DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!))];
    final codes = [for (final m in RegExp(r'\x03([A-Z]{3})').allMatches(raw)) m.group(1)!];
    if (dates.isNotEmpty) draft.departure = dates.first;
    if (dates.length > 1) draft.returnOn = dates[1];
    if (codes.length >= 2) {
      draft.origin = codes[0];
      draft.destination = codes[1];
    }
  }
}
