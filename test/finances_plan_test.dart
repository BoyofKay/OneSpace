import 'package:flutter_test/flutter_test.dart';
import 'package:onespace/features/finances/fin_money.dart';
import 'package:onespace/features/finances/fin_plan.dart';

/// 28 Nov 2026 (D110+): every money calculation of Finances is exact and tested.
Amount a(String s) => Amount.parse(s);

Obligation plan({
  String id = 'p',
  String currency = 'USD',
  String amount = '100',
  Day? first,
  Frequency frequency = Frequency.monthly,
  int interval = 1,
  int? dueDay,
  int? secondDueDay,
  ChangeKind change = ChangeKind.none,
  String? changeAmount,
  String? changePercent,
  int changeEvery = 12,
  String? balloon,
  EndKind end = EndKind.afterCount,
  Day? endOn,
  int? count = 12,
  int paidBefore = 0,
  bool autoPaid = false,
  Day? pausedOn,
  ObligationKind kind = ObligationKind.installment,
}) =>
    Obligation(
      id: id,
      kind: kind,
      title: id,
      currency: currency,
      amount: a(amount),
      firstDue: first ?? Day(2026, 1, 15),
      frequency: frequency,
      intervalMonths: interval,
      dueDay: dueDay,
      secondDueDay: secondDueDay,
      changeKind: change,
      changeAmount: changeAmount == null ? null : a(changeAmount),
      changePercent: changePercent == null ? null : Percent.parse(changePercent),
      changeEveryMonths: changeEvery,
      balloon: balloon == null ? null : a(balloon),
      endKind: end,
      endOn: endOn,
      paymentCount: count,
      paidBeforeCount: paidBefore,
      autoPaid: autoPaid,
      pausedOn: pausedOn,
    );

Confirmation rec(int n, Day due, String expected, ConfirmKind kind, {String? actual, List<Correction> corrections = const []}) =>
    Confirmation(id: 'r$n${kind.name}$actual', number: n, due: due, expected: a(expected), kind: kind,
        actual: actual == null ? null : a(actual), corrections: corrections);

void main() {
  group('Amount (exact decimals)', () {
    test('parses and prints without doubles', () {
      expect(a('0.1') + a('0.2'), a('0.3'));
      expect(a('1,234.5').toDb(), '1234.5000');
      expect(a('-12.3456').toDb(), '-12.3456');
      expect(a('12.50000').toDb(), '12.5000');
      expect(a('٣٤٥٫٧٥'), a('345.75'));
      expect(() => a('1.23456'), throwsFormatException);
      expect(() => a('abc'), throwsFormatException);
      expect(Amount.tryParse(''), isNull);
      expect(a('99999999999.9999').toDb(), '99999999999.9999');
    });
    test('rounds half away from zero to the currency decimals', () {
      expect(a('2.345').rounded(2), a('2.35'));
      expect(a('-2.345').rounded(2), a('-2.35'));
      expect(a('2.3449').rounded(2), a('2.34'));
      expect(a('1234.5').format(0), '1,235');
      expect(a('1234567.891').format(3), '1,234,567.891');
      expect(a('0.5').format(2), '0.50');
      expect(a('12.5').toInput(), '12.5');
      expect(a('12').toInput(), '12');
    });
    test('currency decimals', () {
      expect(currencyDecimals('USD'), 2);
      expect(currencyDecimals('kwd'), 3);
      expect(currencyDecimals('JPY'), 0);
    });
    test('totals never mix currencies', () {
      final t = CurrencyTotals()..add('USD', a('10'))..add('SAR', a('5'))..add('usd', a('2.5'));
      expect(t.of('USD'), a('12.5'));
      expect(t.of('SAR'), a('5'));
      expect(t.currencies, ['SAR', 'USD']);
    });
  });

  group('Schedules', () {
    test('monthly on day 31 clamps to short months', () {
      final o = plan(first: Day(2026, 1, 31), count: 4);
      expect(occurrences(o).map((e) => e.due.toDb()), ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30']);
    });
    test('weekly and every two weeks', () {
      expect(occurrences(plan(frequency: Frequency.weekly, count: 3)).map((e) => e.due.toDb()),
          ['2026-01-15', '2026-01-22', '2026-01-29']);
      expect(occurrences(plan(frequency: Frequency.biweekly, count: 3)).map((e) => e.due.toDb()),
          ['2026-01-15', '2026-01-29', '2026-02-12']);
    });
    test('twice a month (1st and 15th)', () {
      final o = plan(first: Day(2026, 1, 15), frequency: Frequency.semimonthly, dueDay: 15, secondDueDay: 1, count: 5);
      expect(occurrences(o).map((e) => e.due.toDb()),
          ['2026-01-15', '2026-02-01', '2026-02-15', '2026-03-01', '2026-03-15']);
    });
    test('bills every 2 or 3 months', () {
      expect(occurrences(plan(frequency: Frequency.everyMonths, interval: 2, count: 3)).map((e) => e.due.toDb()),
          ['2026-01-15', '2026-03-15', '2026-05-15']);
      expect(occurrences(plan(frequency: Frequency.everyMonths, interval: 3, count: 3)).map((e) => e.due.toDb()),
          ['2026-01-15', '2026-04-15', '2026-07-15']);
    });
    test('end by date, by count, never, once', () {
      expect(occurrences(plan(end: EndKind.onDate, endOn: Day(2026, 4, 15), count: null)).length, 4);
      expect(plan(end: EndKind.onDate, endOn: Day(2026, 4, 14), count: null).totalCount, 3);
      expect(occurrences(plan(count: 6)).length, 6);
      final open = plan(end: EndKind.never, count: null);
      expect(open.totalCount, isNull);
      expect(occurrences(open, until: Day(2026, 12, 31)).length, 12);
      expect(occurrences(plan(frequency: Frequency.once, end: EndKind.never, count: null)).length, 1);
    });
    test('paused subscriptions expect nothing from the pause', () {
      final o = plan(end: EndKind.never, count: null, pausedOn: Day(2026, 3, 1), kind: ObligationKind.bill);
      expect(occurrences(o, until: Day(2026, 12, 31)).length, 2);
    });
  });

  group('Amount rules', () {
    test('fixed', () {
      expect(occurrences(plan(count: 3)).map((e) => e.expected), [a('100'), a('100'), a('100')]);
    });
    test('rises 10% every year (insurance), compounded, rounded per payment', () {
      final o = plan(amount: '1000', change: ChangeKind.byPercent, changePercent: '10', count: 37);
      final occ = occurrences(o);
      expect(occ[0].expected, a('1000'));
      expect(occ[11].expected, a('1000'));
      expect(occ[12].expected, a('1100'));
      expect(occ[24].expected, a('1210'));
      expect(occ[36].expected, a('1331'));
    });
    test('percent with odd amounts stays exact', () {
      final o = plan(amount: '333.33', change: ChangeKind.byPercent, changePercent: '7.5', count: 25);
      expect(occurrences(o)[12].expected, a('358.33')); // 358.329750 → 358.33
      expect(occurrences(o)[24].expected, a('385.20')); // 385.204481… → 385.20
    });
    test('falls by an amount every 6 months, never below zero', () {
      final o = plan(amount: '100', change: ChangeKind.byAmount, changeAmount: '-40', changeEvery: 6, count: 19);
      final occ = occurrences(o);
      expect(occ[5].expected, a('100'));
      expect(occ[6].expected, a('60'));
      expect(occ[12].expected, a('20'));
      expect(occ[18].expected, Amount.zero);
    });
    test('falls by a percent', () {
      final o = plan(amount: '200', change: ChangeKind.byPercent, changePercent: '-5', count: 13);
      expect(occurrences(o)[12].expected, a('190'));
    });
    test('balloon final payment', () {
      final o = plan(amount: '250', balloon: '5000', count: 4);
      expect(occurrences(o).map((e) => e.expected), [a('250'), a('250'), a('250'), a('5000')]);
    });
    test('three-decimal currency rounding', () {
      final o = plan(currency: 'KWD', amount: '10.125', change: ChangeKind.byPercent, changePercent: '3.3', count: 13);
      expect(occurrences(o)[12].expected, a('10.459')); // 10.459125 → 10.459
    });
  });

  group('Payment status', () {
    final today = Day(2026, 3, 20);
    test('paid, partial, not done, overdue, due today, upcoming', () {
      final o = plan(count: 6);
      final recs = [
        rec(1, Day(2026, 1, 15), '100', ConfirmKind.done),
        rec(2, Day(2026, 2, 15), '100', ConfirmKind.partial, actual: '40'),
      ];
      final s = paymentStates(o, recs, today);
      expect(s.map((e) => e.status), [PayStatus.paid, PayStatus.partial, PayStatus.overdue,
        PayStatus.upcoming, PayStatus.upcoming, PayStatus.upcoming]);
      expect(s[1].remaining, a('60'));
      expect(paymentStates(o, recs, Day(2026, 3, 15))[2].status, PayStatus.dueToday);
      final notDone = paymentStates(o, [rec(1, Day(2026, 1, 15), '100', ConfirmKind.notDone)], today);
      expect(notDone.first.status, PayStatus.notDone);
      expect(notDone.first.remaining, a('100'));
    });
    test('two partial payments that add up settle the payment', () {
      final o = plan(count: 2);
      final s = paymentStates(o, [
        rec(1, Day(2026, 1, 15), '100', ConfirmKind.partial, actual: '60'),
        rec(1, Day(2026, 1, 15), '100', ConfirmKind.partial, actual: '40'),
      ], today);
      expect(s.first.status, PayStatus.paid);
      expect(s.first.remaining, Amount.zero);
    });
    test('auto-paid bills wait for a done mark after the date', () {
      final o = plan(autoPaid: true, kind: ObligationKind.bill, count: 4);
      final s = paymentStates(o, const [], today);
      expect(s[0].status, PayStatus.awaitingMark);
      expect(s[3].status, PayStatus.upcoming);
    });
    test('opening position: payments already made are not invented as records', () {
      final o = plan(count: 10, paidBefore: 2);
      final s = paymentStates(o, const [], today);
      expect(s[0].status, PayStatus.paidBefore);
      expect(s[1].status, PayStatus.paidBefore);
      expect(s[2].status, PayStatus.overdue);
      expect(suggestedPaidBefore(o, today), 3);
    });
    test('confirmed records keep their snapshot when the plan changes later (A9)', () {
      final before = plan(amount: '100', count: 3);
      final recs = [rec(1, Day(2026, 1, 15), '100', ConfirmKind.done)];
      final after = plan(amount: '150', count: 3); // owner edits the amount later
      final s = paymentStates(after, recs, today);
      expect(s[0].expected, a('100'));
      expect(s[0].paid, a('100'));
      expect(s[1].expected, a('150'));
      expect(paymentStates(before, recs, today)[1].expected, a('100'));
    });
    test('corrections replace status and amount without editing the record', () {
      final o = plan(count: 2);
      final r = rec(1, Day(2026, 1, 15), '100', ConfirmKind.done,
          corrections: [const Correction(kind: ConfirmKind.partial, reason: 'bank reversed part')]);
      // a partial correction without an amount means nothing was paid
      expect(paymentStates(o, [r], today).first.status, PayStatus.partial);
      final r2 = rec(1, Day(2026, 1, 15), '100', ConfirmKind.done,
          corrections: [Correction(kind: ConfirmKind.partial, actual: a('70'))]);
      final s = paymentStates(o, [r2], today).first;
      expect(s.paid, a('70'));
      expect(s.remaining, a('30'));
    });
    test('confirmed actual amount replaces the expected one for that payment only', () {
      final o = plan(kind: ObligationKind.bill, count: 3);
      final s = paymentStates(o, [rec(1, Day(2026, 1, 15), '100', ConfirmKind.done, actual: '112.40')], today);
      expect(s[0].paid, a('112.40'));
      expect(s[1].expected, a('100'));
    });
    test('summary counts', () {
      final o = plan(count: 6, paidBefore: 1);
      final sum = summarize(o, [rec(2, Day(2026, 2, 15), '100', ConfirmKind.partial, actual: '30')], today);
      expect(sum.paidCount, 1);
      expect(sum.partialCount, 1);
      expect(sum.overdueCount, 1);
      expect(sum.unpaidCount, 5);
      expect(sum.remainingAmount, a('470'));
      expect(sum.paidAmount, a('130'));
      expect(sum.endsOn, Day(2026, 6, 15));
    });
    test('next open payment', () {
      final o = plan(count: 3);
      expect(nextOpen(o, [rec(1, Day(2026, 1, 15), '100', ConfirmKind.done)], today)!.occurrence.number, 2);
      expect(nextOpen(o, [
        rec(1, Day(2026, 1, 15), '100', ConfirmKind.done),
        rec(2, Day(2026, 2, 15), '100', ConfirmKind.done),
        rec(3, Day(2026, 3, 15), '100', ConfirmKind.done),
      ], today), isNull);
    });
  });

  group('Combined payment split (A17)', () {
    test('parts must add up exactly', () {
      final ok = CombinedSplit(a('300'), [SplitPart('x', 1, a('120.50')), SplitPart('y', 1, a('179.50'))]);
      expect(ok.isValid, isTrue);
      final short = CombinedSplit(a('300'), [SplitPart('x', 1, a('100'))]);
      expect(short.problem, 'The parts must add up to the total.');
      expect(short.unassigned, a('200'));
      expect(CombinedSplit(a('100'), [SplitPart('x', 1, a('50')), SplitPart('x', 1, a('50'))]).problem,
          'A payment is listed twice.');
      expect(CombinedSplit(a('0'), const []).isValid, isFalse);
      expect(CombinedSplit(a('10'), [SplitPart('x', 1, a('-5')), SplitPart('y', 1, a('15'))]).isValid, isFalse);
    });
    test('a part becomes done or partial', () {
      expect(kindForPart(a('100'), a('100')), ConfirmKind.done);
      expect(kindForPart(a('99.99'), a('100')), ConfirmKind.partial);
    });
  });

  group('Freedom Timeline and debt-free total', () {
    final today = Day(2026, 3, 20);
    test('monthly equivalents', () {
      expect(monthlyEquivalent(a('100'), Frequency.weekly, 1, 2), a('433.33'));
      expect(monthlyEquivalent(a('100'), Frequency.biweekly, 1, 2), a('216.67'));
      expect(monthlyEquivalent(a('100'), Frequency.semimonthly, 1, 2), a('200'));
      expect(monthlyEquivalent(a('300'), Frequency.everyMonths, 3, 2), a('100'));
      expect(monthlyEquivalent(a('300'), Frequency.once, 1, 2), Amount.zero);
    });
    test('ordered by end date with room freed, remaining and debt-free day', () {
      final car = plan(id: 'car', amount: '500', count: 6); // ends 2026-06-15
      final phone = plan(id: 'phone', amount: '50', first: Day(2026, 2, 1), count: 3); // ends 2026-04-01
      final loan = plan(id: 'loan', currency: 'SAR', amount: '1000', balloon: '3000', count: 12); // ends 2026-12-15
      final open = plan(id: 'rent', end: EndKind.never, count: null, kind: ObligationKind.bill);
      final done = plan(id: 'done', count: 1, first: Day(2026, 1, 1));
      final t = freedomTimeline([
        (car, [rec(1, Day(2026, 1, 15), '500', ConfirmKind.done)]),
        (phone, const <Confirmation>[]),
        (loan, const <Confirmation>[]),
        (open, const <Confirmation>[]),
        (done, [rec(1, Day(2026, 1, 1), '100', ConfirmKind.done)]),
      ], today);
      expect(t.map((p) => p.obligation.id), ['phone', 'car', 'loan']);
      expect(t[0].monthlyRoom, a('50'));
      expect(t[1].remaining, a('2500'));
      expect(t[1].paymentsLeft, 5);
      expect(t[2].monthlyRoom, a('1000')); // the regular payment, not the balloon
      expect(t[2].remaining, a('14000'));
      final d = debtFree(t);
      expect(d.lastDay, Day(2026, 12, 15));
      expect(d.remaining.of('USD'), a('2650'));
      expect(d.remaining.of('SAR'), a('14000'));
      expect(d.monthlyRoom.of('USD'), a('550'));
      final run = cumulativeRoom(t);
      expect(run[1].of('USD'), a('550'));
      expect(run[2].of('SAR'), a('1000'));
    });
  });

  group('Reminders', () {
    test('before the due day, never in the past', () {
      final o = plan(count: 3);
      final r = reminderFor(o, const [], Day(2026, 1, 1), daysBefore: 3)!;
      expect(r.on, Day(2026, 1, 12));
      expect(r.afterDue, isFalse);
      expect(reminderFor(o, const [], Day(2026, 1, 14), daysBefore: 3)!.on, Day(2026, 1, 14));
    });
    test('auto-paid: the day after the due day', () {
      final o = plan(autoPaid: true, kind: ObligationKind.bill, count: 3);
      final r = reminderFor(o, const [], Day(2026, 1, 1))!;
      expect(r.on, Day(2026, 1, 16));
      expect(r.afterDue, isTrue);
    });
    test('no reminder when everything is settled', () {
      final o = plan(count: 1, first: Day(2026, 1, 1));
      expect(reminderFor(o, [rec(1, Day(2026, 1, 1), '100', ConfirmKind.done)], Day(2026, 1, 5)), isNull);
    });
  });
}
