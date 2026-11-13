import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/first_name.dart';
void main(){
 test('Only first name is shown; profile data is not changed',(){
  expect(FirstName.of('Alex Morgan Carter'),'Alex');
  expect(FirstName.of('  Alex   Morgan '),'Alex');
  expect(FirstName.of(''), 'there');
  expect(FirstName.of(null,fallback:'friend'),'friend');
  expect(FirstName.of('أحمد إسماعيل'),'أحمد');
 });
}
