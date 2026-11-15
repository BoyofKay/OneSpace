import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/voice_commands.dart';

void main() {
  // Sunday 15 Nov 2026, 10:00.
  final now = DateTime(2026, 11, 15, 10);
  VoiceCommand p(String s) => VoiceCommandRules.parse(s, now);

  test('reminder with tomorrow and a pm time', () {
    final c = p('Remind me to call the clinic tomorrow at 5 pm');
    expect(c.action, VoiceAction.reminder);
    expect(c.title, 'Call the clinic');
    expect(c.when, DateTime(2026, 11, 16, 17));
    expect(c.timeGiven, isTrue);
  });

  test('reminder "in 10 minutes"', () {
    final c = p('remind me to take the pizza out in 10 minutes');
    expect(c.title, 'Take the pizza out');
    expect(c.when, DateTime(2026, 11, 15, 10, 10));
  });

  test('bare "at 5" means 5 pm; past time today rolls to tomorrow', () {
    expect(p('remind me to stretch at 5').when, DateTime(2026, 11, 15, 17));
    expect(p('remind me to wake up at 8 am').when, DateTime(2026, 11, 16, 8));
  });

  test('weekday and tonight', () {
    expect(p('remind me to pay rent on friday').when, DateTime(2026, 11, 20, 9));
    expect(p('remind me to pay rent on friday').timeGiven, isFalse);
    expect(p('remind me to call mom tonight').when, DateTime(2026, 11, 15, 20));
  });

  test('note', () {
    final c = p('Take a note: the Wi-Fi password is on the router');
    expect(c.action, VoiceAction.note);
    expect(c.title, 'The wi-fi password is on the router');
  });

  test('add to a list', () {
    final c = p('add milk and eggs to the groceries list');
    expect(c.action, VoiceAction.addToList);
    expect(c.title, 'Milk and eggs');
    expect(c.target, 'groceries');
  });

  test('new list', () {
    final c = p('create a list called packing for Philly');
    expect(c.action, VoiceAction.newList);
    expect(c.title, 'Packing for philly');
  });

  test('event with a time', () {
    final c = p('add an event dinner with Sara on saturday at 7:30 pm');
    expect(c.action, VoiceAction.event);
    expect(c.title, 'Dinner with sara');
    expect(c.when, DateTime(2026, 11, 21, 19, 30));
    expect(c.timeGiven, isTrue);
  });

  test('open screens', () {
    expect(p('open the calendar').target, 'calendar');
    expect(p('go to my reminders').target, 'reminders');
    expect(p('show me the to-do lists').target, 'todo');
    expect(p('open settings page').action, VoiceAction.open);
  });

  test('read commands, love, search, help', () {
    expect(p("what's on today").action, VoiceAction.readToday);
    expect(p('read my reminders').action, VoiceAction.readReminders);
    expect(p('read my latest note').action, VoiceAction.readNotes);
    expect(p('send a little love').action, VoiceAction.love);
    final s = p('search for passport');
    expect(s.action, VoiceAction.search);
    expect(s.title, 'passport');
    expect(p('what can I say').action, VoiceAction.help);
  });

  test('unknown keeps the words', () {
    final c = p('buy flowers for Kay');
    expect(c.action, VoiceAction.unknown);
    expect(c.title, 'Buy flowers for Kay');
  });

  test('speech joining', () {
    expect(VoiceCommandRules.joinForSpeech([]), 'Nothing planned.');
    expect(VoiceCommandRules.joinForSpeech(['A']), 'A.');
    expect(VoiceCommandRules.joinForSpeech(['A', 'B', 'C']), 'A, B, and C.');
  });
}
