import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/responsive_field_pair.dart';

void main(){
 testWidgets('Narrow form fields stack without overflow', (tester)async{
  await tester.pumpWidget(const MaterialApp(home:Scaffold(body:SizedBox(
   width:300,child:ResponsiveFieldPair(
    first:TextField(decoration:InputDecoration(labelText:'Cost')),
    second:TextField(decoration:InputDecoration(labelText:'Currency')),
   )))));
  expect(tester.takeException(),isNull);
  final inputs=find.byType(TextField);
  expect(inputs,findsNWidgets(2));
  final a=tester.getTopLeft(inputs.at(0));
  final b=tester.getTopLeft(inputs.at(1));
  expect(b.dy,greaterThan(a.dy));
 });
 testWidgets('Wide form fields share one row', (tester)async{
  await tester.pumpWidget(const MaterialApp(home:Scaffold(body:SizedBox(
   width:700,child:ResponsiveFieldPair(
    first:TextField(decoration:InputDecoration(labelText:'Cost')),
    second:TextField(decoration:InputDecoration(labelText:'Currency')),
   )))));
  expect(tester.takeException(),isNull);
  final inputs=find.byType(TextField);
  final a=tester.getTopLeft(inputs.at(0));
  final b=tester.getTopLeft(inputs.at(1));
  expect(b.dy,a.dy);
  expect(b.dx,greaterThan(a.dx));
 });
}
