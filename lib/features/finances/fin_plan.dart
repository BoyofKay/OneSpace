/// OneSpace Finances (28 Nov 2026, D110+): every money calculation in one
/// pure library — no Flutter, no database, no doubles. The screens and the
/// reminders only call into this file; the unit tests cover it.
///
/// * [Obligation] — a bill or an installment plan, with its schedule rule
///   and amount rule.
/// * [occurrences] — each expected payment (date + expected amount).
/// * [paymentStates] — paid / partial / unpaid / overdue per payment, from the
///   confirmed records (which are never changed, A9) and today's date.
/// * [CombinedSplit] — one payment split across plans by the user (A17).
/// * [freedomTimeline], [debtFree] — when each plan ends, the monthly room it
///   frees and the total still to pay.
library;

import 'fin_money.dart';

/// A calendar day without a time or time zone.
class Day implements Comparable<Day> {
  Day(int year, int month, int day) : _d = DateTime.utc(year, month, day);
  Day._(this._d);
  final DateTime _d;

  factory Day.fromDateTime(DateTime t) => Day(t.year, t.month, t.day);
  static Day parse(String s) => Day.fromDateTime(DateTime.parse(s.length >= 10 ? s.substring(0, 10) : s));
  static Day? tryParse(Object? s) {
    if (s == null) return null;
    try {
      return parse(s.toString());
    } on FormatException {
      return null;
    }
  }

  int get year => _d.year;
  int get month => _d.month;
  int get day => _d.day;
  int get weekday => _d.weekday;
  DateTime get asUtc => _d;

  Day addDays(int n) => Day._(_d.add(Duration(days: n)));

  /// Same day-of-month [months] later; clamped to the month's last day.
  Day addMonths(int months, {int? dayOfMonth}) {
    final total = year * 12 + (month - 1) + months;
    final y = total ~/ 12;
    final m = total % 12 + 1;
    final want = dayOfMonth ?? day;
    return Day(y, m, want.clamp(1, daysInMonth(y, m)));
  }

  int daysUntil(Day other) => other._d.difference(_d).inDays;

  /// Whole months from this day to [later] (by calendar, day-of-month aware).
  int wholeMonthsUntil(Day later) {
    var months = (later.year - year) * 12 + (later.month - month);
    if (later.day < day && later.day < daysInMonth(later.year, later.month)) months--;
    return months;
  }

  static int daysInMonth(int y, int m) => DateTime.utc(y, m + 1, 0).day;

  bool isBefore(Day o) => _d.isBefore(o._d);
  bool isAfter(Day o) => _d.isAfter(o._d);
  @override
  int compareTo(Day o) => _d.compareTo(o._d);
  @override
  bool operator ==(Object o) => o is Day && o._d == _d;
  @override
  int get hashCode => _d.hashCode;
  String toDb() => '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  @override
  String toString() => toDb();
}

enum ObligationKind { bill, installment }

/// How often a payment is due (A7 frequencies; bills every 2 or 3 months
/// from the owner's sheet use [everyMonths] with an interval).
enum Frequency { once, weekly, biweekly, semimonthly, monthly, everyMonths }

/// Bills: a fixed amount, an estimate, or a budget the bill must stay under.
enum AmountKind { fixed, estimated, budget }

/// Installments (and bills) whose amount rises or falls over time.
enum ChangeKind { none, byAmount, byPercent }

enum EndKind { never, onDate, afterCount }

String frequencyKey(Frequency f) => switch (f) {
      Frequency.once => 'once',
      Frequency.weekly => 'weekly',
      Frequency.biweekly => 'biweekly',
      Frequency.semimonthly => 'semimonthly',
      Frequency.monthly => 'monthly',
      Frequency.everyMonths => 'every_months',
    };
Frequency frequencyFromKey(String? k) => Frequency.values.firstWhere(
    (f) => frequencyKey(f) == k, orElse: () => Frequency.monthly);
String amountKindKey(AmountKind k) => k.name;
AmountKind amountKindFromKey(String? k) =>
    AmountKind.values.firstWhere((x) => x.name == k, orElse: () => AmountKind.fixed);
String changeKindKey(ChangeKind k) => switch (k) {
      ChangeKind.none => 'none',
      ChangeKind.byAmount => 'amount',
      ChangeKind.byPercent => 'percent',
    };
ChangeKind changeKindFromKey(String? k) => ChangeKind.values.firstWhere(
    (x) => changeKindKey(x) == k, orElse: () => ChangeKind.none);
String endKindKey(EndKind k) => switch (k) {
      EndKind.never => 'never',
      EndKind.onDate => 'date',
      EndKind.afterCount => 'count',
    };
EndKind endKindFromKey(String? k) =>
    EndKind.values.firstWhere((x) => endKindKey(x) == k, orElse: () => EndKind.never);

/// A bill or an installment plan, exactly as set up by its owner.
class Obligation {
  Obligation({
    required this.id,
    required this.kind,
    required this.title,
    required this.currency,
    required this.amount,
    required this.firstDue,
    this.frequency = Frequency.monthly,
    this.intervalMonths = 1,
    int? dueDay,
    this.secondDueDay,
    this.amountKind = AmountKind.fixed,
    this.changeKind = ChangeKind.none,
    Amount? changeAmount,
    Percent? changePercent,
    this.changeEveryMonths = 12,
    this.balloon,
    this.endKind = EndKind.never,
    this.endOn,
    this.paymentCount,
    this.paidBeforeCount = 0,
    this.autoPaid = false,
    this.pausedOn,
    this.providerId,
    this.category,
  })  : dueDay = dueDay ?? firstDue.day,
        changeAmount = changeAmount ?? Amount.zero,
        changePercent = changePercent ?? Percent.zero;

  final String id;
  final ObligationKind kind;
  final String title;
  final String currency;

  /// The first regular amount (before any rise or fall).
  final Amount amount;

  /// The date of payment number 1 — for plans that started before today,
  /// the original first payment (A16, opening position).
  final Day firstDue;
  final Frequency frequency;

  /// For [Frequency.everyMonths]: 2 = every two months, 3 = quarterly …
  final int intervalMonths;

  /// Day of the month for monthly schedules (31 = last day of short months).
  final int dueDay;

  /// The second day for [Frequency.semimonthly] (e.g. 1 and 15).
  final int? secondDueDay;
  final AmountKind amountKind;
  final ChangeKind changeKind;
  final Amount changeAmount;
  final Percent changePercent;

  /// The amount changes once every this many months, counted from [firstDue].
  final int changeEveryMonths;

  /// A different (usually larger) final payment.
  final Amount? balloon;
  final EndKind endKind;
  final Day? endOn;
  final int? paymentCount;

  /// Payments already made before the plan was added (A16). They are not
  /// invented as records; they only mark the first N payments as done.
  final int paidBeforeCount;

  /// Paid automatically by the bank: after the date the owner only marks it done.
  final bool autoPaid;

  /// Paused but kept (subscriptions): no payments are expected from this day.
  final Day? pausedOn;
  final String? providerId;
  final String? category;

  int get decimals => currencyDecimals(currency);
  bool get isFinite => endKind != EndKind.never || frequency == Frequency.once;

  /// Total number of payments, when the plan has an end (null = open-ended).
  int? get totalCount => _total;
  late final int? _total = _countPayments();
  int? _countPayments() {
    if (frequency == Frequency.once) return 1;
    switch (endKind) {
      case EndKind.afterCount:
        return paymentCount;
      case EndKind.onDate:
        var n = 0;
        for (final d in _dates()) {
          if (d.isAfter(endOn!)) break;
          n++;
          if (n > maxOccurrences) break;
        }
        return n;
      case EndKind.never:
        return null;
    }
  }

  /// A safety limit so a wrong setup can never loop forever.
  static const maxOccurrences = 2400;

  /// Every due date of the schedule, in order, without the end rule.
  Iterable<Day> _dates() sync* {
    switch (frequency) {
      case Frequency.once:
        yield firstDue;
        return;
      case Frequency.weekly:
      case Frequency.biweekly:
        final step = frequency == Frequency.weekly ? 7 : 14;
        for (var i = 0;; i++) {
          yield firstDue.addDays(step * i);
        }
      case Frequency.monthly:
      case Frequency.everyMonths:
        final every = frequency == Frequency.monthly ? 1 : intervalMonths.clamp(1, 120);
        yield firstDue;
        for (var i = 1;; i++) {
          yield firstDue.addMonths(every * i, dayOfMonth: dueDay);
        }
      case Frequency.semimonthly:
        final a = dueDay, b = secondDueDay ?? (dueDay <= 15 ? dueDay + 15 : dueDay - 15);
        final days = [a, b]..sort();
        yield firstDue;
        var y = firstDue.year, m = firstDue.month;
        var last = firstDue;
        while (true) {
          for (final d in days) {
            final c = Day(y, m, d.clamp(1, Day.daysInMonth(y, m)));
            if (c.isAfter(last)) {
              last = c;
              yield c;
            }
          }
          m++;
          if (m > 12) {
            m = 1;
            y++;
          }
        }
    }
  }

  /// The amount rule: the expected amount of payment [number] (1-based) due on [due].
  Amount expectedAmount(int number, Day due) {
    final total = totalCount;
    if (balloon != null && total != null && number == total && total > 1) return balloon!;
    final steps = changeKind == ChangeKind.none
        ? 0
        : (firstDue.wholeMonthsUntil(due) ~/ changeEveryMonths.clamp(1, 1200)).clamp(0, 1200);
    Amount value;
    switch (changeKind) {
      case ChangeKind.none:
        value = amount;
      case ChangeKind.byAmount:
        value = amount + changeAmount.times(steps);
      case ChangeKind.byPercent:
        // amount × (1 + p/100)^steps, exact, rounded once.
        final p = changePercent.units; // ten-thousandths of a percent point
        final base = BigInt.from(1000000); // 100% in the same units
        value = amount.mulDiv((base + p).pow(steps), base.pow(steps), decimals);
    }
    value = value.rounded(decimals);
    return value.isNegative ? Amount.zero : value;
  }
}

/// One expected payment of a plan.
class Occurrence {
  const Occurrence(this.number, this.due, this.expected);
  final int number; // 1-based
  final Day due;
  final Amount expected;
  @override
  String toString() => '#$number $due $expected';
}

/// The schedule's payments from number 1 up to [until] (inclusive) or the
/// plan's end, whichever comes first. Paused plans stop before [Obligation.pausedOn].
List<Occurrence> occurrences(Obligation o, {Day? until, int? limit}) {
  final out = <Occurrence>[];
  final total = o.totalCount;
  var n = 0;
  for (final d in o._dates()) {
    n++;
    if (total != null && n > total) break;
    if (o.endKind == EndKind.onDate && o.endOn != null && d.isAfter(o.endOn!)) break;
    if (until != null && d.isAfter(until)) break;
    if (o.pausedOn != null && !d.isBefore(o.pausedOn!)) break;
    out.add(Occurrence(n, d, o.expectedAmount(n, d)));
    if (limit != null && out.length >= limit) break;
    if (n >= Obligation.maxOccurrences) break;
  }
  return out;
}

/// What the owner confirmed (A8): done, not done, or partly paid.
enum ConfirmKind { done, notDone, partial }

String confirmKindKey(ConfirmKind k) => switch (k) {
      ConfirmKind.done => 'done',
      ConfirmKind.notDone => 'not_done',
      ConfirmKind.partial => 'partial',
    };
ConfirmKind confirmKindFromKey(String? k) =>
    ConfirmKind.values.firstWhere((x) => confirmKindKey(x) == k, orElse: () => ConfirmKind.done);

/// A confirmed record. Never edited (A9): a correction is a new
/// [Correction] that replaces its status and amount.
class Confirmation {
  Confirmation({
    required this.id,
    required this.number,
    required this.due,
    required this.expected,
    required this.kind,
    this.actual,
    this.combinedId,
    this.corrections = const [],
  });
  final String id;
  final int number;
  final Day due;

  /// Snapshot of the expected amount when it was confirmed (later setup
  /// changes never alter it).
  final Amount expected;
  final ConfirmKind kind;
  final Amount? actual;
  final String? combinedId;
  final List<Correction> corrections;

  ConfirmKind get effectiveKind => corrections.isEmpty ? kind : corrections.last.kind;

  /// The amount actually paid by this record (after the latest correction).
  Amount get paid {
    final k = effectiveKind;
    final a = corrections.isEmpty ? actual : corrections.last.actual;
    if (k == ConfirmKind.notDone) return Amount.zero;
    if (k == ConfirmKind.done) return a ?? expected;
    return a ?? Amount.zero;
  }
}

class Correction {
  const Correction({required this.kind, this.actual, this.reason});
  final ConfirmKind kind;
  final Amount? actual;
  final String? reason;
}

enum PayStatus {
  /// Made before the plan was added (opening position, A16).
  paidBefore,
  paid,
  partial,
  /// Confirmed as not done.
  notDone,
  upcoming,
  dueToday,
  overdue,
  /// Auto-paid and the date has passed: waiting for the owner's "done" mark.
  awaitingMark,
}

class PaymentState {
  const PaymentState(this.occurrence, this.status, this.paid, this.records);
  final Occurrence occurrence;
  final PayStatus status;
  final Amount paid;
  final List<Confirmation> records;

  /// The expected amount for this payment; once confirmed, the snapshot taken
  /// at the time — so later changes to the plan never rewrite it (A9).
  Amount get expected => records.isEmpty ? occurrence.expected : records.first.expected;

  /// What is still owed on this payment (zero when settled).
  Amount get remaining {
    if (status == PayStatus.paidBefore || status == PayStatus.paid) return Amount.zero;
    final r = expected - paid;
    return r.isNegative ? Amount.zero : r;
  }

  bool get settled => status == PayStatus.paidBefore || status == PayStatus.paid;
  bool get isOpen => !settled;
}

/// Paid / partial / unpaid / overdue for every payment up to [until].
List<PaymentState> paymentStates(Obligation o, List<Confirmation> records, Day today, {Day? until}) {
  final byNumber = <int, List<Confirmation>>{};
  for (final r in records) {
    byNumber.putIfAbsent(r.number, () => []).add(r);
  }
  final out = <PaymentState>[];
  for (final occ in occurrences(o, until: until)) {
    final recs = byNumber[occ.number] ?? const <Confirmation>[];
    if (occ.number <= o.paidBeforeCount && recs.isEmpty) {
      out.add(PaymentState(occ, PayStatus.paidBefore, occ.expected, recs));
      continue;
    }
    if (recs.isNotEmpty) {
      final expected = recs.first.expected;
      var paid = Amount.zero;
      var anyDone = false;
      var allNotDone = true;
      for (final r in recs) {
        paid += r.paid;
        if (r.effectiveKind == ConfirmKind.done) anyDone = true;
        if (r.effectiveKind != ConfirmKind.notDone) allNotDone = false;
      }
      final PayStatus s;
      if (anyDone || (paid >= expected && expected.isPositive)) {
        s = PayStatus.paid;
      } else if (allNotDone) {
        s = PayStatus.notDone;
      } else {
        s = PayStatus.partial;
      }
      out.add(PaymentState(occ, s, paid, recs));
      continue;
    }
    final PayStatus s;
    if (occ.due.isAfter(today)) {
      s = PayStatus.upcoming;
    } else if (occ.due == today) {
      s = PayStatus.dueToday;
    } else {
      s = o.autoPaid ? PayStatus.awaitingMark : PayStatus.overdue;
    }
    out.add(PaymentState(occ, s, Amount.zero, recs));
  }
  return out;
}

/// The next payment that still needs the owner (open, earliest first).
PaymentState? nextOpen(Obligation o, List<Confirmation> records, Day today) {
  final horizon = today.addMonths(36);
  for (final s in paymentStates(o, records, today, until: horizon)) {
    if (s.isOpen && s.status != PayStatus.notDone) return s;
  }
  return null;
}

/// Counts for the Installments view.
class PlanSummary {
  PlanSummary(this.obligation, this.states);
  final Obligation obligation;
  final List<PaymentState> states;

  int get paidCount => states.where((s) => s.settled).length;
  int get overdueCount => states
      .where((s) => s.status == PayStatus.overdue || s.status == PayStatus.notDone || s.status == PayStatus.awaitingMark)
      .length;
  int get partialCount => states.where((s) => s.status == PayStatus.partial).length;
  int get unpaidCount => states.where((s) => s.isOpen).length;
  int? get totalCount => obligation.totalCount;
  Amount get paidAmount => states.fold(Amount.zero, (a, s) => a + (s.settled ? s.expected.max(s.paid) : s.paid));
  Amount get remainingAmount => states.fold(Amount.zero, (a, s) => a + s.remaining);
  Day? get endsOn => states.isEmpty ? null : states.last.occurrence.due;
}

/// Summary of a plan over its whole life (finite plans) or the next
/// [openEndedMonths] months (open-ended bills).
PlanSummary summarize(Obligation o, List<Confirmation> records, Day today, {int openEndedMonths = 12}) {
  final until = o.isFinite ? null : today.addMonths(openEndedMonths);
  return PlanSummary(o, paymentStates(o, records, today, until: until));
}

// ---------------------------------------------------------------------------
// Combined payments (A17): one transfer to a provider paying several plans.
// The owner says how it is split; OneSpace only checks the parts add up.

class SplitPart {
  const SplitPart(this.obligationId, this.number, this.amount);
  final String obligationId;
  final int number;
  final Amount amount;
}

class CombinedSplit {
  CombinedSplit(this.total, this.parts);
  final Amount total;
  final List<SplitPart> parts;

  Amount get assigned => parts.fold(Amount.zero, (a, p) => a + p.amount);
  Amount get unassigned => total - assigned;

  /// Valid when every part is positive, no payment appears twice and the
  /// parts add up to exactly the total.
  String? get problem {
    if (!total.isPositive) return 'The total must be more than zero.';
    if (parts.isEmpty) return 'Choose at least one plan.';
    if (parts.any((p) => !p.amount.isPositive)) return 'Each part must be more than zero.';
    final keys = parts.map((p) => '${p.obligationId}#${p.number}').toSet();
    if (keys.length != parts.length) return 'A payment is listed twice.';
    if (assigned != total) return 'The parts must add up to the total.';
    return null;
  }

  bool get isValid => problem == null;
}

/// The confirmation each split part becomes: done when it covers the
/// payment's remaining amount, partial otherwise.
ConfirmKind kindForPart(Amount part, Amount remaining) =>
    part >= remaining ? ConfirmKind.done : ConfirmKind.partial;

// ---------------------------------------------------------------------------
// Freedom Timeline: when each plan ends and the monthly room it frees.

/// The monthly equivalent of a regular amount, exact then rounded once:
/// weekly × 52 / 12, every two weeks × 26 / 12, twice a month × 2,
/// every N months ÷ N, once = 0.
Amount monthlyEquivalent(Amount regular, Frequency f, int intervalMonths, int decimals) {
  final (num, den) = switch (f) {
    Frequency.once => (0, 1),
    Frequency.weekly => (52, 12),
    Frequency.biweekly => (26, 12),
    Frequency.semimonthly => (2, 1),
    Frequency.monthly => (1, 1),
    Frequency.everyMonths => (1, intervalMonths.clamp(1, 120)),
  };
  return regular.mulDiv(BigInt.from(num), BigInt.from(den), decimals);
}

class FreedomPoint {
  const FreedomPoint(this.obligation, this.endsOn, this.monthlyRoom, this.remaining, this.paymentsLeft);
  final Obligation obligation;
  final Day endsOn;

  /// What stops being paid each month once this plan is finished.
  final Amount monthlyRoom;

  /// Still to pay until the end (open payments, overdue included).
  final Amount remaining;
  final int paymentsLeft;
}

/// Finite, unfinished plans ordered by end date. Plans that are already
/// fully paid, paused or open-ended are left out.
List<FreedomPoint> freedomTimeline(List<(Obligation, List<Confirmation>)> plans, Day today) {
  final out = <FreedomPoint>[];
  for (final (o, recs) in plans) {
    if (!o.isFinite || o.pausedOn != null || o.frequency == Frequency.once) continue;
    final states = paymentStates(o, recs, today);
    if (states.isEmpty) continue;
    final open = states.where((s) => s.isOpen).toList();
    if (open.isEmpty) continue;
    // The room freed is the regular payment at the end (before a balloon).
    final regular = states.length >= 2 && o.balloon != null
        ? states[states.length - 2].expected
        : states.last.expected;
    out.add(FreedomPoint(
      o,
      states.last.occurrence.due,
      monthlyEquivalent(regular, o.frequency, o.intervalMonths, o.decimals),
      open.fold(Amount.zero, (a, s) => a + s.remaining),
      open.length,
    ));
  }
  out.sort((a, b) {
    final c = a.endsOn.compareTo(b.endsOn);
    return c != 0 ? c : a.obligation.title.compareTo(b.obligation.title);
  });
  return out;
}

/// The total still to pay on all finite plans, per currency, and the day the
/// last one ends ("debt-free").
class DebtFree {
  DebtFree(this.remaining, this.lastDay, this.monthlyRoom);
  final CurrencyTotals remaining;
  final Day? lastDay;

  /// Monthly room freed once every plan has ended, per currency.
  final CurrencyTotals monthlyRoom;
}

DebtFree debtFree(List<FreedomPoint> timeline) {
  final remaining = CurrencyTotals();
  final room = CurrencyTotals();
  Day? last;
  for (final p in timeline) {
    remaining.add(p.obligation.currency, p.remaining);
    room.add(p.obligation.currency, p.monthlyRoom);
    if (last == null || p.endsOn.isAfter(last)) last = p.endsOn;
  }
  return DebtFree(remaining, last, room);
}

/// Running room freed per currency after each point of the timeline.
List<CurrencyTotals> cumulativeRoom(List<FreedomPoint> timeline) {
  final out = <CurrencyTotals>[];
  final run = CurrencyTotals();
  for (final p in timeline) {
    run.add(p.obligation.currency, p.monthlyRoom);
    final copy = CurrencyTotals();
    for (final c in run.currencies) {
      copy.add(c, run.of(c));
    }
    out.add(copy);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Reminders (A8): before the due day, and after it for auto-paid bills.

class ReminderPlan {
  const ReminderPlan(this.on, this.afterDue, this.occurrence);
  final Day on;
  final bool afterDue;
  final Occurrence occurrence;
}

/// When to remind about the next open payment: [daysBefore] days before the
/// due day (never before today), or — for an auto-paid bill whose date
/// has passed — the day after the due day, asking for the "done" mark.
ReminderPlan? reminderFor(Obligation o, List<Confirmation> records, Day today, {int daysBefore = 2}) {
  final next = nextOpen(o, records, today);
  if (next == null) return null;
  final due = next.occurrence.due;
  if (o.autoPaid) {
    final after = due.addDays(1);
    return ReminderPlan(after.isBefore(today) ? today : after, true, next.occurrence);
  }
  var on = due.addDays(-daysBefore.clamp(0, 60));
  if (on.isBefore(today)) on = today;
  return ReminderPlan(on, false, next.occurrence);
}

/// Opening position (A16): how many payments of a plan that began on
/// [firstDue] would normally already be due before [today].
int suggestedPaidBefore(Obligation o, Day today) =>
    occurrences(o, until: today.addDays(-1)).length;
