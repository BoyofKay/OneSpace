import 'package:material_ui/material_ui.dart';

/// WCAG relative luminance checks used in theme regressions.
/// 4.5:1 normal body text, 3:1 large text / interactive icons.
class ThemeContrastAudit {
 const ThemeContrastAudit._();
 static double ratio(Color foreground,Color background){
  final a=foreground.computeLuminance();
  final b=background.computeLuminance();
  final hi=a>b?a:b;
  final lo=a>b?b:a;
  return (hi+0.05)/(lo+0.05);
 }
 static bool readableText(Color fg,Color bg)=>ratio(fg,bg)>=4.5;
 static bool readableLarge(Color fg,Color bg)=>ratio(fg,bg)>=3.0;
}
