import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/theme/occasion_theme_resolver.dart';
import 'package:onespace/theme/onespace_appearance.dart';
void main(){
 test('Authorized birthday activates only on its exact calendar day',(){
  final rows=<Map<String,dynamic>>[
   {'kind':'birthday','occasion_on':'2000-12-14','annual':true,
    'status':'planning','archived_at':null},
  ];
  expect(OccasionThemeResolver.forDate(rows,DateTime(2026,12,14)),
   SeasonChoice.birthday);
  expect(OccasionThemeResolver.forDate(rows,DateTime(2026,12,13)),isNull);
 });
 test('Archived/cancelled and unseen plans never activate a theme',(){
  final rows=<Map<String,dynamic>>[
   {'kind':'birthday','occasion_on':'2026-11-13','annual':true,
    'status':'cancelled','archived_at':null},
   {'kind':'anniversary','occasion_on':'2026-11-13','annual':true,
    'status':'planning','archived_at':'2026-11-01'},
  ];
  expect(OccasionThemeResolver.forDate(rows,DateTime(2026,11,13)),isNull);
 });
 test('Anniversary takes priority over birthday when both are authorized',(){
  final rows=<Map<String,dynamic>>[
   {'kind':'birthday','occasion_on':'2000-01-02','annual':true},
   {'kind':'anniversary','occasion_on':'2020-01-02','annual':true},
  ];
  expect(OccasionThemeResolver.forDate(rows,DateTime(2026,1,2)),
   SeasonChoice.anniversary);
 });
}
