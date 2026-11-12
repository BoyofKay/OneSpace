import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/lists/list_item_rules.dart';
import 'package:onespace/features/notes/note_draft_rules.dart';

void main() {
  group('Shopping and checklist validation', () {
    test('accepts a bilingual item with a fractional quantity', () {
      expect(ListItemRules.isValid(
        label: 'أرز',
        quantity: 1.5,
        unit: 'kg',
        note: 'For dinner',
      ), isTrue);
    });
    test('rejects empty name, invalid and excessive quantities', () {
      for (final quantity in [-2.0, 0.0, 100000.0, double.nan, double.infinity]) {
        expect(ListItemRules.isValid(
          label: 'Milk', quantity: quantity, unit: '', note: '',
        ), isFalse);
      }
      expect(ListItemRules.isValid(
        label: '  ', quantity: 1, unit: '', note: '',
      ), isFalse);
    });
    test('enforces length restrictions without losing Arabic text', () {
      expect(ListItemRules.isValid(
        label: 'Apple', quantity: 1, unit: 'A' * 25, note: '',
      ), isFalse);
      expect(ListItemRules.isValid(
        label: 'A' * 201, quantity: 1, unit: '', note: '',
      ), isFalse);
    });
  });
  group('Collaborative note validation', () {
    test('accepts multilingual notes and an empty body', () {
      expect(NoteDraftRules.isValid(
        title: 'خطط السفر', body: 'Flights and accommodation',
      ), isTrue);
      expect(NoteDraftRules.isValid(title: 'Idea', body: ''), isTrue);
    });
    test('rejects empty titles and large documents', () {
      expect(NoteDraftRules.isValid(title: '  ', body: 'text'), isFalse);
      expect(NoteDraftRules.isValid(title: 'A' * 121, body: 'text'), isFalse);
      expect(NoteDraftRules.isValid(title: 'Idea', body: 'B' * 30001), isFalse);
    });
  });
}
