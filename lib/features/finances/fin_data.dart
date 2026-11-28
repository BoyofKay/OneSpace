import 'package:supabase_flutter/supabase_flutter.dart';

import 'fin_money.dart';
import 'fin_plan.dart';

/// OneSpace Finances (28 Nov 2026): reading and writing the owner's finance
/// records (tables fin_*, database 0325–0327). All money crosses the wire as
/// text (`amount::text`), never as a floating-point number.
///
/// Every record belongs to its creator and lives in their personal storage
/// (private_space_id = the person's id, A3/A5). Nothing is shared in
/// iteration 1, so this file only ever reads the signed-in person's own rows.

/// Starter categories, shown in the app language. Saved as fin_categories
/// rows (built_in_key) the first time one is used.
const finBuiltInCategories = <String, String>{
  'housing': 'Housing and rent',
  'utilities': 'Utilities',
  'phone_internet': 'Phone and internet',
  'insurance': 'Insurance',
  'transport': 'Car and transport',
  'loans': 'Loans and financing',
  'subscriptions': 'Subscriptions',
  'education': 'Education',
  'health': 'Health',
  'family': 'Family and support',
  'other': 'Other',
};

class FinCategory {
  const FinCategory(this.id, this.name, this.builtInKey);
  final String id, name;
  final String? builtInKey;
  /// English name to pass to tt(): built-in ones are translated, custom ones stay as typed.
  String get label => builtInKey != null ? (finBuiltInCategories[builtInKey] ?? name) : name;
}

class FinProvider {
  const FinProvider(this.id, this.name);
  final String id, name;
}

/// One bill or installment plan as stored, with its calculation model.
class FinItem {
  FinItem(this.row) : plan = obligationFromRow(row);
  final Map<String, dynamic> row;
  final Obligation plan;
  String get id => plan.id;
  String get title => plan.title;
  bool get isBill => plan.kind == ObligationKind.bill;
  String? get providerId => row['provider_id']?.toString();
  String? get categoryId => row['category_id']?.toString();
  String get notes => (row['notes'] ?? '').toString();
  String? get paymentLink => row['payment_link']?.toString();
  bool get remindersOn => row['reminders_on'] != false;
  int get reminderDaysBefore => (row['reminder_days_before'] as num?)?.toInt() ?? 2;
  bool get archived => row['archived_at'] != null;
  bool get paused => plan.pausedOn != null;
}

Obligation obligationFromRow(Map<String, dynamic> r) => Obligation(
      id: r['id'].toString(),
      kind: r['kind'] == 'installment' ? ObligationKind.installment : ObligationKind.bill,
      title: (r['title'] ?? '').toString(),
      currency: (r['currency'] ?? 'USD').toString(),
      amount: Amount.fromDb(r['amount']) ?? Amount.zero,
      firstDue: Day.parse(r['first_due_on'].toString()),
      frequency: frequencyFromKey(r['frequency']?.toString()),
      intervalMonths: (r['interval_months'] as num?)?.toInt() ?? 1,
      dueDay: (r['due_day'] as num?)?.toInt(),
      secondDueDay: (r['second_due_day'] as num?)?.toInt(),
      amountKind: amountKindFromKey(r['amount_kind']?.toString()),
      changeKind: changeKindFromKey(r['change_kind']?.toString()),
      changeAmount: Amount.fromDb(r['change_amount']),
      changePercent: Percent.fromDb(r['change_percent']),
      changeEveryMonths: (r['change_every_months'] as num?)?.toInt() ?? 12,
      balloon: Amount.fromDb(r['balloon_amount']),
      endKind: endKindFromKey(r['end_kind']?.toString()),
      endOn: Day.tryParse(r['end_on']),
      paymentCount: (r['payment_count'] as num?)?.toInt(),
      paidBeforeCount: (r['paid_before_count'] as num?)?.toInt() ?? 0,
      autoPaid: r['auto_paid'] == true,
      pausedOn: Day.tryParse(r['paused_on']),
      providerId: r['provider_id']?.toString(),
      category: r['category_id']?.toString(),
    );

/// Everything the Finances tab shows, loaded at once.
class FinSnapshot {
  FinSnapshot({required this.items, required this.records, required this.providers,
    required this.categories, required this.today});
  final List<FinItem> items;
  final Map<String, List<Confirmation>> records;
  final Map<String, FinProvider> providers;
  final Map<String, FinCategory> categories;
  final Day today;

  List<Confirmation> recordsOf(String itemId) => records[itemId] ?? const [];
  List<FinItem> get active => items.where((i) => !i.archived).toList();
  List<FinItem> get bills => active.where((i) => i.isBill).toList();
  List<FinItem> get installments => active.where((i) => !i.isBill).toList();
  List<FinItem> get archived => items.where((i) => i.archived).toList();
  FinItem? item(String id) => items.where((i) => i.id == id).firstOrNull;
}

class FinRepo {
  FinRepo._();
  static SupabaseClient get _db => Supabase.instance.client;
  static String? get me => _db.auth.currentUser?.id;

  static const itemColumns = 'id,kind,title,notes,category_id,provider_id,currency,amount::text,'
      'amount_kind,first_due_on,frequency,interval_months,due_day,second_due_day,change_kind,'
      'change_amount::text,change_percent::text,change_every_months,balloon_amount::text,end_kind,'
      'end_on,payment_count,paid_before_count,auto_paid,reminder_days_before,reminders_on,'
      'payment_link,paused_on,archived_at,created_at';
  static const paymentColumns = 'id,item_id,occurrence_no,due_on,currency,expected_amount::text,'
      'status,actual_amount::text,paid_on,combined_id,note,created_at';

  static Day today() => Day.fromDateTime(DateTime.now());

  static Future<FinSnapshot> load() async {
    final uid = me;
    if (uid == null) throw StateError('Not signed in');
    final results = await Future.wait([
      _db.from('fin_items').select(itemColumns).eq('created_by', uid).order('created_at'),
      _db.from('fin_payments').select(paymentColumns).eq('created_by', uid).order('created_at'),
      _db.from('fin_payment_corrections').select('id,payment_id,status,actual_amount::text,reason,created_at')
          .eq('created_by', uid).order('created_at'),
      _db.from('fin_providers').select('id,name').eq('created_by', uid).filter('archived_at', 'is', null).order('name'),
      _db.from('fin_categories').select('id,name,built_in_key').eq('created_by', uid).filter('archived_at', 'is', null),
    ]);
    final corrections = <String, List<Correction>>{};
    for (final c in (results[2] as List).cast<Map<String, dynamic>>()) {
      corrections.putIfAbsent(c['payment_id'].toString(), () => []).add(Correction(
        kind: confirmKindFromKey(c['status']?.toString()),
        actual: Amount.fromDb(c['actual_amount']),
        reason: c['reason']?.toString()));
    }
    final records = <String, List<Confirmation>>{};
    for (final p in (results[1] as List).cast<Map<String, dynamic>>()) {
      records.putIfAbsent(p['item_id'].toString(), () => []).add(confirmationFromRow(p, corrections[p['id'].toString()] ?? const []));
    }
    return FinSnapshot(
      items: [for (final r in (results[0] as List).cast<Map<String, dynamic>>()) FinItem(r)],
      records: records,
      providers: {for (final r in (results[3] as List).cast<Map<String, dynamic>>())
        r['id'].toString(): FinProvider(r['id'].toString(), r['name'].toString())},
      categories: {for (final r in (results[4] as List).cast<Map<String, dynamic>>())
        r['id'].toString(): FinCategory(r['id'].toString(), r['name'].toString(), r['built_in_key']?.toString())},
      today: today(),
    );
  }

  static Confirmation confirmationFromRow(Map<String, dynamic> p, List<Correction> corrections) => Confirmation(
        id: p['id'].toString(),
        number: (p['occurrence_no'] as num).toInt(),
        due: Day.parse(p['due_on'].toString()),
        expected: Amount.fromDb(p['expected_amount']) ?? Amount.zero,
        kind: confirmKindFromKey(p['status']?.toString()),
        actual: Amount.fromDb(p['actual_amount']),
        combinedId: p['combined_id']?.toString(),
        corrections: corrections,
      );

  /// Saves a new or changed item and returns its id. [values] uses the
  /// column names of fin_items; amounts are passed as text.
  static Future<String> saveItem(Map<String, dynamic> values, {String? id}) async {
    final uid = me!;
    if (id == null) {
      final row = await _db.from('fin_items')
          .insert({...values, 'private_space_id': uid, 'created_by': uid}).select('id').single();
      return row['id'].toString();
    }
    await _db.from('fin_items').update(values).eq('id', id);
    return id;
  }

  /// A confirmation (A8). Never edited afterwards (A9).
  static Future<void> confirm(FinItem item, PaymentState state, ConfirmKind kind,
      {Amount? actual, Day? paidOn, String note = ''}) async {
    final uid = me!;
    await _db.from('fin_payments').insert({
      'item_id': item.id,
      'private_space_id': uid,
      'created_by': uid,
      'occurrence_no': state.occurrence.number,
      'due_on': state.occurrence.due.toDb(),
      'currency': item.plan.currency,
      'expected_amount': state.expected.toDb(),
      'status': confirmKindKey(kind),
      'actual_amount': kind == ConfirmKind.notDone ? null : actual?.toDb(),
      'paid_on': kind == ConfirmKind.notDone ? null : (paidOn ?? today()).toDb(),
      'note': note,
    });
  }

  /// A correction is a new entry that replaces one record's status and amount (A9).
  static Future<void> correct(Confirmation record, ConfirmKind kind, {Amount? actual, String reason = ''}) async {
    final uid = me!;
    await _db.from('fin_payment_corrections').insert({
      'payment_id': record.id,
      'private_space_id': uid,
      'created_by': uid,
      'status': confirmKindKey(kind),
      'actual_amount': kind == ConfirmKind.notDone ? null : actual?.toDb(),
      'reason': reason,
    });
  }

  /// One payment split across plans by the owner (A17); saved all together.
  static Future<void> recordCombined({required String currency, required Amount total, required Day paidOn,
      required List<(FinItem, PaymentState, Amount)> parts, String? providerId, String note = ''}) async {
    await _db.rpc('fin_record_combined_payment', params: {
      'p_currency': currency,
      'p_total': total.toDb(),
      'p_paid_on': paidOn.toDb(),
      'p_provider': providerId,
      'p_note': note,
      'p_parts': [
        for (final (item, state, amount) in parts) {
          'item_id': item.id,
          'occurrence_no': state.occurrence.number,
          'due_on': state.occurrence.due.toDb(),
          'expected_amount': state.expected.toDb(),
          'remaining': state.remaining.toDb(),
          'amount': amount.toDb(),
        },
      ],
    });
  }

  static Future<void> setArchived(String id, bool archived) =>
      _db.from('fin_items').update({'archived_at': archived ? DateTime.now().toUtc().toIso8601String() : null}).eq('id', id);

  static Future<void> setPaused(String id, Day? pausedOn) =>
      _db.from('fin_items').update({'paused_on': pausedOn?.toDb()}).eq('id', id);

  /// Only possible while nothing was confirmed (the database refuses otherwise).
  static Future<bool> delete(String id) async {
    final rows = await _db.from('fin_items').delete().eq('id', id).select('id');
    return (rows as List).isNotEmpty;
  }

  static Future<FinProvider> addProvider(String name) async {
    final uid = me!;
    final r = await _db.from('fin_providers')
        .insert({'name': name.trim(), 'private_space_id': uid, 'created_by': uid}).select('id,name').single();
    return FinProvider(r['id'].toString(), r['name'].toString());
  }

  /// The row id of a starter category, created the first time it is used.
  static Future<String> ensureBuiltInCategory(String key, Map<String, FinCategory> known) async {
    for (final c in known.values) {
      if (c.builtInKey == key) return c.id;
    }
    final uid = me!;
    final existing = await _db.from('fin_categories').select('id')
        .eq('created_by', uid).eq('built_in_key', key).maybeSingle();
    if (existing != null) return existing['id'].toString();
    final r = await _db.from('fin_categories').insert({
      'name': finBuiltInCategories[key] ?? key, 'built_in_key': key,
      'private_space_id': uid, 'created_by': uid}).select('id').single();
    return r['id'].toString();
  }

  static Future<String> addCategory(String name) async {
    final uid = me!;
    final r = await _db.from('fin_categories')
        .insert({'name': name.trim(), 'private_space_id': uid, 'created_by': uid}).select('id').single();
    return r['id'].toString();
  }

  /// Keeps the one personal reminder of an item on its next open payment:
  /// [Obligation]'s reminder rule in fin_plan.dart decides the day. The text
  /// names the item, never an amount (A19). Never throws: a reminder problem
  /// must not undo a saved payment.
  static Future<void> syncReminder(FinItem item, List<Confirmation> records, {String Function(String)? translate}) async {
    final uid = me;
    if (uid == null) return;
    final t = translate ?? (String s) => s;
    try {
      final existing = await _db.from('reminders').select('id')
          .eq('created_by', uid).eq('source_kind', 'finance').eq('source_id', item.id)
          .filter('archived_at', 'is', null);
      final ids = [for (final r in (existing as List)) r['id'].toString()];
      final plan = item.archived || item.paused || !item.remindersOn
          ? null
          : reminderFor(item.plan, records, today(), daysBefore: item.reminderDaysBefore);
      if (plan == null) {
        if (ids.isNotEmpty) {
          await _db.from('reminders').update({'archived_at': DateTime.now().toUtc().toIso8601String()}).inFilter('id', ids);
        }
        return;
      }
      final at = DateTime(plan.on.year, plan.on.month, plan.on.day, 9).toUtc().toIso8601String();
      final title = (plan.afterDue
              ? t('Did {} get paid?')
              : t('Payment due soon: {}'))
          .replaceFirst('{}', item.title);
      final values = {
        'title': title.length > 160 ? title.substring(0, 160) : title,
        'details': t('Open Finances to mark it done, not done or partly paid.'),
        'due_at': at,
      };
      if (ids.isEmpty) {
        await _db.from('reminders').insert({
          ...values,
          'private_space_id': uid,
          'created_by': uid,
          'visibility': 'private',
          'audience': 'me',
          'source_kind': 'finance',
          'source_id': item.id,
        });
      } else {
        await _db.from('reminders').update(values).eq('id', ids.first);
        if (ids.length > 1) {
          await _db.from('reminders').update({'archived_at': DateTime.now().toUtc().toIso8601String()}).inFilter('id', ids.sublist(1));
        }
      }
    } catch (_) {
      // Reminders are a convenience; the payment record is what matters.
    }
  }
}
