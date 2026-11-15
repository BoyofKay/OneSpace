import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/form_kit.dart';

void main() {
  const me = 'me', partner = 'p';
  test('only me forces belongs to me', () {
    final v = MetaRules.setShared(const MetaValues(shared: true, belongsTo: partner), false, me);
    expect(v.shared, isFalse);
    expect(v.belongsTo, me);
  });
  test('partner or both of us forces shared', () {
    expect(MetaRules.setBelongsTo(const MetaValues(shared: false, belongsTo: me), partner, me).shared, isTrue);
    expect(MetaRules.setBelongsTo(const MetaValues(shared: false, belongsTo: me), null, me).shared, isTrue);
  });
  test('me keeps visibility', () {
    expect(MetaRules.setBelongsTo(const MetaValues(shared: true), me, me).shared, isTrue);
  });
  test('labels', () {
    const people = SpacePeople(me: me, partnerId: partner, partnerName: 'Kay');
    expect(MetaRules.belongsLabel(null, people), 'Both of us');
    expect(MetaRules.belongsLabel(me, people), 'Me');
    expect(MetaRules.belongsLabel(partner, people), 'Kay');
  });
  test('copyWith can clear the date', () {
    final v = MetaValues(date: DateTime(2026, 1, 1)).copyWith(date: null);
    expect(v.date, isNull);
  });
}
