import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/world/trip_document_rules.dart';

void main(){
 test('Document signatures, not filenames, determine allowed type',(){
  expect(TripDocumentRules.validatedMime(Uint8List.fromList([37,80,68,70,45,49,46,55])),
   'application/pdf');
  expect(TripDocumentRules.detectMime(Uint8List.fromList([0xff,0xd8,0xff])),
   'image/jpeg');
  expect(TripDocumentRules.detectMime(Uint8List.fromList([1,2,3])),isNull);
 });
 test('Oversize and empty files are rejected',(){
  expect(()=>TripDocumentRules.validatedMime(Uint8List(0)),throwsFormatException);
  expect(()=>TripDocumentRules.validatedMime(Uint8List(TripDocumentRules.maxBytes+1)),
   throwsFormatException);
 });
 test('Private object paths bind trip, contributor and random document id',(){
  const trip='9e95000d-f709-4cdf-bc5d-51493abc1001';
  const user='29a08125-7444-430e-84b0-acb3a11001a1';
  const document='bde01b2c-4af1-423d-9b51-41120f64c001';
  expect(TripDocumentRules.path(tripId:trip,userId:user,
    documentId:document,mime:'application/pdf'),
    '$trip/$user/$document.pdf');
  expect(()=>TripDocumentRules.path(tripId:'../../other',userId:user,
    documentId:document,mime:'application/pdf'),throwsFormatException);
 });
 test('Filename is sanitized before entering metadata',(){
  expect(TripDocumentRules.safeFileName(' ../board/pass.pdf'), '..-board-pass.pdf');
  expect(TripDocumentRules.safeTitle('   '),'Travel document');
 });
}
