import 'package:material_ui/material_ui.dart';
import 'package:onespace/l10n/phrases.dart';

import '../../core/editor_scaffold.dart';
import 'fin_combined_screen.dart';
import 'fin_data.dart';
import 'fin_item_editor.dart';
import 'fin_item_screen.dart';
import 'fin_money.dart';
import 'fin_plan.dart';
import 'fin_widgets.dart';

/// 28 Nov 2026 (A1, D110+): Finances, the fifth tab. Everything here is the
/// signed-in person's own (private by default, A4). Iteration 1: bills,
/// installment plans, confirmations, the Installments view and the Freedom
/// Timeline. Amounts stay in their own currency.
class FinancesScreen extends StatefulWidget {
  const FinancesScreen({super.key, this.refreshToken = 0});
  final int refreshToken;
  @override
  State<FinancesScreen> createState() => _FinancesScreenState();
}

class _FinancesScreenState extends State<FinancesScreen> {
  FinSnapshot? data;
  Object? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FinancesScreen old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final d = await FinRepo.load();
      if (!mounted) return;
      setState(() { data = d; error = null; loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { error = e; loading = false; });
    }
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) await _load();
  }

  void _addBill() => _push(const FinItemEditor(kind: ObligationKind.bill));
  void _addPlan() => _push(const FinItemEditor(kind: ObligationKind.installment));
  void _fastAdd() => _push(const FastInstallmentEditor());
  void _combined() {
    final d = data;
    if (d == null) return;
    _push(CombinedPaymentScreen(data: d));
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    Widget body;
    if (d == null && loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (d == null) {
      body = ListView(children: [
        FinEmpty(icon: Icons.cloud_off_outlined, title: tt('Could not load Finances'),
          text: tt('Check your connection and pull down to try again.')),
        Center(child: FilledButton(onPressed: _load, child: Text(tt('Try again')))),
      ]);
    } else {
      body = TabBarView(children: [
        _refresh(_Overview(data: d, open: _push)),
        _refresh(_BillsList(data: d, open: _push, onAdd: _addBill)),
        _refresh(_InstallmentsView(data: d, open: _push, onAdd: _addPlan, onCombined: _combined)),
        _refresh(_FreedomTimeline(data: d, open: _push)),
      ]);
    }
    return DefaultTabController(length: 4, child: Scaffold(
      appBar: PreferredSize(preferredSize: const Size.fromHeight(kTextTabBarHeight), child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
          Tab(text: tt('Overview')),
          Tab(text: tt('Bills')),
          Tab(text: tt('Installments')),
          Tab(text: tt('Freedom timeline')),
        ]))),
      body: body,
      floatingActionButton: AddFabMenu(label: 'Add', options: [
        AddFabOption('Add a bill', Icons.receipt_long_outlined, _addBill),
        AddFabOption('Add an installment plan', Icons.credit_score_outlined, _addPlan),
        AddFabOption('Quick add installments', Icons.bolt_outlined, _fastAdd),
        AddFabOption('Record a combined payment', Icons.call_split_outlined, _combined),
      ]),
    ));
  }

  Widget _refresh(Widget child) => RefreshIndicator(onRefresh: _load, child: child);
}

/// The open payments of all active items, with their item.
List<(FinItem, PaymentState)> _openPayments(FinSnapshot d, {required Day until}) {
  final out = <(FinItem, PaymentState)>[];
  for (final item in d.active) {
    for (final s in paymentStates(item.plan, d.recordsOf(item.id), d.today, until: until)) {
      if (s.isOpen) out.add((item, s));
    }
  }
  out.sort((a, b) => a.$2.occurrence.due.compareTo(b.$2.occurrence.due));
  return out;
}

class _Overview extends StatelessWidget {
  const _Overview({required this.data, required this.open});
  final FinSnapshot data;
  final Future<void> Function(Widget) open;

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d.active.isEmpty) {
      return ListView(padding: const EdgeInsets.only(bottom: 120), children: [
        FinEmpty(icon: Icons.account_balance_wallet_outlined, title: tt('Your finances, privately'),
          text: tt('Add your bills and installment plans. Everything here is private to you until you choose to share it.')),
      ]);
    }
    final in30 = d.today.addDays(30);
    final open30 = _openPayments(d, until: in30);
    final needs = open30.where((e) => const {PayStatus.overdue, PayStatus.dueToday, PayStatus.awaitingMark, PayStatus.partial}
        .contains(e.$2.status) && !e.$2.occurrence.due.isAfter(d.today)).toList();
    final coming = open30.where((e) => e.$2.occurrence.due.isAfter(d.today)).toList();
    final due30 = CurrencyTotals();
    for (final (item, s) in open30) {
      due30.add(item.plan.currency, s.remaining);
    }
    final overdue = CurrencyTotals();
    for (final (item, s) in needs) {
      if (s.status != PayStatus.dueToday) overdue.add(item.plan.currency, s.remaining);
    }
    final timeline = freedomTimeline([for (final i in d.installments) (i.plan, d.recordsOf(i.id))], d.today);
    final free = debtFree(timeline);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
      Row(children: [
        Expanded(child: FigureTile(caption: tt('To pay in the next 30 days'), value: moneyTotals(due30), icon: Icons.event_note_outlined)),
        const SizedBox(width: 10),
        Expanded(child: FigureTile(caption: tt('Overdue'), value: overdue.isEmpty ? tt('Nothing') : moneyTotals(overdue),
          icon: Icons.warning_amber_rounded, alert: !overdue.isEmpty)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: FigureTile(caption: tt('Left on installment plans'), value: moneyTotals(free.remaining), icon: Icons.credit_score_outlined)),
        const SizedBox(width: 10),
        Expanded(child: FigureTile(caption: tt('Debt-free on'),
          value: free.lastDay == null ? tt('No plans') : dayText(context, free.lastDay!), icon: Icons.flag_outlined)),
      ]),
      const SizedBox(height: 20),
      if (needs.isNotEmpty) ...[
        _Header(tt('Needs you')),
        for (final (item, s) in needs) _PaymentTile(item: item, state: s, data: d, open: open),
        const SizedBox(height: 12),
      ],
      _Header(tt('Coming up (30 days)')),
      if (coming.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(tt('Nothing due in the next 30 days.'))),
      for (final (item, s) in coming) _PaymentTile(item: item, state: s, data: d, open: open),
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 6, top: 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(
      color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)));
}

/// One expected payment; tapping it opens the confirmation (A8).
class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.item, required this.state, required this.data, required this.open});
  final FinItem item;
  final PaymentState state;
  final FinSnapshot data;
  final Future<void> Function(Widget) open;
  @override
  Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
    leading: Icon(item.isBill ? Icons.receipt_long_outlined : Icons.credit_score_outlined),
    title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${dayText(context, state.occurrence.due)} · ${money(state.remaining, item.plan.currency)}'),
      StatusChip(state.status),
    ]),
    trailing: const Icon(Icons.chevron_right),
    onTap: () async {
      final saved = await showConfirmSheet(context, item: item, state: state, records: data.recordsOf(item.id));
      if (saved == true) await open(FinItemScreen(itemId: item.id));
    },
  ));
}

class _BillsList extends StatelessWidget {
  const _BillsList({required this.data, required this.open, required this.onAdd});
  final FinSnapshot data;
  final Future<void> Function(Widget) open;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) {
    final bills = data.bills;
    if (bills.isEmpty) {
      return ListView(children: [
        FinEmpty(icon: Icons.receipt_long_outlined, title: tt('No bills yet'),
          text: tt('Rent, utilities, phone, insurance, subscriptions: add each bill once and OneSpace reminds you before it is due.')),
        Center(child: FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(tt('Add a bill')))),
      ]);
    }
    final monthly = CurrencyTotals();
    for (final b in bills) {
      if (b.paused || b.plan.frequency == Frequency.once) continue;
      monthly.add(b.plan.currency, monthlyEquivalent(b.plan.expectedAmount(1, data.today), b.plan.frequency,
        b.plan.intervalMonths, b.plan.decimals));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
      FigureTile(caption: tt('Bills per month (about)'), value: moneyTotals(monthly), icon: Icons.calendar_month_outlined),
      const SizedBox(height: 14),
      for (final b in bills) _ItemTile(item: b, data: data, open: open),
    ]);
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.data, required this.open});
  final FinItem item;
  final FinSnapshot data;
  final Future<void> Function(Widget) open;
  @override
  Widget build(BuildContext context) {
    final next = nextOpen(item.plan, data.recordsOf(item.id), data.today);
    final cat = data.categories[item.categoryId];
    final parts = <String>[
      frequencyText(item.plan),
      if (cat != null) tt(cat.label),
      if (item.plan.autoPaid) tt('Paid automatically'),
    ];
    return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(parts.join(' · ')),
        if (item.paused) Text(tt('Paused'), style: TextStyle(color: Theme.of(context).colorScheme.primary))
        else if (next != null) Row(children: [
          Flexible(child: Text('${tt('Next')}: ${dayText(context, next.occurrence.due)}  ')),
          StatusChip(next.status),
        ])
        else Text(tt('All paid')),
      ]),
      trailing: Text(money(next?.expected ?? item.plan.amount, item.plan.currency),
        style: const TextStyle(fontWeight: FontWeight.w700)),
      onTap: () => open(FinItemScreen(itemId: item.id)),
    ));
  }
}

/// The Installments view: paid / unpaid / overdue per plan, grouped by provider.
class _InstallmentsView extends StatelessWidget {
  const _InstallmentsView({required this.data, required this.open, required this.onAdd, required this.onCombined});
  final FinSnapshot data;
  final Future<void> Function(Widget) open;
  final VoidCallback onAdd, onCombined;
  @override
  Widget build(BuildContext context) {
    final plans = data.installments;
    if (plans.isEmpty) {
      return ListView(children: [
        FinEmpty(icon: Icons.credit_score_outlined, title: tt('No installment plans yet'),
          text: tt('Car, phone, furniture or a loan: add the plan once, with the payments already made, and see when it ends.')),
        Center(child: FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(tt('Add an installment plan')))),
      ]);
    }
    final groups = <String?, List<FinItem>>{};
    for (final p in plans) {
      groups.putIfAbsent(p.providerId, () => []).add(p);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => (data.providers[a]?.name ?? '\u{FFFF}').compareTo(data.providers[b]?.name ?? '\u{FFFF}'));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 120), children: [
      for (final k in keys) ...[
        Row(children: [
          Expanded(child: _Header(data.providers[k]?.name ?? tt('No provider'))),
          if (groups[k]!.length > 1) TextButton.icon(onPressed: onCombined,
            icon: const Icon(Icons.call_split_outlined, size: 18), label: Text(tt('Combined payment'))),
        ]),
        for (final p in groups[k]!) _PlanCard(item: p, data: data, open: open),
        const SizedBox(height: 8),
      ],
    ]);
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.item, required this.data, required this.open});
  final FinItem item;
  final FinSnapshot data;
  final Future<void> Function(Widget) open;
  @override
  Widget build(BuildContext context) {
    final sum = summarize(item.plan, data.recordsOf(item.id), data.today);
    final total = sum.totalCount ?? sum.states.length;
    final theme = Theme.of(context);
    final cur = item.plan.currency;
    return Card(margin: const EdgeInsets.only(bottom: 8), child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => open(FinItemScreen(itemId: item.id)),
      child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(item.title, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text(money(item.plan.amount, cur), style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: total == 0 ? 0 : sum.paidCount / total, minHeight: 6,
          borderRadius: BorderRadius.circular(3)),
        const SizedBox(height: 8),
        Text(tt('{} of {} paid').replaceFirst('{}', '${sum.paidCount}').replaceFirst('{}', '$total')),
        Wrap(spacing: 12, runSpacing: 4, children: [
          _Count(Icons.schedule, tt('Unpaid'), sum.unpaidCount, theme.colorScheme.onSurfaceVariant),
          if (sum.partialCount > 0) _Count(Icons.timelapse, tt('Partly paid'), sum.partialCount, Colors.orange.shade800),
          if (sum.overdueCount > 0) _Count(Icons.warning_amber_rounded, tt('Overdue'), sum.overdueCount, theme.colorScheme.error),
        ]),
        const SizedBox(height: 4),
        Text('${tt('Left to pay')}: ${money(sum.remainingAmount, cur)}'
          '${sum.endsOn == null ? '' : ' · ${tt('Ends')} ${dayText(context, sum.endsOn!)}'}',
          style: theme.textTheme.bodySmall),
      ])),
    ));
  }
}

class _Count extends StatelessWidget {
  const _Count(this.icon, this.label, this.count, this.color);
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 16, color: color),
    const SizedBox(width: 4),
    Text('$label: $count', style: TextStyle(color: color)),
  ]);
}

/// Freedom Timeline: when each plan ends and the monthly room it frees.
class _FreedomTimeline extends StatelessWidget {
  const _FreedomTimeline({required this.data, required this.open});
  final FinSnapshot data;
  final Future<void> Function(Widget) open;
  @override
  Widget build(BuildContext context) {
    final timeline = freedomTimeline([for (final i in data.installments) (i.plan, data.recordsOf(i.id))], data.today);
    if (timeline.isEmpty) {
      return ListView(children: [
        FinEmpty(icon: Icons.flag_outlined, title: tt('Your Freedom Timeline'),
          text: tt('Add installment plans to see when each one ends and how much room it frees every month.')),
      ]);
    }
    final free = debtFree(timeline);
    final run = cumulativeRoom(timeline);
    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
      FigureTile(caption: tt('Debt-free on'), value: dayText(context, free.lastDay!), icon: Icons.flag_outlined),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: FigureTile(caption: tt('Still to pay'), value: moneyTotals(free.remaining))),
        const SizedBox(width: 10),
        Expanded(child: FigureTile(caption: tt('Room freed every month in the end'), value: moneyTotals(free.monthlyRoom))),
      ]),
      const SizedBox(height: 16),
      for (var i = 0; i < timeline.length; i++) IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 28, child: Column(children: [
          Container(width: 14, height: 14, margin: const EdgeInsets.only(top: 18),
            decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle)),
          if (i < timeline.length - 1) Expanded(child: Container(width: 2, color: theme.colorScheme.outlineVariant)),
        ])),
        Expanded(child: Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(
          onTap: () => open(FinItemScreen(itemId: timeline[i].obligation.id)),
          title: Text(timeline[i].obligation.title),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${tt('Ends')} ${dayText(context, timeline[i].endsOn)} · '
              '${tt('{} payments left').replaceFirst('{}', '${timeline[i].paymentsLeft}')}'),
            Text('${tt('Frees')} ${money(timeline[i].monthlyRoom, timeline[i].obligation.currency)} ${tt('per month')}',
              style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600)),
            Text('${tt('Freed so far by then')}: ${moneyTotals(run[i])}', style: theme.textTheme.bodySmall),
          ]),
        ))),
      ])),
    ]);
  }
}
