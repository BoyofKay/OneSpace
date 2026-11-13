import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/core/back_exit_policy.dart';

void main(){
 test('A second back gesture inside the window exits',(){
   final guard=BackExitPolicy();
   final time=DateTime(2026,11,13,12);
   expect(guard.shouldExit(time),false);
   expect(guard.shouldExit(time.add(const Duration(milliseconds:1400))),true);
 });
 test('An expired confirmation window requires two new gestures',(){
   final guard=BackExitPolicy();
   final time=DateTime(2026,11,13,12);
   expect(guard.shouldExit(time),false);
   expect(guard.shouldExit(time.add(const Duration(seconds:3))),false);
   expect(guard.shouldExit(time.add(const Duration(seconds:4))),true);
 });
 test('Navigating to a tab or Profile resets the pending exit',(){
   final guard=BackExitPolicy();
   final time=DateTime(2026,11,13,12);
   expect(guard.shouldExit(time),false);
   guard.reset();
   expect(guard.shouldExit(time.add(const Duration(milliseconds:500))),false);
 });
}
