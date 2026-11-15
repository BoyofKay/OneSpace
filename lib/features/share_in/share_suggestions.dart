import 'package:material_ui/material_ui.dart';
import 'share_intake_rules.dart';

/// Where shared content can go (spec 4.1/4.2). "Items to sort" is always the
/// first choice and is offered separately, so it is not in this list.
enum ShareDestination {
  giftIdea('Gift idea for an occasion', Icons.card_giftcard_outlined),
  activityOption('Option in an Activity', Icons.compare_arrows),
  newActivity('New Activity', Icons.hub_outlined),
  todo('To-do', Icons.checklist_outlined),
  experience('Shared experience', Icons.movie_outlined),
  flightOption('Flight option for a trip', Icons.airplane_ticket_outlined),
  trip('Trip', Icons.flight_takeoff_outlined),
  note('Note', Icons.sticky_note_2_outlined),
  reminder('Reminder', Icons.alarm_outlined),
  event('Event', Icons.event_outlined);

  const ShareDestination(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// What kind of thing arrived, recognised from the content itself, never
/// from which app sent it.
enum ShareContentKind { shop, media, flight, travel, maps, website, datedText, text }

class ShareSuggestions {
  const ShareSuggestions._();

  static const _shops = ['amazon.', 'amzn.', 'walmart.', 'target.com', 'noon.com',
    'ikea.', 'ebay.', 'aliexpress.', 'etsy.', 'shein.', 'namshi.', 'jarir.',
    'extra.com', 'temu.', 'bestbuy.', 'costco.', 'carrefour', 'centrepoint',
    'sephora.', 'nike.com', 'zara.com', 'hm.com', 'apple.com/shop'];
  static const _media = ['youtube.', 'youtu.be', 'netflix.', 'spotify.', 'imdb.',
    'primevideo.', 'disneyplus.', 'hulu.', 'goodreads.', 'music.apple', 'tv.apple',
    'steampowered.', 'twitch.tv', 'shahid.', 'osn', 'anghami.', 'soundcloud.',
    'audible.', 'podcasts.', 'letterboxd.', 'tiktok.'];
  static const _travel = ['booking.com', 'airbnb.', 'expedia.', 'skyscanner.',
    'kayak.', 'trip.com', 'agoda.', 'hotels.com', 'flydubai.', 'saudia.',
    'emirates.', 'qatarairways.', 'flynas.', 'aa.com', 'united.com', 'delta.com',
    'tripadvisor.', 'google.com/travel', 'almosafer.', 'wego.'];
  /// R67: flight searches and airline sites (a flight to compare in a trip).
  static const _flights = ['google.com/travel/flights', 'skyscanner.', 'kayak.',
    'flydubai.', 'saudia.', 'emirates.', 'qatarairways.', 'flynas.', 'flyadeal.',
    'aa.com', 'united.com', 'delta.com', 'etihad.', 'turkishairlines.', 'egyptair.',
    '/flights', '/flight/'];
  static const _maps = ['maps.google.', 'google.com/maps', 'goo.gl/maps',
    'maps.app.goo.gl', 'maps.apple.', 'waze.com'];

  static final _dateWords = RegExp(
    r'\b(today|tonight|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|'
    r'next week|next month|jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|june?|july?|'
    r'aug(ust)?|sep(t(ember)?)?|oct(ober)?|nov(ember)?|dec(ember)?|'
    r'\d{1,2}[:.]\d{2}\s*(am|pm)?|\d{1,2}\s*(am|pm)|\d{1,2}[/-]\d{1,2}([/-]\d{2,4})?)\b',
    caseSensitive: false);

  static ShareContentKind kindOf(IncomingShare share) {
    final link = share.link.toLowerCase();
    bool any(List<String> keys) => keys.any(link.contains);
    if (link.isNotEmpty) {
      if (any(_maps)) return ShareContentKind.maps;
      if (any(_media)) return ShareContentKind.media;
      if (any(_flights)) return ShareContentKind.flight;
      if (any(_travel)) return ShareContentKind.travel;
      if (any(_shops)) return ShareContentKind.shop;
      return ShareContentKind.website;
    }
    final text = '${share.title} ${share.note}';
    return _dateWords.hasMatch(text) ? ShareContentKind.datedText : ShareContentKind.text;
  }

  /// Up to three suggestions, best first (spec 4.2).
  static List<ShareDestination> forShare(IncomingShare share) =>
      switch (kindOf(share)) {
        ShareContentKind.shop => const [ShareDestination.giftIdea,
          ShareDestination.activityOption, ShareDestination.todo],
        ShareContentKind.media => const [ShareDestination.experience,
          ShareDestination.newActivity, ShareDestination.note],
        ShareContentKind.flight => const [ShareDestination.flightOption,
          ShareDestination.trip, ShareDestination.note],
        ShareContentKind.travel => const [ShareDestination.trip,
          ShareDestination.newActivity, ShareDestination.note],
        ShareContentKind.maps => const [ShareDestination.newActivity,
          ShareDestination.trip, ShareDestination.event],
        ShareContentKind.website => const [ShareDestination.newActivity,
          ShareDestination.note, ShareDestination.activityOption],
        ShareContentKind.datedText => const [ShareDestination.reminder,
          ShareDestination.todo, ShareDestination.event],
        ShareContentKind.text => const [ShareDestination.note,
          ShareDestination.todo, ShareDestination.newActivity],
      };

  /// Everything else, for "More…".
  static List<ShareDestination> more(IncomingShare share) {
    final top = forShare(share);
    return [for (final d in ShareDestination.values) if (!top.contains(d)) d];
  }

  /// Items older than 30 days get a gentle "still want this?" label (spec 4.3).
  static bool isStale(DateTime savedAt, DateTime now) =>
      now.difference(savedAt).inDays > 30;
}
