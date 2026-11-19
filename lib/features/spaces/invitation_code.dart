/// OneSpace invitation codes are 64 hexadecimal characters.
///
/// The matcher also accepts a pasted email, SMS, link or WhatsApp message.
String? normalizedInvitationCode(String input) {
  final code = input.trim().toLowerCase();
  if (RegExp(r'^[0-9a-f]{64}$').hasMatch(code)) return code;
  final found = RegExp(r'(?<![0-9a-f])[0-9a-f]{64}(?![0-9a-f])').firstMatch(code);
  return found?.group(0);
}

/// Use a first-party HTTPS link so a recipient has a browser fallback.
/// A verified App/Universal Link can open the installed application directly.
Uri invitationWebLink(String code, {bool qa = false}) => Uri.https(
  'onespace.live', '/app-invite', {
    'code': code,
    if (qa) 'env': 'qa',
  },
);

/// Used only when the person explicitly chooses "Open in OneSpace" on web.
/// QA and Production must not consume each other's invitations.
Uri invitationAppLink(String code, {bool qa = false}) => Uri(
  scheme: qa ? 'onespace-preview' : 'onespace',
  host: 'invite',
  queryParameters: {'code': code},
);

/// Reject unrelated links, wrong environments and malformed codes.
String? invitationCodeFromUri(Uri uri, {bool qa = false}) {
  final isWebsite = uri.scheme == 'https' &&
      uri.host == 'onespace.live' && uri.path == '/app-invite' &&
      ((uri.queryParameters['env'] == 'qa') == qa);
  final isApp = uri.scheme == (qa ? 'onespace-preview' : 'onespace') &&
      uri.host == 'invite';
  if (!isWebsite && !isApp) return null;
  final code = uri.queryParameters['code'];
  if (code == null) return null;
  // The query parameter must contain ONLY a code, never arbitrary text.
  return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(code)
      ? code.toLowerCase() : null;
}

/// Resending never creates another code or extends the original expiry.
/// For security, invitations should be shared only with the intended partner.
String invitationMessage(String code, {bool qa = false, bool email = false}) {
  final link = invitationWebLink(code, qa: qa);
  if (email) {
    return 'I would love for us to have our own space on OneSpace. 💙\\n\\n'
        'OneSpace helps us remember the little things, plan together, and feel connected — wherever we are.\\n\\n'
        'Tap this invitation to join me:\\n$link\\n\\n'
        'If OneSpace is already installed, open it from the invitation link. '
        'Otherwise, you can install it when your platform is available and use this code under Join your partner:\\n\\n'
        '$code\\n\\n'
        'Google Play: [OneSpace store link coming soon]\\n'
        'App Store: [OneSpace store link coming soon]\\n\\n'
        'This invitation expires at its original expiration time.\\n\\n'
        'One Life. Two Places. One Space.';
  }
  return 'Join me on OneSpace! 💙\\n\\n'
      'Open your invitation:\\n$link\\n\\n'
      'If the app is not installed, use the links on that page.\\n'
      'Manual invitation code (if needed):\\n$code\\n\\n'
      'Google Play: [coming soon] · App Store: [coming soon]\\n'
      'The original invitation expiration still applies.';
}
