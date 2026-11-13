import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'onespace_appearance.dart';

/// Every route gets the same branded, season-aware background. Decorations
/// never intercept touches and do not include photos, user data or network IO.
class OneSpaceCanvas extends StatelessWidget{
 const OneSpaceCanvas({super.key,required this.child,required this.season});
 final Widget child;
 final SeasonChoice season;
 @override Widget build(BuildContext context){
  final theme=Theme.of(context);
  final tokens=theme.extension<OneSpaceVisualTokens>();
  if(tokens==null)return child;
  return Stack(fit:StackFit.expand,children:[
   DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(
    begin:Alignment.topLeft,end:Alignment.bottomRight,
    colors:[tokens.heroEnd,tokens.canvas,tokens.canvas]))),
   IgnorePointer(child:CustomPaint(
    painter:_AtmospherePainter(
     accent:tokens.motifColor,season:season,
     light:theme.brightness==Brightness.light))),
   child,
  ]);
 }
}

class _AtmospherePainter extends CustomPainter{
 const _AtmospherePainter({
  required this.accent,required this.season,required this.light});
 final Color accent;
 final SeasonChoice season;
 final bool light;
 @override void paint(Canvas canvas,Size size){
  final paint=Paint()..color=accent..style=PaintingStyle.fill;
  // Soft atmospheric glows, not a repeated stock-pattern background.
  final halo=Paint()..shader=RadialGradient(
   colors:[accent.withValues(alpha:light?.54:.32),Colors.transparent],
  ).createShader(Rect.fromCircle(
   center:Offset(size.width*.88,size.height*.09),
   radius:math.max(size.width,size.height)*.67));
  canvas.drawRect(Offset.zero&size,halo);
  if(season==SeasonChoice.off){
   for(var i=0;i<5;i++){
    final center=Offset(size.width*(.16+i*.19),size.height*(.10+i*.15));
    paint.style=PaintingStyle.stroke;paint.strokeWidth=1.15;
    canvas.drawCircle(center,18+i*10,paint);
   }
   return;
  }
  // Festive accents appear across the full viewport, but stay faint enough
  // behind readable foreground cards and inputs.
  for(var i=0;i<31;i++){
   final x=((i*73+29)%101)/101*size.width;
   final y=((i*149+43)%103)/103*size.height;
   final center=Offset(x,y);
   paint.style=PaintingStyle.stroke;paint.strokeWidth=1.1+(i%3)*.3;
   switch(season){
    case SeasonChoice.valentines:
     _heart(canvas,center,6+(i%4)*2,paint);
    case SeasonChoice.spring:
     _flower(canvas,center,5+(i%5)*1.6,paint);
    case SeasonChoice.halloween:
     _moon(canvas,center,5+(i%4)*3,paint);
    case SeasonChoice.winter:
     _snowflake(canvas,center,5+(i%4)*2,paint);
    case SeasonChoice.off:
    case SeasonChoice.automatic:
     break;
   }
  }
 }
 void _heart(Canvas canvas,Offset center,double size,Paint paint){
  final p=Path()..moveTo(center.dx,center.dy+size)
   ..cubicTo(center.dx-size*1.7,center.dy-size*.1,
    center.dx-size*.6,center.dy-size*.9,center.dx,center.dy-size*.2)
   ..cubicTo(center.dx+size*.6,center.dy-size*.9,
    center.dx+size*1.7,center.dy-size*.1,center.dx,center.dy+size);
  canvas.drawPath(p,paint);
 }
 void _flower(Canvas canvas,Offset c,double r,Paint paint){
  for(var k=0;k<5;k++){
   final a=k*math.pi*2/5;
   canvas.drawOval(Rect.fromCenter(
    center:Offset(c.dx+math.cos(a)*r*.75,c.dy+math.sin(a)*r*.75),
    width:r*1.25,height:r*.9),paint);
  }
  canvas.drawCircle(c,r*.24,paint);
 }
 void _moon(Canvas canvas,Offset c,double r,Paint paint){
  canvas.drawArc(Rect.fromCircle(center:c,radius:r),
   math.pi*.2,math.pi*1.6,false,paint);
  final p=Path()..moveTo(c.dx+r*.7,c.dy-r*.45)
   ..lineTo(c.dx+r*1.4,c.dy-r*.6)
   ..lineTo(c.dx+r*1.05,c.dy-r*.05)
   ..close();
  canvas.drawPath(p,paint);
 }
 void _snowflake(Canvas canvas,Offset c,double r,Paint paint){
  for(var k=0;k<3;k++){
   final a=k*math.pi/3;
   final delta=Offset(math.cos(a)*r,math.sin(a)*r);
   canvas.drawLine(c-delta,c+delta,paint);
  }
 }
 @override bool shouldRepaint(covariant _AtmospherePainter old)=>
  old.accent!=accent||old.season!=season||old.light!=light;
}
