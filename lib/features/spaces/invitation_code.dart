/// Normalize and validate the one-time 64-character hexadecimal pairing code.
/// Never log or persist these codes to the device.
String? normalizedInvitationCode(String input) {
  final code = input.trim().toLowerCase();
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(code) ? code : null;
}
