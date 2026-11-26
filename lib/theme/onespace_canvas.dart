import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'onespace_appearance.dart';

/// Every route gets the same branded, season-aware background. Decorations
/// never intercept touches and do not include photos, user data or network IO.
class OneSpaceCanvas extends StatelessWidget{
 const OneSpaceCanvas({super.key,required this.child,required this.season,this.style=BackgroundStyle.calm});
 final Widget child;
 final SeasonChoice season;
 /// R64: the pattern used when no season is showing.
 final BackgroundStyle style;
 @override Widget build(BuildContext context){
  final theme=Theme.of(context);
  final tokens=theme.extension<OneSpaceVisualTokens>();
  if(tokens==null)return child;
  return Stack(fit:StackFit.expand,children:[
   DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(
    begin:AlignmentDirectional.topStart,end:AlignmentDirectional.bottomEnd,
    colors:[tokens.heroEnd,tokens.canvas,tokens.canvas]))),
   IgnorePointer(child:CustomPaint(
    painter:_AtmospherePainter(
     accent:tokens.motifColor,season:season,style:style,
     light:theme.brightness==Brightness.light))),
   child,
  ]);
 }
}

class _AtmospherePainter extends CustomPainter{
 const _AtmospherePainter({
  required this.accent,required this.season,required this.light,this.style=BackgroundStyle.calm});
 final Color accent;
 final SeasonChoice season;
 final BackgroundStyle style;
 final bool light;
 @override void paint(Canvas canvas,Size size){
  final paint=Paint()..color=accent..style=PaintingStyle.fill;
  // Soft atmospheric glows, not a repeated stock-pattern background.
  final halo=Paint()..shader=RadialGradient(
   colors:[accent.withValues(alpha:light ? .54 : .32),Colors.transparent],
  ).createShader(Rect.fromCircle(
   center:Offset(size.width*.88,size.height*.09),
   radius:math.max(size.width,size.height)*.67));
  canvas.drawRect(Offset.zero&size,halo);
  if(season==SeasonChoice.off||season==SeasonChoice.automatic){
   _background(canvas,size,paint);
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
    case SeasonChoice.christmas:
     _snowflake(canvas,center,5+(i%4)*2,paint);
    case SeasonChoice.birthday:
    case SeasonChoice.newYear:
     _flower(canvas,center,5+(i%4)*2,paint);
    case SeasonChoice.anniversary:
     _heart(canvas,center,5+(i%4)*2,paint);
    case SeasonChoice.thanksgiving:
     _flower(canvas,center,5+(i%4)*2,paint);
    case SeasonChoice.off:
    case SeasonChoice.automatic:
     break;
   }
  }
 }
 /// R64: everyday background patterns (faint, never behind text strongly).
 void _background(Canvas canvas,Size size,Paint paint){
  paint.style=PaintingStyle.stroke;
  switch(style){
   case BackgroundStyle.plain:
    return;
   case BackgroundStyle.calm:
    for(var i=0;i<5;i++){
     final center=Offset(size.width*(.16+i*.19),size.height*(.10+i*.15));
     paint.strokeWidth=1.15;
     canvas.drawCircle(center,18+i*10,paint);
    }
   case BackgroundStyle.hearts:
    for(var i=0;i<18;i++){
     paint.strokeWidth=1.1;
     _heart(canvas,_spot(i,size),5+(i%4)*2.5,paint);
    }
   case BackgroundStyle.stars:
    for(var i=0;i<34;i++){
     paint.strokeWidth=1;
     if(i%5==0){_moon(canvas,_spot(i,size),4+(i%3)*2,paint);}
     else{_star(canvas,_spot(i,size),2+(i%4)*1.2,paint);}
    }
   case BackgroundStyle.waves:
    paint.strokeWidth=1.3;
    for(var row=0;row<7;row++){
     final y=size.height*(.12+row*.13);
     final path=Path()..moveTo(0,y);
     for(double x=0;x<=size.width;x+=8){
      path.lineTo(x,y+math.sin((x/size.width)*math.pi*3+row)*10);
     }
     canvas.drawPath(path,paint);
    }
   case BackgroundStyle.pattern:
    paint.strokeWidth=.9;
    const step=74.0;
    for(double y=step/2;y<size.height+step;y+=step){
     for(double x=step/2;x<size.width+step;x+=step){
      _star8(canvas,Offset(x+((y/step).floor().isOdd?step/2:0),y),15,paint);
     }
    }
  }
 }
 Offset _spot(int i,Size size)=>Offset(((i*73+29)%101)/101*size.width,((i*149+43)%103)/103*size.height);
 void _star(Canvas canvas,Offset c,double r,Paint paint){
  final p=Path();
  for(var k=0;k<10;k++){
   final a=-math.pi/2+k*math.pi/5;
   final rr=k.isEven?r:r*.45;
   final pt=Offset(c.dx+math.cos(a)*rr,c.dy+math.sin(a)*rr);
   if(k==0){p.moveTo(pt.dx,pt.dy);}else{p.lineTo(pt.dx,pt.dy);}
  }
  canvas.drawPath(p..close(),paint);
 }
 /// Eight-pointed star (two overlapping squares), a classic arabesque motif.
 void _star8(Canvas canvas,Offset c,double r,Paint paint){
  for(final turn in [0.0,math.pi/4]){
   final p=Path();
   for(var k=0;k<4;k++){
    final a=turn+k*math.pi/2;
    final pt=Offset(c.dx+math.cos(a)*r,c.dy+math.sin(a)*r);
    if(k==0){p.moveTo(pt.dx,pt.dy);}else{p.lineTo(pt.dx,pt.dy);}
   }
   canvas.drawPath(p..close(),paint);
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
  old.accent!=accent||old.season!=season||old.light!=light||old.style!=style;
}
