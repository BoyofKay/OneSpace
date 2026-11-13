import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/coordinate/activity_image_rules.dart';

void main() {
  test('identifies supported photos from actual bytes, not a filename', () {
    expect(ActivityImageRules.mimeType(Uint8List.fromList([
      0xff,0xd8,0xff,0xe0,0,0,0,0,0,0,0,0,
    ])), 'image/jpeg');
    expect(ActivityImageRules.mimeType(Uint8List.fromList([
      0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a,0,0,0,0,
    ])), 'image/png');
    expect(ActivityImageRules.mimeType(Uint8List.fromList(
      'RIFFabcdWEBP'.codeUnits,
    )), 'image/webp');
    expect(ActivityImageRules.mimeType(Uint8List.fromList(
      'not an image'.codeUnits,
    )), isNull);
  });

  test('rejects oversized photos and invalid content', () {
    expect(() => ActivityImageRules.validate(Uint8List(0)),
      throwsFormatException);
    expect(() => ActivityImageRules.validate(
      Uint8List(ActivityImageRules.maxBytes + 1),
    ), throwsFormatException);
  });

  test('media paths require two UUID folders and a safe filename', () {
    const a='12345678-1234-4123-8123-123456789abc';
    const b='87654321-4321-4321-8321-cba987654321';
    expect(ActivityImageRules.objectPath(
      activityId:a,userId:b,filename:'12345.jpg',
    ), '$a/$b/12345.jpg');
    expect(() => ActivityImageRules.objectPath(
      activityId:'../../private',userId:b,filename:'test.jpg',
    ), throwsFormatException);
    expect(() => ActivityImageRules.objectPath(
      activityId:a,userId:b,filename:'../../image.png',
    ), throwsFormatException);
  });

  test('private image paths never contain a public URL', () {
    expect(ActivityImageRules.extension('image/jpeg'), 'jpg');
    expect(ActivityImageRules.extension('image/png'), 'png');
    expect(() => ActivityImageRules.extension('image/svg+xml'),
      throwsArgumentError);
  });
}
