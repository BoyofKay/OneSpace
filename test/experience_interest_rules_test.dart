import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/connect/experience_interest_rules.dart';

Map<String, dynamic> vote(String experience, String user, String choice) =>
    {'experience_id': experience, 'user_id': user, 'choice': choice};

void main() {
  test('both distinct partners must explicitly say yes', () {
    final votes = [vote('a', 'one', 'yes'), vote('a', 'two', 'maybe')];
    expect(ExperienceInterestRules.mutuallyInterested(votes, 'a'), isFalse);
    expect(ExperienceInterestRules.summary(votes, 'a'),
        'One partner interested');
    votes[1]['choice'] = 'yes';
    expect(ExperienceInterestRules.mutuallyInterested(votes, 'a'), isTrue);
    expect(ExperienceInterestRules.summary(votes, 'a'), 'Mutual pick');
    expect(ExperienceInterestRules.mutuallyInterested(votes, 'b'), isFalse);
  });

  test('repeated votes by the same user never count as agreement', () {
    final duplicates = [vote('a', 'one', 'yes'), vote('a', 'one', 'yes')];
    expect(ExperienceInterestRules.mutuallyInterested(duplicates, 'a'), false);
  });

  test('individual choices remain independent', () {
    final votes = [vote('a', 'one', 'yes'), vote('a', 'two', 'not_now')];
    expect(ExperienceInterestRules.choiceForUser(votes, 'a', 'one'), 'yes');
    expect(ExperienceInterestRules.choiceForUser(votes, 'a', 'two'), 'not_now');
    expect(ExperienceInterestRules.choiceForUser(votes, 'a', null), 'undecided');
    expect(ExperienceInterestRules.choiceForUser(votes, 'b', 'two'), 'undecided');
    expect(ExperienceInterestRules.summary(votes, 'a'),
        'One partner interested');
    expect(ExperienceInterestRules.summary([vote('a','one','maybe')], 'a'),
        'Still considering');
    expect(ExperienceInterestRules.summary([vote('a','one','not_now')], 'a'),
        'Not right now');
    expect(ExperienceInterestRules.summary([], 'a'), 'No picks yet');
  });

  test('mutual count excludes finished and archived experiences', () {
    final experiences = [
      {'id':'a','archived_at':null,'status':'suggested'},
      {'id':'b','archived_at':null,'status':'enjoyed'},
      {'id':'c','archived_at':'2026-11-14','status':'planned'},
    ];
    final votes = [
      vote('a', 'one', 'yes'), vote('a', 'two', 'yes'),
      vote('b', 'one', 'yes'), vote('b', 'two', 'yes'),
      vote('c', 'one', 'yes'), vote('c', 'two', 'yes'),
    ];
    expect(ExperienceInterestRules.mutualCount(experiences, votes), 1);
  });

  test('choice labels are stable', () {
    expect(ExperienceInterestRules.choices['yes'], 'Interested');
    expect(ExperienceInterestRules.choices['maybe'], 'Maybe');
    expect(ExperienceInterestRules.choices['not_now'], 'Not now');
    expect(ExperienceInterestRules.choices['undecided'], 'Clear pick');
  });
}
