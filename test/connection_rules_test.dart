import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/connection/connection_rules.dart';

void main() {
  group('Goal input', () {
    test('supports meaningful multilingual goals', () {
      expect(ConnectionRules.validGoal(
        title:'هدفنا',description:'Work on this together',progress:40),isTrue);
      expect(ConnectionRules.validGoal(
        title:' ',description:'Anything',progress:40),isFalse);
      expect(ConnectionRules.validGoal(
        title:List.filled(121,'x').join(),description:'',progress:40),isFalse);
      expect(ConnectionRules.validGoal(
        title:'Move home',description:'',progress:101),isFalse);
    });
  });
  group('Daily check-in date and limits', () {
    final now=DateTime(2026,11,12,23,30);
    test('allows today and previous days, never a future entry', () {
      expect(ConnectionRules.validCheckin(
        day:DateTime(2026,11,12),now:now,mood:3,
        message:'Thinking of you',gratitude:'Family'),isTrue);
      expect(ConnectionRules.validCheckin(
        day:DateTime(2026,11,13),now:now,mood:3,
        message:'Hello',gratitude:''),isFalse);
    });
    test('rejects invalid mood and excessive text', () {
      expect(ConnectionRules.validCheckin(
        day:now,now:now,mood:0,message:'',gratitude:''),isFalse);
      expect(ConnectionRules.validCheckin(
        day:now,now:now,mood:4,
        message:List.filled(2001,'x').join(),gratitude:''),isFalse);
    });
  });
}
