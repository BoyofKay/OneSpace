import 'package:material_ui/material_ui.dart';
import 'package:onespace/l10n/phrases.dart';

import '../../core/form_kit.dart';
import 'fin_data.dart';
import 'fin_item_editor.dart';
import 'fin_money.dart';
import 'fin_plan.dart';
import 'fin_widgets.dart';

/// One bill or installment plan: every expected payment with its status
/// (paid / partly paid / unpaid / overdue), confirmation and corrections.
class FinItemScreen extends StatefulWidget {
  const FinItemScreen({super.key, required this.itemId});
  final String itemId;
  @override
  State<FinItemScreen> createState() => _FinItemScreenState();
}

class _FinItemScreenState extends State<FinItemScreen> {
  FinSnapshot? data;
  bool showAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await FinRepo.load();
      if (mounted) setState(() => data = d);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tt('Could not load. Check your connection and try again.'))));
    }
  }

  Future<void> _menu(String choice, FinItem item, List<Confirmation> recs) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    switch (choice) {
      case 'edit':
        await nav.push(MaterialPageRoute<void>(builder: (_) => FinItemEditor(kind: item.plan.kind, existing: item)));
      case 'pause':
        await FinRepo.setPaused(item.id, item.paused ? null : FinRepo.today());
      case 'archive':
        await FinRepo.setArchived(item.id, !item.archived);
      case 'delete':
        final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(scrollable: true,
          title: Text(tt('Delete this item?')),
          content: Text(tt('It has no confirmed payments, so it can be deleted completely.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tt('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tt('Delete'))),
          ]));
        if (ok != true) return;
        await FinRepo.delete(item.id);
        if (mounted) nav.pop();
        return;
    }
    await _load();
    final fresh = data?.item(item.id);
    if (fresh != null) await FinRepo.syncReminder(fresh, data!.recordsOf(fresh.id), translate: tt);
    if (choice == 'archive') messenger.showSnackBar(SnackBar(content: Text(tt(item.archived ? 'Restored.' : 'Archived. Its payments are kept.'))));
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final item = d?.item(widget.itemId);
    if (d == null || item == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: d == null
          ? const CircularProgressIndicator() : Text(tt('This item is no longer available.'))));
    }
    final recs = d.recordsOf(item.id);
    final o = item.plan;
    final until = o.isFinite ? null : d.today.addMonths(12);
    final states = paymentStates(o, recs, d.today, until: until);
    final sum = PlanSummary(o, states);
    // Long plans: settled payments far in the past are folded away.
    final firstOpen = states.indexWhere((s) => s.isOpen);
    final start = showAll || firstOpen <= 3 ? 0 : firstOpen - 3;
    final cat = d.categories[item.categoryId];
    final provider = d.providers[item.providerId];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(item.title), actions: [
        PopupMenuButton<String>(onSelected: (c) => _menu(c, item, recs), itemBuilder: (_) => [
          PopupMenuItem(value: 'edit', child: Text(tt('Edit'))),
          if (item.isBill) PopupMenuItem(value: 'pause', child: Text(tt(item.paused ? 'Resume' : 'Pause (keep it)'))),
          PopupMenuItem(value: 'archive', child: Text(tt(item.archived ? 'Restore' : 'Archive'))),
          if (recs.isEmpty) PopupMenuItem(value: 'delete', child: Text(tt('Delete'))),
        ]),
      ]),
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
        Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(money(o.amount, o.currency), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text([
              frequencyText(o),
              if (o.amountKind == AmountKind.estimated) tt('Estimated amount'),
              if (o.amountKind == AmountKind.budget) tt('Budget limit'),
              if (o.changeKind == ChangeKind.byPercent) tt('Changes by {}% every {} months')
                  .replaceFirst('{}', o.changePercent.toInput()).replaceFirst('{}', '${o.changeEveryMonths}'),
              if (o.changeKind == ChangeKind.byAmount) tt('Changes by {} every {} months')
                  .replaceFirst('{}', money(o.changeAmount, o.currency)).replaceFirst('{}', '${o.changeEveryMonths}'),
              if (o.balloon != null) '${tt('Final payment')} ${money(o.balloon!, o.currency)}',
              if (o.autoPaid) tt('Paid automatically'),
            ].join(' · ')),
            if (provider != null || cat != null) Text([if (provider != null) provider.name, if (cat != null) tt(cat.label)].join(' · '),
              style: theme.textTheme.bodySmall),
            if (item.paused) Padding(padding: const EdgeInsets.only(top: 6),
              child: Text(tt('Paused: no payments are expected until you resume it.'), style: TextStyle(color: theme.colorScheme.primary))),
            if (item.archived) Padding(padding: const EdgeInsets.only(top: 6),
              child: Text(tt('Archived'), style: TextStyle(color: theme.colorScheme.primary))),
            const Divider(height: 24),
            Text(o.isFinite
                ? tt('{} of {} paid').replaceFirst('{}', '${sum.paidCount}').replaceFirst('{}', '${sum.totalCount ?? states.length}')
                : tt('Next 12 months')),
            Text('${tt('Left to pay')}: ${money(sum.remainingAmount, o.currency)}'),
            if (o.isFinite && sum.endsOn != null) Text('${tt('Ends')} ${dayText(context, sum.endsOn!)}'),
            if (item.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(item.notes)),
          ]))),
        const SizedBox(height: 16),
        Text(tt('Payments'), style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
        if (start > 0) TextButton(onPressed: () => setState(() => showAll = true),
          child: Text(tt('Show {} earlier payments').replaceFirst('{}', '$start'))),
        for (final s in states.skip(start)) Card(margin: const EdgeInsets.only(top: 8), child: ListTile(
          leading: CircleAvatar(radius: 16, child: Text('${s.occurrence.number}', style: const TextStyle(fontSize: 12))),
          title: Text('${dayText(context, s.occurrence.due)} · ${money(s.expected, o.currency)}'),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            StatusChip(s.status),
            if (s.records.isNotEmpty && s.status != PayStatus.paid)
              Text('${tt('Paid so far')}: ${money(s.paid, o.currency)}', style: theme.textTheme.bodySmall),
            if (s.records.isNotEmpty && s.status == PayStatus.paid && s.paid != s.expected)
              Text('${tt('Actual amount')}: ${money(s.paid, o.currency)}', style: theme.textTheme.bodySmall),
          ]),
          trailing: s.status == PayStatus.paidBefore ? null : const Icon(Icons.chevron_right),
          onTap: s.status == PayStatus.paidBefore ? null : () async {
            final changed = s.isOpen && s.status != PayStatus.notDone
                ? await showConfirmSheet(context, item: item, state: s, records: recs)
                : await showRecordSheet(context, item: item, state: s);
            if (changed == true) await _load();
          },
        )),
      ])),
    );
  }
}

/// Done / not done / partly paid + the actual amount (A8). The record is final
/// once saved (A9); mistakes are fixed with a correction.
Future<bool?> showConfirmSheet(BuildContext context, {required FinItem item, required PaymentState state,
    required List<Confirmation> records}) =>
    showModalBottomSheet<bool>(context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => _ConfirmSheet(item: item, state: state, records: records));

class _ConfirmSheet extends StatefulWidget {
  const _ConfirmSheet({required this.item, required this.state, required this.records});
  final FinItem item;
  final PaymentState state;
  final List<Confirmation> records;
  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> {
  ConfirmKind kind = ConfirmKind.done;
  late final amount = TextEditingController(text: widget.state.remaining.toInput());
  DateTime paidOn = DateTime.now();
  bool saving = false;
  String? problem;

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cur = widget.item.plan.currency;
    Amount? actual;
    if (kind != ConfirmKind.notDone) {
      actual = Amount.tryParse(amount.text);
      if (actual == null || actual.isNegative) {
        setState(() => problem = tt('Enter the amount, for example 125.50'));
        return;
      }
      actual = actual.rounded(currencyDecimals(cur));
      if (kind == ConfirmKind.partial && !actual.isPositive) {
        setState(() => problem = tt('A partial payment must be more than zero.'));
        return;
      }
    }
    setState(() { saving = true; problem = null; });
    try {
      final paid = Day.fromDateTime(paidOn);
      // "Done" pays what was still open on this payment; any other amount is kept as typed.
      await FinRepo.confirm(widget.item, widget.state, kind, actual: actual, paidOn: paid);
      final fresh = await FinRepo.load();
      final item = fresh.item(widget.item.id);
      if (item != null) await FinRepo.syncReminder(item, fresh.recordsOf(item.id), translate: tt);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() { saving = false; problem = tt('Could not save. Check your connection and try again.'); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final cur = widget.item.plan.currency;
    return SafeArea(child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.item.title, style: Theme.of(context).textTheme.titleLarge),
        Text('${tt('Payment')} ${s.occurrence.number} · ${dayText(context, s.occurrence.due)} · ${money(s.expected, cur)}'),
        if (s.paid.isPositive) Text('${tt('Paid so far')}: ${money(s.paid, cur)}'),
        const SizedBox(height: 14),
        ChoiceRow<ConfirmKind>(label: 'Was it paid?', selected: kind, onSelected: (k) => setState(() => kind = k ?? kind),
          options: const {ConfirmKind.done: 'Done', ConfirmKind.partial: 'Partly paid', ConfirmKind.notDone: 'Not done'},
          icons: const {ConfirmKind.done: Icons.check_circle_outline, ConfirmKind.partial: Icons.timelapse,
            ConfirmKind.notDone: Icons.cancel_outlined}),
        if (kind != ConfirmKind.notDone) ...[
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: '${tt(kind == ConfirmKind.partial ? 'Amount paid' : 'Actual amount')} ($cur) *',
              helperText: tt('Change it if the real amount was different.'), border: const OutlineInputBorder())),
          const SizedBox(height: 14),
          DateField(label: tt('Paid on'), value: paidOn, required: true, onChanged: (v) => setState(() => paidOn = v ?? paidOn)),
        ],
        Text(tt('Saved records are never changed. If something is wrong later, add a correction.'),
          style: Theme.of(context).textTheme.bodySmall),
        if (problem != null) Padding(padding: const EdgeInsets.only(top: 8),
          child: Text(problem!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: saving ? null : _save,
          child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(tt('Save')))),
      ])));
  }
}

/// The saved records of one payment, and a correction (A9).
Future<bool?> showRecordSheet(BuildContext context, {required FinItem item, required PaymentState state}) =>
    showModalBottomSheet<bool>(context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => _RecordSheet(item: item, state: state));

class _RecordSheet extends StatefulWidget {
  const _RecordSheet({required this.item, required this.state});
  final FinItem item;
  final PaymentState state;
  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  Confirmation? correcting;
  ConfirmKind kind = ConfirmKind.done;
  final amount = TextEditingController();
  final reason = TextEditingController();
  bool saving = false;
  String? problem;

  @override
  void dispose() {
    amount.dispose();
    reason.dispose();
    super.dispose();
  }

  String _kindText(ConfirmKind k) => tt(switch (k) {
        ConfirmKind.done => 'Done',
        ConfirmKind.partial => 'Partly paid',
        ConfirmKind.notDone => 'Not done',
      });

  Future<void> _save() async {
    final rec = correcting!;
    Amount? actual;
    if (kind != ConfirmKind.notDone) {
      actual = Amount.tryParse(amount.text);
      if (actual == null || actual.isNegative) {
        setState(() => problem = tt('Enter the amount, for example 125.50'));
        return;
      }
      actual = actual.rounded(currencyDecimals(widget.item.plan.currency));
    }
    setState(() { saving = true; problem = null; });
    try {
      await FinRepo.correct(rec, kind, actual: actual, reason: reason.text.trim());
      final fresh = await FinRepo.load();
      final item = fresh.item(widget.item.id);
      if (item != null) await FinRepo.syncReminder(item, fresh.recordsOf(item.id), translate: tt);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() { saving = false; problem = tt('Could not save. Check your connection and try again.'); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final cur = widget.item.plan.currency;
    final theme = Theme.of(context);
    return SafeArea(child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.item.title, style: theme.textTheme.titleLarge),
        Text('${tt('Payment')} ${s.occurrence.number} · ${dayText(context, s.occurrence.due)} · ${money(s.expected, cur)}'),
        const SizedBox(height: 8),
        for (final r in s.records) Card(child: ListTile(
          title: Text('${_kindText(r.kind)}${r.actual == null ? '' : ' · ${money(r.actual!, cur)}'}'),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final c in r.corrections) Text('${tt('Corrected to')}: ${_kindText(c.kind)}'
              '${c.actual == null ? '' : ' · ${money(c.actual!, cur)}'}${(c.reason ?? '').isEmpty ? '' : ' — ${c.reason}'}'),
          ]),
          trailing: TextButton(onPressed: () => setState(() {
            correcting = r;
            kind = r.effectiveKind;
            amount.text = r.paid.toInput();
          }), child: Text(tt('Correct'))),
        )),
        if (s.isOpen && s.status != PayStatus.paidBefore) TextButton.icon(
          onPressed: () async {
            final saved = await showConfirmSheet(context, item: widget.item, state: s, records: s.records);
            if (saved == true && context.mounted) Navigator.pop(context, true);
          },
          icon: const Icon(Icons.add), label: Text(tt('Add another payment'))),
        if (correcting != null) ...[
          const Divider(height: 24),
          Text(tt('Correction'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ChoiceRow<ConfirmKind>(label: 'Correct status', selected: kind, onSelected: (k) => setState(() => kind = k ?? kind),
            options: const {ConfirmKind.done: 'Done', ConfirmKind.partial: 'Partly paid', ConfirmKind.notDone: 'Not done'}),
          if (kind != ConfirmKind.notDone) Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: '${tt('Correct amount')} ($cur) *', border: const OutlineInputBorder()))),
          TextField(controller: reason, maxLength: 500,
            decoration: InputDecoration(labelText: tt('Reason (optional)'), border: const OutlineInputBorder())),
          if (problem != null) Text(problem!, style: TextStyle(color: theme.colorScheme.error)),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: saving ? null : _save,
            child: Text(tt('Save correction')))),
        ],
      ])));
  }
}
