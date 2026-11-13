import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/coordinate/activity_decision_rules.dart';

void main() {
  test('every decision action maps to a valid Activity stage', () {
    final expected = {
      'chosen': 'decided',
      'purchased': 'purchased',
      'delivered': 'completed',
      'registered': 'completed',
      'postponed': 'on_hold',
      'reopened': 'exploring',
      'cancelled': 'cancelled',
    };
    expect(ActivityDecisionRules.actions.toSet(), expected.keys.toSet());
    for (final entry in expected.entries) {
      expect(ActivityDecisionRules.stageFor(entry.key), entry.value);
      expect(ActivityDecisionRules.titleFor(entry.key), isNotEmpty);
    }
    expect(() => ActivityDecisionRules.stageFor('invalid'), throwsArgumentError);
    expect(ActivityDecisionRules.requiresOption('chosen'), isTrue);
    expect(ActivityDecisionRules.requiresOption('purchased'), isFalse);
  });

  test('reopened Activity remains part of its decision history', () {
    final events = [
      {'id': '1', 'action': 'chosen', 'created_at': '2026-11-13T08:00:00Z'},
      {'id': '2', 'action': 'purchased', 'created_at': '2026-11-13T09:00:00Z'},
      {'id': '3', 'action': 'reopened', 'created_at': '2026-11-14T10:00:00Z'},
    ];
    final latest = ActivityDecisionRules.latest(events);
    expect(latest?['action'], 'reopened');
    expect(ActivityDecisionRules.stageFor(latest?['action'] as String),
        'exploring');
    expect(events.first['action'], 'chosen'); // Input order remains intact
    expect(events.length, 3);
  });

  test('latest returns null for an empty history', () {
    expect(ActivityDecisionRules.latest([]), isNull);
  });

  test('latest understands offset timestamps, not string sort alone', () {
    final events = [
      {'id': 'old', 'created_at': '2026-11-13T15:00:00+03:00'},
      {'id': 'new', 'created_at': '2026-11-13T13:30:00Z'},
    ];
    expect(ActivityDecisionRules.latest(events)?['id'], 'new');
  });
}
