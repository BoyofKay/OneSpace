import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/spaces/love_nudge_rules.dart';

void main() {
  final noon = DateTime(2026, 11, 15, 12);
  test('apart: nudge after one day, together after two', () {
    final yesterday = DateTime(2026, 11, 14, 20);
    expect(LoveNudgeRules.nudge(lastSent: yesterday, now: noon, apart: true),
        'Your last little love was yesterday');
    expect(LoveNudgeRules.nudge(lastSent: yesterday, now: noon, apart: false), isNull);
    expect(LoveNudgeRules.nudge(lastSent: DateTime(2026, 11, 12), now: noon, apart: false),
        'It has been 3 days since your last little love');
  });
  test('quiet at night, hidden after Not today, sent today = nothing', () {
    expect(LoveNudgeRules.nudge(lastSent: null, now: DateTime(2026, 11, 15, 22), apart: true), isNull);
    expect(LoveNudgeRules.nudge(lastSent: null, now: noon, apart: true,
        dismissedOn: DateTime(2026, 11, 15, 9)), isNull);
    expect(LoveNudgeRules.nudge(lastSent: DateTime(2026, 11, 15, 8), now: noon, apart: true), isNull);
    expect(LoveNudgeRules.nudge(lastSent: null, now: noon, apart: false), 'Send your first little love');
  });
}
