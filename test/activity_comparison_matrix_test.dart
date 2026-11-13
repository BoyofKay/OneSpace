import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/coordinate/activity_comparison_matrix.dart';

Map<String, dynamic> option(
  String id, String label, Map<String, dynamic> payload, {
  String? archivedAt,
}) => {
  'id': id,
  'activity_id': 'activity-a',
  'parent_component_id': null,
  'kind': 'option',
  'label': label,
  'payload': payload,
  'archived_at': archivedAt,
};

Map<String, dynamic> child(
  String optionId, String kind, String label, String value, {
  String? currency,
  String activityId = 'activity-a',
}) => {
  'id': '$optionId-$label',
  'activity_id': activityId,
  'parent_component_id': optionId,
  'kind': kind,
  'label': label,
  'payload': {
    'value': value,
    'currency': currency,
  },
};

void main() {
  test('heater comparison aligns differently ordered requirements', () {
    final records = [
      option('amazon', 'Amazon heater', {
        'price': '89.99', 'currency': 'USD', 'specs': '1500W',
        'url': 'https://example.org/amazon',
      }),
      option('walmart', 'Walmart heater', {
        'price': '105', 'currency': 'USD', 'note': 'Store pickup',
      }),
      child('amazon', 'spec', 'Timer', '12 hours'),
      child('walmart', 'spec', 'Automatic Shutoff', 'Yes'),
      child('amazon', 'spec', 'Automatic Shutoff', 'Yes'),
      child('walmart', 'spec', 'timer', '6 hours'),
    ];
    final model = ActivityComparisonMatrix.build(records);
    expect(model.columns.map((c) => c.title), [
      'Amazon heater', 'Walmart heater',
    ]);
    final labels = model.rows.map((r) => r.label).toList();
    expect(labels.first, 'Price');
    expect(labels, contains('Timer'));
    expect(labels.where((l) => l.toLowerCase() == 'timer').length, 1);
    expect(model.value('price', model.columns[0]), 'USD 89.99');
    expect(model.value('timer', model.columns[0]), '12 hours');
    expect(model.value('timer', model.columns[1]), '6 hours');
    expect(model.value('automatic shutoff', model.columns[1]), 'Yes');
    expect(model.value('specifications', model.columns[1]), '—');
    expect(model.columns.first.sourceUrl, 'https://example.org/amazon');
  });

  test('gymnastics criteria are flexible and do not require prices', () {
    final records = [
      option('gym-a', 'Gym A', {'value': 'A short trial available'}),
      option('gym-b', 'Gym B', {}),
      child('gym-a', 'spec', 'Parent required', 'Yes'),
      child('gym-a', 'spec', 'Age range', '2–4 years'),
      child('gym-b', 'spec', 'Swimming included', 'No'),
      child('gym-b', 'spec', 'Age Range', '3–5 years'),
      child('gym-a', 'date', 'First visit', '2026-11-25'),
    ];
    final model = ActivityComparisonMatrix.build(records);
    expect(model.rows.map((r) => r.label), contains('Age range'));
    expect(model.value('age range', model.columns[0]), '2–4 years');
    expect(model.value('age range', model.columns[1]), '3–5 years');
    expect(model.value('swimming included', model.columns[0]), '—');
    expect(model.value('price', model.columns[0]), '—');
  });

  test('only attached, nonarchived same-Activity components appear', () {
    final records = [
      option('a', 'Available', {}),
      option('b', 'Archived', {}, archivedAt: '2026-11-13'),
      child('a', 'spec', 'Age range', '2–4'),
      child('a', 'spec', 'Hidden', 'private', activityId: 'other-space'),
      child('b', 'spec', 'Irrelevant', 'gone'),
      child('a', 'step', 'Email sent', 'Yes'),
    ];
    final model = ActivityComparisonMatrix.build(records);
    expect(model.columns.length, 1);
    expect(model.rows.map((r) => r.label), ['Age range']);
  });

  test('child price takes precedence over the initial observed price', () {
    final model = ActivityComparisonMatrix.build([
      option('one', 'Heater', {'price': '119.00', 'currency': 'USD'}),
      child('one', 'price', 'New price', '99.00', currency: 'USD'),
    ]);
    expect(model.value('price', model.columns.single), 'USD 99.00');
  });

  test('retains each partner opinion without treating it as a decision', () {
    final model = ActivityComparisonMatrix.build([
      option('one', 'Heater', {}),
    ], reactions: [
      {'component_id': 'one', 'user_id': 'a', 'opinion': 1},
      {'component_id': 'one', 'user_id': 'b', 'opinion': -1},
    ], currentUserId: 'a');
    expect(model.columns.single.myOpinion, 1);
    expect(model.columns.single.partnerOpinion, -1);
  });

  test('contact data becomes useful side-by-side comparison criteria', () {
    final model = ActivityComparisonMatrix.build([
      option('gym-a','Gym A',{}),
      option('gym-b','Gym B',{}),
      {
        'id':'contact-a', 'activity_id':'activity-a',
        'parent_component_id':'gym-a', 'kind':'contact',
        'label':'Admissions', 'payload':{
          'contact_name':'Sarah', 'phone':'+1 610 555 0147',
          'email':'hello@example.com',
          'address':'123 Main Street',
          'working_hours':'Mon–Fri, 9–5',
        },
      },
      {
        'id':'contact-b', 'activity_id':'activity-a',
        'parent_component_id':'gym-b', 'kind':'contact',
        'label':'Office', 'payload':{
          'phone':'+1 610 555 0198',
          'working_hours':'Saturday, 10–2',
        },
      },
    ]);
    expect(model.value('contact person',model.columns[0]),'Sarah');
    expect(model.value('contact person',model.columns[1]),'—');
    expect(model.value('phone',model.columns[1]),'+1 610 555 0198');
    expect(model.value('working hours',model.columns[0]),'Mon–Fri, 9–5');
    expect(model.rows.map((r)=>r.label),contains('Email'));
  });

  test('empty comparison does not fabricate data or throw', () {
    final model = ActivityComparisonMatrix.build([
      {'kind': 'note', 'label': 'Not an option'},
    ]);
    expect(model.columns, isEmpty);
    expect(model.rows, isEmpty);
  });
}
