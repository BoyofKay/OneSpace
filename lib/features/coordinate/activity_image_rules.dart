import 'dart:typed_data';

/// Keep photo paths private to one Activity and one contributor. Do not store
/// permanent or public URLs in components.
class ActivityImageRules {
  const ActivityImageRules._();

  static const bucket = 'onespace-activity-media';
  static const maxBytes = 6 * 1024 * 1024;

  static String? mimeType(Uint8List bytes) {
    if (bytes.length < 12) return null;
    if (bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e &&
        bytes[3] == 0x47 && bytes[4] == 0x0d && bytes[5] == 0x0a &&
        bytes[6] == 0x1a && bytes[7] == 0x0a) {
      return 'image/png';
    }
    if (String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }

  static String extension(String mime) => switch (mime) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    _ => throw ArgumentError.value(mime, 'mime', 'Not an allowed photo type'),
  };

  static void validate(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Photo must be smaller than 6 MB.');
    }
    if (mimeType(bytes) == null) {
      throw const FormatException('Please choose a JPEG, PNG or WebP photo.');
    }
  }

  static String objectPath({
    required String activityId,
    required String userId,
    required String filename,
  }) {
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    if (!uuid.hasMatch(activityId) || !uuid.hasMatch(userId) ||
        !RegExp(r'^[0-9a-zA-Z-]+\.(jpg|png|webp)$').hasMatch(filename)) {
      throw const FormatException('Invalid private media path.');
    }
    return '$activityId/$userId/$filename';
  }
}
