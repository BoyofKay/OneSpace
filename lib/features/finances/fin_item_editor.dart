import 'package:material_ui/material_ui.dart';
import 'package:onespace/l10n/phrases.dart';

import '../../core/editor_scaffold.dart';
import '../../core/form_kit.dart';
import '../../core/preferred_currency.dart';
import 'fin_data.dart';
import 'fin_money.dart';
import 'fin_plan.dart';
import 'fin_widgets.dart';

/// Add or edit a bill or an installment plan (iteration 1).
///
/// Bills: fixed, estimated or budget-controlled; one time or recurring;
/// end by date, by count or never; due day; category; paid automatically.
/// Installments: fixed, rising or falling by an amount or a percentage,
/// balloon final payment, provider, and the opening position for plans that
/// started before today (A16: how many payments are already made).
class FinItemEditor extends StatefulWidget {
  const FinItemEditor({super.key, required this.kind, this.existing});
  final ObligationKind kind;
  final FinItem? existing;
  @override
  State<FinItemEditor> createState() => _FinItemEditorState();
}

class _FinItemEditorState extends State<FinItemEditor> with FormChangeTracker {
  bool get isBill => widget.kind == ObligationKind.bill;
  final title = TextEditingController();
  final amount = TextEditingController();
  final changeValue = TextEditingController();
  final balloon = TextEditingController();
  final count = TextEditingController();
  final paidBefore = TextEditingController(text: '0');
  final notes = TextEditingController();
  String currency = PreferredCurrency.code;
  AmountKind amountKind = AmountKind.fixed;
  Frequency frequency = Frequency.monthly;
  int interval = 2;
  int secondDay = 15;
  DateTime? firstDue;
  EndKind endKind = EndKind.never;
  DateTime? endOn;
  ChangeKind changeKind = ChangeKind.none;
  bool rising = true;
  int changeEvery = 12;
  bool autoPaid = false;
  bool remindersOn = true;
  int reminderDays = 2;
  String? providerId;
  String? categoryId;
  String? categoryKey; // a starter category not saved yet
  FinSnapshot? data;
  bool saving = false;
  String? problem;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (!isBill) endKind = EndKind.afterCount;
    if (e != null) {
      final o = e.plan;
      title.text = o.title;
      amount.text = o.amount.toInput();
      currency = o.currency;
      amountKind = o.amountKind;
      frequency = o.frequency;
      if (o.frequency == Frequency.everyMonths) interval = o.intervalMonths;
      secondDay = o.secondDueDay ?? 15;
      firstDue = DateTime(o.firstDue.year, o.firstDue.month, o.firstDue.day);
      endKind = o.endKind;
      if (o.endOn != null) endOn = DateTime(o.endOn!.year, o.endOn!.month, o.endOn!.day);
      if (o.paymentCount != null) count.text = '${o.paymentCount}';
      paidBefore.text = '${o.paidBeforeCount}';
      changeKind = o.changeKind;
      changeEvery = o.changeEveryMonths;
      if (o.changeKind == ChangeKind.byAmount) {
        rising = !o.changeAmount.isNegative;
        changeValue.text = (rising ? o.changeAmount : -o.changeAmount).toInput();
      } else if (o.changeKind == ChangeKind.byPercent) {
        final p = Amount.units(o.changePercent.units);
        rising = !p.isNegative;
        changeValue.text = (rising ? p : -p).toInput();
      }
      if (o.balloon != null) balloon.text = o.balloon!.toInput();
      autoPaid = o.autoPaid;
      remindersOn = e.remindersOn;
      reminderDays = e.reminderDaysBefore;
      providerId = e.providerId;
      categoryId = e.categoryId;
      notes.text = e.notes;
    } else {
      PreferredCurrency.load().then((c) { if (mounted && widget.existing == null) setState(() => currency = c); });
    }
    FinRepo.load().then((d) { if (mounted) setState(() => data = d); }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [title, amount, changeValue, balloon, count, paidBefore, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String get signature => [title.text, amount.text, changeValue.text, balloon.text, count.text, paidBefore.text,
    notes.text, currency, amountKind, frequency, interval, secondDay, firstDue, endKind, endOn, changeKind, rising,
    changeEvery, autoPaid, remindersOn, reminderDays, providerId, categoryId, categoryKey].join('|');

  Amount? get _amount => Amount.tryParse(amount.text);
  int? get _count => int.tryParse(count.text.trim());
  int get _paidBefore => int.tryParse(paidBefore.text.trim()) ?? 0;

  bool get complete =>
      title.text.trim().isNotEmpty && _amount != null && !_amount!.isNegative && firstDue != null &&
      (frequency == Frequency.once || endKind != EndKind.afterCount || (_count != null && _count! > 0)) &&
      (frequency == Frequency.once || endKind != EndKind.onDate || endOn != null);

  /// The plan as it would be saved, for the preview and the opening position.
  Obligation? _preview() {
    if (!complete) return null;
    final d = firstDue!;
    final dec = currencyDecimals(currency);
    final cv = Amount.tryParse(changeValue.text);
    return Obligation(
      id: 'preview', kind: widget.kind, title: title.text.trim(), currency: currency,
      amount: _amount!.rounded(dec), firstDue: Day(d.year, d.month, d.day),
      frequency: frequency, intervalMonths: frequency == Frequency.everyMonths ? interval : 1,
      secondDueDay: frequency == Frequency.semimonthly ? secondDay : null,
      amountKind: amountKind,
      changeKind: cv == null ? ChangeKind.none : changeKind,
      changeAmount: changeKind == ChangeKind.byAmount && cv != null ? (rising ? cv : -cv).rounded(dec) : null,
      changePercent: changeKind == ChangeKind.byPercent && cv != null ? Percent.parse((rising ? cv : -cv).toDb()) : null,
      changeEveryMonths: changeEvery,
      balloon: Amount.tryParse(balloon.text)?.rounded(dec),
      endKind: frequency == Frequency.once ? EndKind.never : endKind,
      endOn: endOn == null ? null : Day(endOn!.year, endOn!.month, endOn!.day),
      paymentCount: frequency == Frequency.once ? null : _count,
      paidBeforeCount: _paidBefore,
      autoPaid: autoPaid,
    );
  }

  Future<void> _save() async {
    final p = _preview();
    if (p == null) return;
    if (p.paymentCount != null && p.paidBeforeCount > p.paymentCount!) {
      setState(() => problem = tt('Payments already made cannot be more than all payments.'));
      return;
    }
    if (p.changeKind == ChangeKind.byPercent && !rising && Amount.units(p.changePercent.units) <= Amount.whole(-100)) {
      setState(() => problem = tt('A fall must be less than 100%.'));
      return;
    }
    setState(() { saving = true; problem = null; });
    try {
      var cat = categoryId;
      if (categoryKey != null) cat = await FinRepo.ensureBuiltInCategory(categoryKey!, data?.categories ?? const {});
      final values = <String, dynamic>{
        if (widget.existing == null) 'kind': isBill ? 'bill' : 'installment',
        'title': p.title,
        'notes': notes.text.trim(),
        'category_id': cat,
        'provider_id': providerId,
        'currency': p.currency,
        'amount': p.amount.toDb(),
        'amount_kind': isBill ? amountKindKey(amountKind) : 'fixed',
        'first_due_on': p.firstDue.toDb(),
        'frequency': frequencyKey(p.frequency),
        'interval_months': p.intervalMonths,
        'due_day': p.dueDay,
        'second_due_day': p.secondDueDay,
        'change_kind': changeKindKey(p.changeKind),
        'change_amount': p.changeAmount.toDb(),
        'change_percent': p.changePercent.toDb(),
        'change_every_months': p.changeEveryMonths,
        'balloon_amount': isBill ? null : p.balloon?.toDb(),
        'end_kind': endKindKey(p.endKind),
        'end_on': p.endKind == EndKind.onDate ? p.endOn?.toDb() : null,
        'payment_count': p.endKind == EndKind.afterCount ? p.paymentCount : null,
        'paid_before_count': p.paidBeforeCount,
        'auto_paid': p.autoPaid,
        'reminders_on': remindersOn,
        'reminder_days_before': reminderDays,
      };
      final id = await FinRepo.saveItem(values, id: widget.existing?.id);
      final fresh = await FinRepo.load();
      final item = fresh.item(id);
      if (item != null) await FinRepo.syncReminder(item, fresh.recordsOf(id), translate: tt);
      markClean();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() { saving = false; problem = tt('Could not save. Check your connection and try again.'); });
    }
  }

  Future<void> _newProvider() async {
    final r = await showFormPage(context, title: 'New provider', saveLabel: 'Add',
      fields: const [FormFieldSpec('Provider name', required: true, maxLength: 80, hint: 'For example a bank or a shop')]);
    if (r == null || r.first.trim().isEmpty) return;
    try {
      final p = await FinRepo.addProvider(r.first);
      final d = await FinRepo.load();
      if (mounted) setState(() { data = d; providerId = p.id; });
    } catch (_) {}
  }

  Future<void> _newCategory() async {
    final r = await showFormPage(context, title: 'New category', saveLabel: 'Add',
      fields: const [FormFieldSpec('Category name', required: true, maxLength: 60)]);
    if (r == null || r.first.trim().isEmpty) return;
    try {
      final id = await FinRepo.addCategory(r.first);
      final d = await FinRepo.load();
      if (mounted) setState(() { data = d; categoryId = id; categoryKey = null; });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final preview = _preview();
    final today = FinRepo.today();
    final suggested = preview == null ? 0 : suggestedPaidBefore(preview, today);
    final startedBefore = firstDue != null && Day(firstDue!.year, firstDue!.month, firstDue!.day).isBefore(today);
    // Category choices: saved ones (custom and starter) + starter ones not saved yet.
    final savedKeys = {for (final c in d?.categories.values ?? const <FinCategory>[]) if (c.builtInKey != null) c.builtInKey};
    final catOptions = <String, String>{
      for (final c in d?.categories.values ?? const <FinCategory>[]) 'id:${c.id}': c.label,
      for (final e in finBuiltInCategories.entries) if (!savedKeys.contains(e.key)) 'key:${e.key}': e.value,
    };
    final catSelected = categoryKey != null ? 'key:$categoryKey' : categoryId != null ? 'id:$categoryId' : null;
    final provOptions = {for (final p in d?.providers.values ?? const <FinProvider>[]) p.id: p.name};
    final next = preview?.isFinite == true ? occurrences(preview!) : (preview == null ? <Occurrence>[] : occurrences(preview, limit: 3));
    return EditorScaffold(
      title: widget.existing != null ? (isBill ? 'Edit bill' : 'Edit installment plan') : (isBill ? 'New bill' : 'New installment plan'),
      isNew: widget.existing == null,
      isChanged: () => changed,
      isComplete: () => complete,
      saving: saving,
      onSave: _save,
      listenTo: [title, amount, changeValue, balloon, count, paidBefore, notes],
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
        TextField(controller: title, maxLength: 120, textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tt(isBill ? 'Bill name *' : 'Plan name *'),
            hintText: tt(isBill ? 'For example electricity or rent' : 'For example car or new phone'),
            border: const OutlineInputBorder())),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tt(isBill ? 'Amount *' : 'Payment amount *'), border: const OutlineInputBorder()))),
          const SizedBox(width: 10),
          Expanded(child: ChoicePickerField<String>(label: tt('Currency'), selected: currency, icon: Icons.payments_outlined,
            options: PreferredCurrency.choices(OneSpacePhrases.lang), onSelected: (c) => setState(() => currency = c ?? currency))),
        ]),
        if (isBill) ChoiceRow<AmountKind>(label: 'The amount is', selected: amountKind,
          onSelected: (k) => setState(() => amountKind = k ?? amountKind),
          options: const {AmountKind.fixed: 'Fixed', AmountKind.estimated: 'An estimate', AmountKind.budget: 'A budget limit'}),
        if (!isBill) Row(children: [
          Expanded(child: ChoicePickerField<String>(label: tt('Provider'), selected: providerId, noneLabel: 'No provider',
            icon: Icons.storefront_outlined, options: provOptions, onSelected: (p) => setState(() => providerId = p))),
          IconButton(tooltip: tt('New provider'), onPressed: _newProvider, icon: const Icon(Icons.add_business_outlined)),
        ]),
        Row(children: [
          Expanded(child: ChoicePickerField<String>(label: tt('Category'), selected: catSelected, noneLabel: 'No category',
            icon: Icons.category_outlined, options: catOptions, onSelected: (v) => setState(() {
              if (v == null) { categoryId = null; categoryKey = null; }
              else if (v.startsWith('key:')) { categoryKey = v.substring(4); categoryId = null; }
              else { categoryId = v.substring(3); categoryKey = null; }
            }))),
          IconButton(tooltip: tt('New category'), onPressed: _newCategory, icon: const Icon(Icons.create_new_folder_outlined)),
        ]),
        const FormSection('When'),
        ChoiceRow<Frequency>(label: 'How often', selected: frequency, onSelected: (f) => setState(() {
          frequency = f ?? frequency;
          if (frequency == Frequency.once) endKind = EndKind.never;
          if (!isBill && frequency != Frequency.once && endKind == EndKind.never) endKind = EndKind.afterCount;
        }), options: {for (final e in frequencyLabels.entries) if (isBill || e.key != Frequency.once) e.key: e.value}),
        if (frequency == Frequency.everyMonths) ChoiceRow<int>(label: 'Every', selected: interval,
          onSelected: (v) => setState(() => interval = v ?? interval),
          options: const {2: '2 months', 3: '3 months', 4: '4 months', 6: '6 months', 12: '12 months'}),
        DateField(label: tt(startedBefore || widget.existing != null ? 'First payment date' : 'First due date'),
          value: firstDue, required: true, first: DateTime(today.year - 40), last: DateTime(today.year + 30),
          onChanged: (v) => setState(() => firstDue = v)),
        if (frequency == Frequency.semimonthly) ChoicePickerField<int>(label: tt('Second day of the month'),
          selected: secondDay, icon: Icons.event_repeat_outlined,
          options: {for (var i = 1; i <= 31; i++) i: '$i'}, onSelected: (v) => setState(() => secondDay = v ?? secondDay)),
        if (frequency == Frequency.monthly || frequency == Frequency.everyMonths || frequency == Frequency.semimonthly)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(firstDue == null ? '' :
            tt('Due on day {} of the month (the last day in shorter months).').replaceFirst('{}', '${firstDue!.day}'),
            style: Theme.of(context).textTheme.bodySmall)),
        if (frequency != Frequency.once) ChoiceRow<EndKind>(label: 'Ends', selected: endKind,
          onSelected: (k) => setState(() => endKind = k ?? endKind),
          options: {if (isBill) EndKind.never: 'Never', EndKind.onDate: 'On a date', EndKind.afterCount: 'After a number of payments'}),
        if (frequency != Frequency.once && endKind == EndKind.onDate) DateField(label: tt('Last payment on or before'),
          value: endOn, required: true, first: DateTime(today.year - 40), last: DateTime(today.year + 40),
          onChanged: (v) => setState(() => endOn = v)),
        if (frequency != Frequency.once && endKind == EndKind.afterCount) Padding(padding: const EdgeInsets.only(bottom: 14),
          child: TextField(controller: count, keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tt('Number of payments in total *'), border: const OutlineInputBorder()))),
        if (startedBefore && frequency != Frequency.once) ...[
          const FormSection('Already paid'),
          Text(tt('This started before today. How many payments are already made? OneSpace does not invent the history; it only marks them as paid before tracking.'),
            style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: paidBefore, keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tt('Payments already made'), border: const OutlineInputBorder()))),
            const SizedBox(width: 8),
            if (suggested > 0 && '$suggested' != paidBefore.text.trim())
              TextButton(onPressed: () => setState(() => paidBefore.text = '$suggested'),
                child: Text(tt('All {} due so far').replaceFirst('{}', '$suggested'))),
          ]),
          const SizedBox(height: 14),
        ],
        if (frequency != Frequency.once) ...[
          const FormSection('Does the amount change?'),
          ChoiceRow<ChangeKind>(label: 'Change', selected: changeKind, onSelected: (k) => setState(() => changeKind = k ?? changeKind),
            options: const {ChangeKind.none: 'Stays the same', ChangeKind.byPercent: 'By a percentage', ChangeKind.byAmount: 'By an amount'}),
          if (changeKind != ChangeKind.none) ...[
            ChoiceRow<bool>(label: 'Direction', selected: rising, onSelected: (v) => setState(() => rising = v ?? rising),
              options: const {true: 'Rises', false: 'Falls'}),
            Row(children: [
              Expanded(child: TextField(controller: changeValue, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: changeKind == ChangeKind.byPercent ? tt('Percent') : '${tt('Amount')} ($currency)',
                  suffixText: changeKind == ChangeKind.byPercent ? '%' : null, border: const OutlineInputBorder()))),
              const SizedBox(width: 10),
              Expanded(child: ChoicePickerField<int>(label: tt('Every'), selected: changeEvery, icon: Icons.update,
                options: const {1: '1 month', 3: '3 months', 6: '6 months', 12: '12 months', 24: '24 months'},
                onSelected: (v) => setState(() => changeEvery = v ?? changeEvery))),
            ]),
          ],
          if (!isBill) Padding(padding: const EdgeInsets.only(bottom: 14), child: TextField(controller: balloon,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: '${tt('Different final payment (balloon), optional')} ($currency)',
              border: const OutlineInputBorder()))),
        ],
        const FormSection('Paying and reminders'),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: autoPaid, onChanged: (v) => setState(() => autoPaid = v),
          title: Text(tt('Paid automatically')),
          subtitle: Text(tt('After the date OneSpace asks you to mark it done.'))),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: remindersOn, onChanged: (v) => setState(() => remindersOn = v),
          title: Text(tt('Remind me')),
          subtitle: Text(tt('Reminders show the name only, never the amount.'))),
        if (remindersOn && !autoPaid) ChoiceRow<int>(label: 'Remind me before', selected: reminderDays,
          onSelected: (v) => setState(() => reminderDays = v ?? reminderDays),
          options: const {0: 'On the day', 1: '1 day', 2: '2 days', 3: '3 days', 7: '1 week'}),
        TextField(controller: notes, maxLength: 2000, minLines: 2, maxLines: 5,
          decoration: InputDecoration(labelText: tt('Notes'), border: const OutlineInputBorder())),
        if (next.isNotEmpty) ...[
          const FormSection('Preview'),
          if (preview!.isFinite) Text(tt('{} payments, last one on {}').replaceFirst('{}', '${next.length}')
              .replaceFirst('{}', dayText(context, next.last.due))),
          for (final o in next.take(3)) Text('${o.number}. ${dayText(context, o.due)} · ${money(o.expected, currency)}'),
          if (next.length > 4) const Text('…'),
          if (next.length > 3) Text('${next.last.number}. ${dayText(context, next.last.due)} · ${money(next.last.expected, currency)}'),
        ],
        if (problem != null) Padding(padding: const EdgeInsets.only(top: 10),
          child: Text(problem!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 8),
        Text(tt('Private to you. Sharing with your partner comes later and will always be your choice.'),
          style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

/// Quick add for installments: the few things on a statement, nothing else.
/// Monthly payments; the first payment date is worked out from the next one
/// and the payments already made (A16).
class FastInstallmentEditor extends StatefulWidget {
  const FastInstallmentEditor({super.key});
  @override
  State<FastInstallmentEditor> createState() => _FastInstallmentEditorState();
}

class _FastInstallmentEditorState extends State<FastInstallmentEditor> with FormChangeTracker {
  final title = TextEditingController();
  final amount = TextEditingController();
  final total = TextEditingController();
  final made = TextEditingController(text: '0');
  final provider = TextEditingController();
  String currency = PreferredCurrency.code;
  DateTime? nextDue;
  bool saving = false;
  String? problem;

  @override
  void initState() {
    super.initState();
    PreferredCurrency.load().then((c) { if (mounted) setState(() => currency = c); });
  }

  @override
  void dispose() {
    for (final c in [title, amount, total, made, provider]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  String get signature => [title.text, amount.text, total.text, made.text, provider.text, currency, nextDue].join('|');

  int? get _total => int.tryParse(total.text.trim());
  int get _made => int.tryParse(made.text.trim()) ?? 0;
  bool get complete => title.text.trim().isNotEmpty && Amount.tryParse(amount.text) != null &&
      _total != null && _total! > 0 && nextDue != null;

  Future<void> _save() async {
    if (_made >= _total!) {
      setState(() => problem = tt('Payments already made must be fewer than all payments.'));
      return;
    }
    setState(() { saving = true; problem = null; });
    try {
      final next = Day(nextDue!.year, nextDue!.month, nextDue!.day);
      final first = next.addMonths(-_made);
      String? providerId;
      if (provider.text.trim().isNotEmpty) {
        final d = await FinRepo.load();
        final name = provider.text.trim().toLowerCase();
        providerId = d.providers.values.where((p) => p.name.toLowerCase() == name).firstOrNull?.id
            ?? (await FinRepo.addProvider(provider.text)).id;
      }
      final id = await FinRepo.saveItem({
        'kind': 'installment', 'title': title.text.trim(), 'currency': currency,
        'amount': Amount.parse(amount.text).rounded(currencyDecimals(currency)).toDb(),
        'first_due_on': first.toDb(), 'due_day': next.day, 'frequency': 'monthly',
        'end_kind': 'count', 'payment_count': _total, 'paid_before_count': _made, 'provider_id': providerId,
      });
      final fresh = await FinRepo.load();
      final item = fresh.item(id);
      if (item != null) await FinRepo.syncReminder(item, fresh.recordsOf(id), translate: tt);
      markClean();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() { saving = false; problem = tt('Could not save. Check your connection and try again.'); });
    }
  }

  @override
  Widget build(BuildContext context) => EditorScaffold(
    title: 'Quick add installments',
    isNew: true,
    isChanged: () => changed,
    isComplete: () => complete,
    saving: saving,
    onSave: _save,
    listenTo: [title, amount, total, made, provider],
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Text(tt('Monthly installments in one step. You can add details later with Edit.'),
        style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 14),
      TextField(controller: title, maxLength: 120,
        decoration: InputDecoration(labelText: tt('Plan name *'), border: const OutlineInputBorder())),
      TextField(controller: provider, maxLength: 80,
        decoration: InputDecoration(labelText: tt('Provider'), hintText: tt('For example a bank or a shop'), border: const OutlineInputBorder())),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: tt('Monthly payment *'), border: const OutlineInputBorder()))),
        const SizedBox(width: 10),
        Expanded(child: ChoicePickerField<String>(label: tt('Currency'), selected: currency, icon: Icons.payments_outlined,
          options: PreferredCurrency.choices(OneSpacePhrases.lang), onSelected: (c) => setState(() => currency = c ?? currency))),
      ]),
      Row(children: [
        Expanded(child: TextField(controller: total, keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: tt('Payments in total *'), border: const OutlineInputBorder()))),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: made, keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: tt('Already made'), border: const OutlineInputBorder()))),
      ]),
      const SizedBox(height: 14),
      DateField(label: tt('Next payment date'), value: nextDue, required: true, onChanged: (v) => setState(() => nextDue = v)),
      if (problem != null) Text(problem!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ]),
  );
}
