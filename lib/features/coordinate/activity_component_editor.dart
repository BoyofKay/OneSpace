
import 'package:material_ui/material_ui.dart';
import '../calendar/calendar_rules.dart';
import 'activity_contact.dart';

/// Type-specific inputs produce a reusable structured JSON payload.
/// The Activity itself requires only a title and details; everything below
/// is optional and can be attached later.
class ComponentEditorSheet extends StatefulWidget {
  const ComponentEditorSheet({
    super.key,
    required this.kind,
    this.existing,
  });

  final String kind;
  final Map<String, dynamic>? existing;

  @override
  State<ComponentEditorSheet> createState() => _ComponentEditorSheetState();
}

class _ComponentEditorSheetState extends State<ComponentEditorSheet> {
  late final TextEditingController title;
  late final TextEditingController value;
  late final TextEditingController details;
  late final TextEditingController url;
  late final TextEditingController price;
  late final TextEditingController currency;
  late final TextEditingController specs;
  late final TextEditingController contactPerson;
  late final TextEditingController contactPhone;
  late final TextEditingController contactEmail;
  late final TextEditingController contactAddress;
  late final TextEditingController contactHours;
  String? error;

  Map<String, dynamic> get original =>
      Map<String, dynamic>.from(widget.existing?['payload'] as Map? ?? const {});

  @override
  void initState() {
    super.initState();
    final p = original;
    title = TextEditingController(text: widget.existing?['label']?.toString() ?? '');
    value = TextEditingController(text: p['value']?.toString() ?? '');
    details = TextEditingController(text: p['note']?.toString() ?? '');
    url = TextEditingController(text: p['url']?.toString() ?? '');
    price = TextEditingController(text: p['price']?.toString() ?? '');
    currency = TextEditingController(text: p['currency']?.toString() ?? 'USD');
    specs = TextEditingController(text: p['specs']?.toString() ?? '');
    contactPerson = TextEditingController(text: p['contact_name']?.toString() ?? '');
    contactPhone = TextEditingController(text: p['phone']?.toString() ?? '');
    contactEmail = TextEditingController(text: p['email']?.toString() ?? '');
    contactAddress = TextEditingController(text: p['address']?.toString() ?? '');
    contactHours = TextEditingController(text: p['working_hours']?.toString() ?? '');
  }

  @override
  void dispose() {
    title.dispose();
    value.dispose();
    details.dispose();
    url.dispose();
    price.dispose();
    currency.dispose();
    specs.dispose();
    contactPerson.dispose();
    contactPhone.dispose();
    contactEmail.dispose();
    contactAddress.dispose();
    contactHours.dispose();
    super.dispose();
  }

  Future<void> chooseDate() async {
    final initial = DateTime.tryParse(value.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (picked != null) setState(() => value.text = CalendarRules.sqlDate(picked));
  }

  Widget input(
    TextEditingController controller,
    String label, {
    int max = 180,
    int lines = 1,
    TextInputType? keyboardType,
    String? hint,
  }) => TextField(
    controller: controller,
    maxLength: max,
    maxLines: lines,
    keyboardType: keyboardType,
    textCapitalization: lines > 1 ? TextCapitalization.sentences : TextCapitalization.words,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
      counterText: '',
    ),
  );

  bool get isDated => widget.kind == 'date' || widget.kind == 'reminder';

  void save() {
    final label = title.text.trim();
    final v = value.text.trim();
    final kind = widget.kind;
    if (label.isEmpty) {
      setState(() => error = 'Give this item a name.');
      return;
    }
    if (kind == 'contact') {
      final contact = ActivityContact(
        person: contactPerson.text.trim(),
        phone: contactPhone.text.trim(),
        email: contactEmail.text.trim(),
        address: contactAddress.text.trim(),
        workingHours: contactHours.text.trim(),
        note: details.text.trim(),
      );
      final invalid = contact.validate();
      if (invalid != null) {
        setState(() => error = invalid);
        return;
      }
      Navigator.of(context).pop({
        'label': label,
        'payload': contact.toPayload(original: original),
      });
      return;
    }
    if ((kind == 'link' || kind == 'location') && v.isEmpty) {
      setState(() => error = 'Enter a link or location.');
      return;
    }
    if (kind == 'link') {
      final u = Uri.tryParse(v);
      if (u == null || !u.hasAuthority || (u.scheme != 'https' && u.scheme != 'http')) {
        setState(() => error = 'Enter a valid https:// or http:// link.');
        return;
      }
    }
    if (kind == 'option' && url.text.trim().isNotEmpty) {
      final u = Uri.tryParse(url.text.trim());
      if (u == null || !u.hasAuthority || (u.scheme != 'https' && u.scheme != 'http')) {
        setState(() => error = 'The option website must be an http(s) link.');
        return;
      }
    }
    if (isDated && DateTime.tryParse(v) == null) {
      setState(() => error = 'Choose a valid date.');
      return;
    }
    if (kind == 'price' || (kind == 'option' && price.text.trim().isNotEmpty)) {
      final raw = kind == 'price' ? v : price.text.trim();
      final parsed = num.tryParse(raw);
      if (parsed == null || parsed < 0) {
        setState(() => error = 'Enter a non-negative numeric amount.');
        return;
      }
      if (!RegExp(r'^[A-Za-z]{3}$').hasMatch(currency.text.trim())) {
        setState(() => error = 'Use a three-letter currency such as USD or SAR.');
        return;
      }
    }
    final payload = <String, dynamic>{
      ...original,
      'value': v,
      'note': details.text.trim(),
    };
    switch (kind) {
      case 'option':
        payload['url'] = url.text.trim();
        payload['price'] = price.text.trim();
        payload['currency'] = currency.text.trim().toUpperCase();
        payload['specs'] = specs.text.trim();
        payload.putIfAbsent('state', () => 'considering');
      case 'price':
        payload['currency'] = currency.text.trim().toUpperCase();
        payload.putIfAbsent('observed_at', () => DateTime.now().toUtc().toIso8601String());
      case 'step':
        payload.putIfAbsent('status', () => 'open');
    }
    Navigator.of(context).pop({'label': label, 'payload': payload});
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18, 12, 18, MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'Add ${kind[0].toUpperCase()}${kind.substring(1)}'
                : 'Edit ${kind[0].toUpperCase()}${kind.substring(1)}',
              style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            input(title, kind == 'spec' ? 'Specification name (e.g., Voltage)' :
              kind == 'option' ? 'Product or provider name' :
              kind == 'step' ? 'Next action' :
              kind == 'contact' ? 'Contact card title (e.g., Gym B admissions)' :
              'Title', max: 180),
            const SizedBox(height: 12),
            if (kind == 'contact') ...[
              input(contactPerson, 'Person to contact (optional)', max: 180),
              const SizedBox(height: 12),
              input(contactPhone, 'Phone number', max: 80,
                keyboardType: TextInputType.phone, hint: '+1 610 555 0147'),
              const SizedBox(height: 12),
              input(contactEmail, 'Email address', max: 254,
                keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              input(contactAddress, 'Physical address', max: 1000, lines: 2,
                keyboardType: TextInputType.streetAddress),
              const SizedBox(height: 12),
              input(contactHours, 'Working hours', max: 800, lines: 3,
                hint: 'Mon–Fri 9:00 AM–5:00 PM'),
              const SizedBox(height: 12),
              input(details, 'Notes / best time to reach them', max: 3000, lines: 3),
              const SizedBox(height: 5),
              Text('Add whichever fields you know. Hours are recorded as provided.',
                style: Theme.of(context).textTheme.bodySmall),
            ] else if (isDated) ...[
              OutlinedButton.icon(
                onPressed: chooseDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(value.text.isEmpty ? 'Choose a date' : value.text),
              ),
              if (kind == 'reminder')
                const Text('Saves a date; phone notifications are not enabled yet.'),
            ] else if (kind == 'image') ...[
              const Text('This photo remains private to authorized partners.'),
              const SizedBox(height: 12),
              input(details, 'Photo caption', max: 4000, lines: 3),
            ] else if (kind == 'tag') ...[
              const Text('Tags help describe and group related items.'),
            ] else if (kind == 'price') ...[
              const Text('Capture the amount and currency observed for this option.'),
            ] else ...[
              input(value,
                kind == 'link' ? 'Website URL' :
                kind == 'location' ? 'Place, address, or coordinates' :
                kind == 'price' ? 'Amount' :
                kind == 'spec' ? 'Specification value' :
                kind == 'note' ? 'Full note' :
                kind == 'step' ? 'Step instructions (optional)' :
                kind == 'option' ? 'Why this is an option (optional)' :
                kind == 'mention' ? 'Person or message' : 'Details',
                max: kind == 'note' ? 4000 : 1600,
                lines: ['note','step','option'].contains(kind) ? 4 : 1,
                keyboardType: kind == 'price'
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : kind == 'link' ? TextInputType.url : null),
            ],
            if (kind == 'price' || kind == 'option') ...[
              const SizedBox(height: 12),
              if (kind == 'option') ...[
                input(url, 'Source website (optional)', max: 2048,
                  keyboardType: TextInputType.url),
                const SizedBox(height: 12),
                input(specs, 'Key specifications (optional)', max: 3000, lines: 3),
                const SizedBox(height: 12),
              ],
              Row(children: [
                Expanded(child: input(priceOrValue(kind), 'Price', max: 20,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                const SizedBox(width: 10),
                SizedBox(width: 90, child: input(currency, 'Currency', max: 3)),
              ]),
            ],
            if (kind != 'note' && kind != 'step' && kind != 'tag' &&
                kind != 'option' && kind != 'reminder' && kind != 'image' &&
                kind != 'contact') ...[
              const SizedBox(height: 12),
              input(details, 'Additional note (optional)', max: 4000, lines: 3),
            ],
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: save,
              icon: const Icon(Icons.check), label: const Text('Save')),
          ],
        ),
      ),
    );
  }

  TextEditingController priceOrValue(String kind) =>
      kind == 'price' ? value : price;
}
