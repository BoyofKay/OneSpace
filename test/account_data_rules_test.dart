import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/settings/account_data_screen.dart';

void main() {
  test('deletion needs the typed word', () {
    expect(AccountDataRules.confirmed('delete'), isTrue);
    expect(AccountDataRules.confirmed(' DELETE '), isTrue);
    expect(AccountDataRules.confirmed('del'), isFalse);
  });
  test('export file name carries the date', () {
    expect(AccountDataRules.fileName(DateTime(2026, 11, 5)), 'OneSpace-my-data-2026-11-05.json');
  });
  test('pending only when not cancelled or completed', () {
    expect(AccountDataRules.pending(null), isFalse);
    expect(AccountDataRules.pending({'cancelled_at': null, 'completed_at': null}), isTrue);
    expect(AccountDataRules.pending({'cancelled_at': '2026-11-15', 'completed_at': null}), isFalse);
  });
}
