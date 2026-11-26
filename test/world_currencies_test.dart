import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/preferred_currency.dart';
import 'package:onespace/core/world_currencies.dart';

void main() {
  test('Settings offer every world currency with English and Arabic names (26 Nov 2026)', () {
    expect(worldCurrencies.length, greaterThanOrEqualTo(150));
    for (final e in worldCurrencies.entries) {
      expect(RegExp(r'^[A-Z]{3}$').hasMatch(e.key), isTrue, reason: e.key);
      expect(e.value.$1.trim(), isNotEmpty, reason: e.key);
      expect(RegExp(r'[؀-ۿ]').hasMatch(e.value.$2), isTrue, reason: e.key);
      expect(RegExp(r'[A-Za-z]').hasMatch(e.value.$2), isFalse, reason: 'Arabic name of ${e.key}');
    }
    for (final c in ['USD', 'EUR', 'GBP', 'JPY', 'CNY', 'INR', 'BRL', 'SAR', 'EGP', 'NGN', 'MXN', 'KRW']) {
      expect(worldCurrencies, contains(c));
    }
  });
  test('Choices are labelled in the app language and include the code', () {
    expect(PreferredCurrency.choices('en')['JPY'], 'Japanese yen (JPY)');
    expect(PreferredCurrency.choices('ar')['EGP'], 'جنيه مصري (EGP)');
    expect(PreferredCurrency.choices('en').length, worldCurrencies.length);
  });
  test('Global default is US dollar', () {
    PreferredCurrency.reset();
    expect(PreferredCurrency.code, 'USD');
  });
}
