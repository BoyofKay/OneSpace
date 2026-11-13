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
   SeasonChoice.automatic,DateTime(2026,12,25)),SeasonChoice.winter);
  expect(OneSpaceAppearance.effectiveSeason(
   SeasonChoice.automatic,DateTime(2026,7,1)),SeasonChoice.off);
 });
 test('Manual off always overrides automatic seasonal theme',(){
  expect(OneSpaceAppearance.effectiveSeason(SeasonChoice.off,DateTime(2026,12,25)),
   SeasonChoice.off);
 });
 test('Material themes keep text colors tied to their brightness',(){
  final theme=OneSpaceTheme.build(
    palette:OneSpacePalette.indigo,brightness:Brightness.dark);
  expect(theme.appBarTheme.foregroundColor,theme.colorScheme.onSurface);
  expect(theme.scaffoldBackgroundColor, isNot(equals(Colors.white)));
 });
}
