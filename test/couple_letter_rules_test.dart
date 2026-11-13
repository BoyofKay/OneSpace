import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/connect/couple_letter_rules.dart';

void main(){
  final letters=<Map<String,dynamic>>[
    {'id':'my-draft','author_id':'me','status':'draft',
      'updated_at':'2026-11-13T18:00:00Z'},
    {'id':'my-sent','author_id':'me','status':'sent',
      'sent_at':'2026-11-11T11:00:00Z'},
    {'id':'received','author_id':'partner','status':'sent',
      'sent_at':'2026-11-12T11:00:00Z'},
  ];

  test('inbox does not leak private drafts',(){
    expect(CoupleLetterRules.filter(letters,'inbox','me')
      .map((v)=>v['id']),['received']);
    expect(CoupleLetterRules.filter(letters,'drafts','me')
      .map((v)=>v['id']),['my-draft']);
    expect(CoupleLetterRules.filter(letters,'sent','me')
      .map((v)=>v['id']),['my-sent']);
  });
  test('sending requires content; drafts may be empty',(){
    expect(CoupleLetterRules.validate('Hello','',sending:true),isNotNull);
    expect(CoupleLetterRules.validate('Hello','',sending:false),isNull);
    expect(CoupleLetterRules.validate('  ','Hi',sending:true),isNotNull);
    expect(CoupleLetterRules.validate('Hello','Hi',sending:true),isNull);
  });
  test('replies do not double-prefix titles',(){
    expect(CoupleLetterRules.replyTitle('A letter'),'Re: A letter');
    expect(CoupleLetterRules.replyTitle('Re: A letter'),'Re: A letter');
  });
  test('snippets are compact',(){
    expect(CoupleLetterRules.snippet('  hello\n\n  world  '),'hello world');
    expect(CoupleLetterRules.snippet('abcdef',max:4),'abc…');
  });
}
