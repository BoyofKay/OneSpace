import 'dart:typed_data';

/// Local validation for OneSpace voice files. Never trust extensions, client
/// durations, or object paths alone; the bucket and PostgreSQL enforce limits.
class ActivityVoiceRules {
  const ActivityVoiceRules._();

  static const bucket = 'onespace-activity-voice';
  static const maxSeconds = 120;
  static const maxBytes = 5 * 1024 * 1024;

  static String durationLabel(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  static void validate(Uint8List bytes, int seconds) {
    if (seconds < 1 || seconds > maxSeconds) {
      throw const FormatException('Voice recording must be 1–120 seconds.');
    }
    if (bytes.length < 12 || bytes.length > maxBytes) {
      throw const FormatException('Voice recording must be smaller than 5 MB.');
    }
    // MPEG-4 container header used by AAC-in-M4A.
    if (String.fromCharCodes(bytes.sublist(4, 8)) != 'ftyp') {
      throw const FormatException('Unable to read this M4A recording.');
    }
  }

  static String objectPath({
    required String activityId,
    required String userId,
    required String fileId,
  }) {
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    if (!uuid.hasMatch(activityId) || !uuid.hasMatch(userId) ||
        !uuid.hasMatch(fileId)) {
      throw const FormatException('Invalid voice storage location.');
    }
    return '$activityId/$userId/$fileId.m4a';
  }
}
