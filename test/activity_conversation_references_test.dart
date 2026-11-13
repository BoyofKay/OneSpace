import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/coordinate/activity_conversation_references.dart';

void main() {
  final messages = <Map<String, dynamic>>[
    {
      'id': 'first',
      'activity_id': 'heater',
      'body': 'Please check the voltage before buying the heater.',
    },
    {
      'id': 'second',
      'activity_id': 'heater',
      'reply_to': 'first',
      'body': 'It supports our voltage.',
    },
    {
      'id': 'outside',
      'activity_id': 'another-activity',
      'body': 'Sensitive outside text.',
    },
  ];
  test('replies preview the actual previous message', () {
    expect(ActivityConversationReferences.quotedMessage(
      messages[1], messages,
    ), 'Please check the voltage before buying the heater.');
  });

  test('missing reference does not leak another Activity message', () {
    expect(ActivityConversationReferences.quotedMessage({
      'id': 'test',
      'activity_id': 'heater',
      'reply_to': 'outside',
    }, messages), 'Earlier message unavailable');
  });

  test('component-specific comments display the correct candidate', () {
    final records = [
      {
        'id': 'amazon',
        'activity_id': 'heater',
        'label': 'Amazon Heater',
      },
      {
        'id': 'outside',
        'activity_id': 'gymnastics',
        'label': 'Private class information',
      },
    ];
    expect(ActivityConversationReferences.componentName({
      'activity_id': 'heater',
      'component_id': 'amazon',
    }, records), 'Amazon Heater');
    expect(ActivityConversationReferences.componentName({
      'activity_id': 'heater',
      'component_id': 'outside',
    }, records), 'Attached item unavailable');
  });

  test('preview is short and whitespace normalized', () {
    expect(ActivityConversationReferences.excerpt('Hello\n  there   friend'),
      'Hello there friend');
    final text = 'Voice ' * 35;
    final preview = ActivityConversationReferences.excerpt(text);
    expect(preview.runes.length, lessThanOrEqualTo(88));
    expect(preview.endsWith('…'), isTrue);
  });

  test('plain messages need no reply or component target', () {
    expect(ActivityConversationReferences.quotedMessage(messages[0], messages),
      isNull);
    expect(ActivityConversationReferences.componentName(messages[0], const []),
      isNull);
  });
}
