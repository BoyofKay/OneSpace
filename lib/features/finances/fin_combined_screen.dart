import 'package:material_ui/material_ui.dart';
import 'package:onespace/l10n/phrases.dart';

import '../../core/editor_scaffold.dart';
import '../../core/form_kit.dart';
import 'fin_data.dart';
import 'fin_money.dart';
import 'fin_plan.dart';
import 'fin_widgets.dart';

/// A17: one transfer that paid several plans (often one provider). The owner
/// says how much went to each payment; OneSpace only checks that the parts
/// add up to the total. No provider allocation rules.
class CombinedPaymentScreen extends StatefulWidget {
  const CombinedPaymentScreen({super.key, required this.data});
  final FinSnapshot data;
  @override
  State<CombinedPaymentScreen> createState() => _CombinedPaymentScreenState();
}

class _Line {
  _Line(this.item, this.state) : controller = TextEditingController();
  final FinItem item;
  final PaymentState state;
  final TextEditingController controller;
  bool selected = false;
}

class _CombinedPaymentScreenState extends State<CombinedPaymentScreen> with FormChangeTracker {
  final total = TextEditingController();
  String? currency;
  String? providerId; // null = every provider
  DateTime paidOn = DateTime.now();
  final lines = <String, _Line>{};
  bool saving = false;
  String? problem;

  FinSnapshot get d => widget.data;

  /// The first two open payments of every active plan (bills too), so an
  /// overdue one and the current one can be paid together.
  List<_Line> _candidates() {
    final out = <_Line>[];
    for (final item in d.active) {
      if (currency != null && item.plan.currency != currency) continue;
      if (providerId != null && item.providerId != providerId) continue;
      final open = paymentStates(item.plan, d.recordsOf(item.id), d.today, until: d.today.addMonths(3))
          .where((s) => s.isOpen && s.status != PayStatus.notDone).take(2);
      for (final s in open) {
        out.add(lines.putIfAbsent('${item.id}#${s.occurrence.number}', () => _Line(item, s)));
      }
    }
    out.sort((a, b) => a.state.occurrence.due.compareTo(b.state.occurrence.due));
    return out;
  }

  @override
  void initState() {
    super.initState();
    final currencies = {for (final i in d.active) i.plan.currency};
    if (currencies.length == 1) currency = currencies.first;
  }

  @override
  void dispose() {
    total.dispose();
    for (final l in lines.values) {
      l.controller.dispose();
    }
    super.dispose();
  }

  @override
  String get signature => [total.text, currency, providerId, paidOn,
    for (final l in lines.values) '${l.selected}${l.controller.text}'].join('|');

  CombinedSplit? _split() {
    final t = Amount.tryParse(total.text);
    if (t == null || currency == null) return null;
    final parts = <SplitPart>[
      for (final l in lines.values)
        if (l.selected && l.item.plan.currency == currency)
          SplitPart(l.item.id, l.state.occurrence.number, Amount.tryParse(l.controller.text) ?? Amount.zero),
    ];
    return CombinedSplit(t.rounded(currencyDecimals(currency!)), parts);
  }

  Future<void> _save() async {
    final split = _split();
    if (split == null || !split.isValid) {
      setState(() => problem = split?.problem == null ? tt('Enter the total.') : tt(split!.problem!));
      return;
    }
    setState(() { saving = true; problem = null; });
    try {
      await FinRepo.recordCombined(
        currency: currency!, total: split.total, paidOn: Day.fromDateTime(paidOn), providerId: providerId,
        parts: [
          for (final l in lines.values)
            if (l.selected && l.item.plan.currency == currency)
              (l.item, l.state, Amount.parse(l.controller.text).rounded(currencyDecimals(currency!))),
        ]);
      final fresh = await FinRepo.load();
      for (final id in {for (final l in lines.values) if (l.selected) l.item.id}) {
        final item = fresh.item(id);
        if (item != null) await FinRepo.syncReminder(item, fresh.recordsOf(id), translate: tt);
      }
      markClean();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() { saving = false; problem = tt('Could not save. Check your connection and try again.'); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates();
    final split = _split();
    final currencies = {for (final i in d.active) i.plan.currency}.toList()..sort();
    final theme = Theme.of(context);
    return EditorScaffold(
      title: 'Combined payment',
      isNew: true,
      isChanged: () => changed,
      isComplete: () => split != null && split.isValid,
      missingHint: split == null ? 'Enter the total and choose the payments.' : (split.problem ?? 'Fill in the fields marked *'),
      saving: saving,
      onSave: _save,
      listenTo: [total, for (final l in lines.values) l.controller],
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(tt('One payment that covered several plans. Say how much went to each; the parts must add up to the total.'),
          style: theme.textTheme.bodyMedium),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: TextField(controller: total, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tt('Total paid *'), border: const OutlineInputBorder()))),
          const SizedBox(width: 10),
          Expanded(child: ChoicePickerField<String>(label: tt('Currency'), selected: currency, required: true,
            icon: Icons.payments_outlined, options: {for (final c in currencies) c: c},
            onSelected: (c) => setState(() => currency = c))),
        ]),
        if (d.providers.isNotEmpty) ChoicePickerField<String>(label: tt('Provider'), selected: providerId,
          noneLabel: 'Every provider', icon: Icons.storefront_outlined,
          options: {for (final p in d.providers.values) p.id: p.name}, onSelected: (p) => setState(() => providerId = p)),
        DateField(label: tt('Paid on'), value: paidOn, required: true, onChanged: (v) => setState(() => paidOn = v ?? paidOn)),
        if (currency == null) Text(tt('Choose the currency first.'))
        else if (candidates.isEmpty) Text(tt('No open payments in this currency.'))
        else ...[
          const FormSection('Split'),
          for (final l in candidates) Card(margin: const EdgeInsets.only(bottom: 8), child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
            child: Column(children: [
              CheckboxListTile(value: l.selected, contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (v) => setState(() {
                  l.selected = v ?? false;
                  if (l.selected && l.controller.text.isEmpty) l.controller.text = l.state.remaining.toInput();
                }),
                title: Text(l.item.title),
                subtitle: Text('${tt('Payment')} ${l.state.occurrence.number} · ${dayText(context, l.state.occurrence.due)} · '
                  '${tt('open')} ${money(l.state.remaining, l.item.plan.currency)}')),
              if (l.selected) Padding(padding: const EdgeInsetsDirectional.only(start: 12), child: TextField(
                controller: l.controller, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: '${tt('Part for this payment')} ($currency) *',
                  border: const OutlineInputBorder(), isDense: true))),
            ]))),
          if (split != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(
            '${tt('Assigned')}: ${money(split.assigned, currency!)} · ${tt('Not assigned yet')}: ${money(split.unassigned, currency!)}',
            style: TextStyle(fontWeight: FontWeight.w700,
              color: split.unassigned.isZero ? Colors.green.shade700 : theme.colorScheme.error))),
        ],
        if (problem != null) Padding(padding: const EdgeInsets.only(top: 8),
          child: Text(problem!, style: TextStyle(color: theme.colorScheme.error))),
      ]),
    );
  }
}
