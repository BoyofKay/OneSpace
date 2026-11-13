import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/coordinate/activity_voice_rules.dart';

void main() {
  Uint8List m4a([int size = 40]) {
    final b = Uint8List(size);
    b.setRange(4, 8, 'ftyp'.codeUnits);
    return b;
  }

  test('voice notes are capped at two minutes and five megabytes', () {
    expect(() => ActivityVoiceRules.validate(m4a(), 1), returnsNormally);
    expect(() => ActivityVoiceRules.validate(m4a(), 120), returnsNormally);
    expect(() => ActivityVoiceRules.validate(m4a(), 0), throwsFormatException);
    expect(() => ActivityVoiceRules.validate(m4a(), 121), throwsFormatException);
    expect(() => ActivityVoiceRules.validate(m4a(5 * 1024 * 1024 + 1), 2),
      throwsFormatException);
  });

  test('disguised files and empty audio cannot be uploaded', () {
    expect(() => ActivityVoiceRules.validate(Uint8List(0), 10),
      throwsFormatException);
    expect(() => ActivityVoiceRules.validate(
      Uint8List.fromList('not an audio file'.codeUnits), 2,
    ), throwsFormatException);
  });

  test('duration labels are compact and understandable', () {
    expect(ActivityVoiceRules.durationLabel(0), '0:00');
    expect(ActivityVoiceRules.durationLabel(59), '0:59');
    expect(ActivityVoiceRules.durationLabel(120), '2:00');
  });

  test('voice paths require UUID-only Activity and user folders', () {
    const activity='12345678-1234-4123-8123-123456789abc';
    const user='87654321-4321-4321-8321-cba987654321';
    const id='12345678-1234-4234-8234-123456789abc';
    expect(ActivityVoiceRules.objectPath(
      activityId:activity,userId:user,fileId:id,
    ), '$activity/$user/$id.m4a');
    expect(() => ActivityVoiceRules.objectPath(
      activityId:'../another',userId:user,fileId:id,
    ), throwsFormatException);
    expect(() => ActivityVoiceRules.objectPath(
      activityId:activity,userId:user,fileId:'../../outside',
    ), throwsFormatException);
  });
}
