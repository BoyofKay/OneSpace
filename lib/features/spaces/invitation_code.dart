/// Invitation codes are 64 hexadecimal characters.
///
/// R71: the code is found even inside a whole pasted message ("Join me on
/// OneSpace … code: abcd…"), so it can be sent by WhatsApp, SMS or email.
String? normalizedInvitationCode(String input) {
  final code = input.trim().toLowerCase();
  if (RegExp(r'^[0-9a-f]{64}$').hasMatch(code)) return code;
  final found = RegExp(r'(?<![0-9a-f])[0-9a-f]{64}(?![0-9a-f])').firstMatch(code);
  return found?.group(0);
}

/// The message sent with the code.
String invitationMessage(String code) =>
  'Join me on OneSpace, our shared space. Open OneSpace › Join your partner and paste this message (or the code). '
  'It works for 48 hours.\n\nCode: $code';
