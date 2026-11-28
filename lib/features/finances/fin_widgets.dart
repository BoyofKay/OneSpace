import 'package:material_ui/material_ui.dart';
import 'package:onespace/l10n/phrases.dart';

import 'fin_money.dart';
import 'fin_plan.dart';

/// "1,234.50 USD" — the amount in its own currency (conversion comes in
/// iteration 3, A13). Digits stay Western so amounts read the same everywhere.
String money(Amount a, String currency) => '${a.format(currencyDecimals(currency))} ${currency.toUpperCase()}';

String moneyTotals(CurrencyTotals t) =>
    t.isEmpty ? money(Amount.zero, 'USD').replaceAll(' USD', '') : [for (final c in t.currencies) money(t.of(c), c)].join(' · ');

String dayText(BuildContext context, Day d) =>
    MaterialLocalizations.of(context).formatMediumDate(DateTime(d.year, d.month, d.day));

const frequencyLabels = <Frequency, String>{
  Frequency.once: 'One time',
  Frequency.weekly: 'Every week',
  Frequency.biweekly: 'Every two weeks',
  Frequency.semimonthly: 'Twice a month',
  Frequency.monthly: 'Every month',
  Frequency.everyMonths: 'Every few months',
};

String frequencyText(Obligation o) {
  if (o.frequency == Frequency.everyMonths) {
    return o.intervalMonths == 12 ? tt('Every year') : tt('Every {} months').replaceFirst('{}', '${o.intervalMonths}');
  }
  return tt(frequencyLabels[o.frequency]!);
}

String statusLabel(PayStatus s) => switch (s) {
      PayStatus.paidBefore => tt('Paid before tracking'),
      PayStatus.paid => tt('Paid'),
      PayStatus.partial => tt('Partly paid'),
      PayStatus.notDone => tt('Not done'),
      PayStatus.upcoming => tt('Upcoming'),
      PayStatus.dueToday => tt('Due today'),
      PayStatus.overdue => tt('Overdue'),
      PayStatus.awaitingMark => tt('Paid automatically? Mark it done'),
    };

IconData statusIcon(PayStatus s) => switch (s) {
      PayStatus.paidBefore || PayStatus.paid => Icons.check_circle,
      PayStatus.partial => Icons.timelapse,
      PayStatus.notDone => Icons.cancel_outlined,
      PayStatus.upcoming => Icons.schedule,
      PayStatus.dueToday => Icons.today,
      PayStatus.overdue => Icons.warning_amber_rounded,
      PayStatus.awaitingMark => Icons.task_alt,
    };

Color statusColor(BuildContext context, PayStatus s) {
  final c = Theme.of(context).colorScheme;
  return switch (s) {
    PayStatus.paidBefore || PayStatus.paid => Colors.green.shade700,
    PayStatus.partial => Colors.orange.shade800,
    PayStatus.notDone || PayStatus.overdue => c.error,
    PayStatus.dueToday || PayStatus.awaitingMark => c.primary,
    PayStatus.upcoming => c.onSurfaceVariant,
  };
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final PayStatus status;
  @override
  Widget build(BuildContext context) {
    final color = statusColor(context, status);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(statusIcon(status), size: 16, color: color),
      const SizedBox(width: 4),
      Flexible(child: Text(statusLabel(status), overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color))),
    ]);
  }
}

/// A big number with a small caption, for the overview cards.
class FigureTile extends StatelessWidget {
  const FigureTile({super.key, required this.caption, required this.value, this.icon, this.alert = false});
  final String caption, value;
  final IconData? icon;
  final bool alert;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = alert ? theme.colorScheme.error : theme.colorScheme.onSurface;
    return Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(14), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 18, color: theme.colorScheme.primary), const SizedBox(width: 6)],
          Expanded(child: Text(caption, style: theme.textTheme.labelMedium)),
        ]),
        const SizedBox(height: 6),
        Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
      ])));
  }
}

/// Empty states inside the Finances tab.
class FinEmpty extends StatelessWidget {
  const FinEmpty({super.key, required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title, text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
    child: Column(children: [
      Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 12),
      Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
    ]));
}
