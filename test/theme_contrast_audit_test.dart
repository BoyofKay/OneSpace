import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onespace/theme/onespace_appearance.dart';
import 'package:onespace/theme/theme_contrast_audit.dart';

void main(){
 test('all four palettes and all seasonal modes retain accessible text',(){
  for(final palette in OneSpacePalette.values){
   for(final brightness in Brightness.values){
    for(final season in SeasonChoice.values){
     final theme=OneSpaceTheme.build(
      palette:palette,brightness:brightness,season:season);
     final scheme=theme.colorScheme;
     final card=theme.cardTheme.color??scheme.surface;
     final label='${palette.name}/${brightness.name}/${season.name}';
     expect(ThemeContrastAudit.readableText(
      scheme.onSurface,card),isTrue,reason:'card body $label');
     expect(ThemeContrastAudit.readableText(
      scheme.onSurface,scheme.surface),isTrue,
      reason:'surface body $label');
     expect(ThemeContrastAudit.readableText(
      scheme.onPrimary,scheme.primary),isTrue,
      reason:'primary button $label');
     expect(ThemeContrastAudit.readableText(
      scheme.onPrimaryContainer,scheme.primaryContainer),isTrue,
      reason:'selected container $label');
     expect(ThemeContrastAudit.readableText(
      scheme.onInverseSurface,scheme.inverseSurface),isTrue,
      reason:'snackbar $label');
    }
   }
  }
 });
 test('contrast helper correctly rejects low contrast',(){
  expect(ThemeContrastAudit.readableText(Colors.white,Colors.white),false);
  expect(ThemeContrastAudit.readableText(Colors.black,Colors.white),true);
  expect(ThemeContrastAudit.readableLarge(Colors.black,Colors.white),true);
 });
}
