import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/spaces/archive_retention_rules.dart';

void main() {
  test('automatic app-private save does not delete server archive', () {
    expect(ArchiveRetentionRules.mayConfirmExternalSave(
      userInitiated:false,savedOutsideApp:false,verifiedAfterWrite:true),false);
  });

  test('manual action without confirmed write cannot delete archive', () {
    expect(ArchiveRetentionRules.mayConfirmExternalSave(
      userInitiated:true,savedOutsideApp:true,verifiedAfterWrite:false),false);
  });

  test('verified user-initiated external file save may trigger cleanup', () {
    expect(ArchiveRetentionRules.mayConfirmExternalSave(
      userInitiated:true,savedOutsideApp:true,verifiedAfterWrite:true),true);
  });

  test('server expiration is 30 days from readiness', () {
    final ready = DateTime.utc(2026,11,19,12);
    expect(ArchiveRetentionRules.expiresAt(ready),
      DateTime.utc(2026,12,19,12));
  });
}
