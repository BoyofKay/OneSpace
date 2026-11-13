import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/theme/onespace_appearance.dart';

void main(){
 test('Four themes are available without tying palettes to gender',(){
  expect(OneSpacePalette.values.length,4);
  for(final palette in OneSpacePalette.values){
   final light=OneSpaceTheme.build(palette:palette,brightness:Brightness.light);
   final dark=OneSpaceTheme.build(palette:palette,brightness:Brightness.dark);
   expect(light.colorScheme.brightness,Brightness.light);
   expect(dark.colorScheme.brightness,Brightness.dark);
   expect(light.cardTheme.shape,isNotNull);
  }
 });
 test('Automatic seasonal decoration uses specific dates',(){
  expect(OneSpaceAppearance.effectiveSeason(
   SeasonChoice.automatic,DateTime(2026,2,14)),SeasonChoice.valentines);
  expect(OneSpaceAppearance.effectiveSeason(
   SeasonChoice.automatic,DateTime(2026,10,31)),SeasonChoice.halloween);
  expect(OneSpaceAppearance.effectiveSeason(
   SeasonChoice.automatic,DateTime(2026,12,25)),SeasonChoice.christmas);
  expect(OneSpaceAppearance.effectiveSeason(
   SeasonChoice.automatic,DateTime(2026,7,1)),SeasonChoice.off);
 });
 test('Preserved user-requested theme names are the actual four presets',(){
  expect(OneSpacePalette.values.map(OneSpaceAppearance.paletteName).toList(),[
   'Midnight Blue','Monochrome','Clean Light','Soft Rose',
  ]);
 });
 test('Holiday palette affects entire component scheme, not a single card',(){
  final ordinary=OneSpaceTheme.build(
   palette:OneSpacePalette.cleanLight,brightness:Brightness.light);
  final holiday=OneSpaceTheme.build(
   palette:OneSpacePalette.cleanLight,brightness:Brightness.light,
   season:SeasonChoice.halloween);
  expect(ordinary.colorScheme.primary,isNot(holiday.colorScheme.primary));
  expect(ordinary.appBarTheme.backgroundColor,
   isNot(holiday.appBarTheme.backgroundColor));
  expect(ordinary.cardTheme.color,isNot(holiday.cardTheme.color));
  expect(holiday.extension<OneSpaceVisualTokens>(),isNotNull);
 });
 test('Manual Eid or anniversary theme does not infer a lunar date',(){
  expect(OneSpaceAppearance.effectiveSeason(
   SeasonChoice.eid,DateTime(2027,6,8)),SeasonChoice.eid);
  expect(OneSpaceAppearance.effectiveSeason(
   SeasonChoice.anniversary,DateTime(2027,4,23)),SeasonChoice.anniversary);
 });
 test('Manual off always overrides automatic seasonal theme',(){
  expect(OneSpaceAppearance.effectiveSeason(SeasonChoice.off,DateTime(2026,12,25)),
   SeasonChoice.off);
 });
 test('Material themes keep text colors tied to their brightness',(){
  final theme=OneSpaceTheme.build(
    palette:OneSpacePalette.midnightBlue,brightness:Brightness.dark);
  expect(theme.appBarTheme.foregroundColor,theme.colorScheme.onSurface);
  expect(theme.scaffoldBackgroundColor, isNot(equals(Colors.white)));
 });
}
