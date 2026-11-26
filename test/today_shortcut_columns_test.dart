import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/spaces/shared_space_screen.dart';

void main() {
  test('Today shortcuts: 3 per row on a phone, more on wide screens (26 Nov 2026)', () {
    expect(shortcutColumns(360), 3);
    expect(shortcutColumns(412), 3);
    expect(shortcutColumns(800), 6);
    expect(shortcutColumns(2000), 8);
    expect(shortcutColumns(double.infinity), 3);
  });
}
