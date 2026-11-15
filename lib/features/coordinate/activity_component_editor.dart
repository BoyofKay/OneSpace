
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../calendar/calendar_rules.dart';
import 'activity_countdown_rules.dart';
import 'activity_contact.dart';
import 'package:onespace/l10n/phrases.dart';

/// Type-specific inputs produce a reusable structured JSON payload.
/// The Activity itself requires only a title and details; everything below
/// is optional and can be attached later.
class ComponentEditorSheet extends StatefulWidget {
  const ComponentEditorSheet({
    super.key,
    required this.kind,
    this.existing,
    this.spaceId,
  });

  final String kind;
  final Map<String, dynamic>? existing;
  final String? spaceId;

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
  List<String> existingTags=[];
  bool tagsLoading=false;
  bool _repeatYearly=false;

  Map<String, dynamic> get original =>
      Map<String, dynamic>.from(widget.existing?['payload'] as Map? ?? const {});

  @override
  void initState() {
    super.initState();
    final p = original;
    _repeatYearly=p['repeat_yearly']==true;
    if(widget.kind=='tag')_loadTags();
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

  Future<void> _loadTags() async {
    final space=widget.spaceId;
    if(space==null)return;
    setState(()=>tagsLoading=true);
    try{
      final rows=await Supabase.instance.client.from('space_tags')
        .select('label').eq('space_id',space).order('label').limit(100);
      if(mounted)setState(()=>existingTags=[
        for(final row in rows)row['label'].toString()]);
    }catch(_){
      // Component creation still works without a loaded tag inventory.
    }finally{
      if(mounted)setState(()=>tagsLoading=false);
    }
  }
  void _chooseTag(String tag){
    setState((){
      title.text=tag;
      value.text=tag;
    });
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

  bool get isDated => widget.kind == 'date' || widget.kind == 'reminder' || widget.kind == 'countdown';

  Future<void> save() async {
    final label = widget.kind=='tag' && title.text.trim().isEmpty
      ?value.text.trim():title.text.trim();
    final v = value.text.trim();
    final kind = widget.kind;
    if (label.isEmpty) {
      setState(() => error = 'Give this item a name.');
      return;
    }
    if(kind=='tag'){
      final tag=(value.text.trim().isEmpty?label:value.text.trim());
      if(tag.length>50){
        setState(()=>error='Tag must be 50 characters or fewer.');
        return;
      }
      final space=widget.spaceId;
      if(space!=null){
        try{
          final found=await Supabase.instance.client.from('space_tags')
            .select('id').eq('space_id',space).ilike('label',tag).limit(1);
          if(found.isEmpty){
            await Supabase.instance.client.from('space_tags').insert({
              'space_id':space,'label':tag,
            });
          }
        }on PostgrestException catch(e){
          if(e.code!='23505'){
            if(mounted)setState(()=>error='Could not add tag to our inventory.');
            return;
          }
        }catch(_){
          if(mounted)setState(()=>error='Could not save tag inventory.');
          return;
        }
      }
      if(!mounted)return;
      Navigator.of(context).pop({
        'label':tag,'payload':{...original,'value':tag,'note':details.text.trim()},
      });
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
    if (isDated && ActivityCountdownRules.parseDate(v) == null) {
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
      case 'reminder':
        payload.putIfAbsent('status', () => 'open');
      case 'countdown':
        payload['repeat_yearly']=_repeatYearly;
    }
    Navigator.of(context).pop({'label': label, 'payload': payload});
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        18, 12, 18, MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tt(widget.existing == null ? 'Add ${kind[0].toUpperCase()}${kind.substring(1)}'
                : 'Edit ${kind[0].toUpperCase()}${kind.substring(1)}'),
              style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            input(title, kind == 'spec' ? 'Specification name (e.g., Voltage)' :
              kind == 'option' ? 'Product or provider name' :
              kind == 'step' ? 'Next action' :
              kind == 'contact' ? 'Contact card title (e.g., Gym B admissions)' :
              kind == 'voice' ? 'Voice note title' :
              'Title', max: 180),
            const SizedBox(height: 12),
            if (kind == 'voice') ...[
              input(details, 'Caption (optional)', max: 1500, lines: 2),
              const SizedBox(height: 5),
              Text(tt('Only the title and caption can be edited. '
                'The recording itself remains unchanged.'),
                style: Theme.of(context).textTheme.bodySmall),
            ] else if (kind == 'contact') ...[
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
                hint: tt('Mon–Fri 9:00 AM–5:00 PM')),
              const SizedBox(height: 12),
              input(details, 'Notes / best time to reach them', max: 3000, lines: 3),
              const SizedBox(height: 5),
              Text(tt('Add whichever fields you know. Hours are recorded as provided.'),
                style: Theme.of(context).textTheme.bodySmall),
            ] else if (isDated) ...[
              OutlinedButton.icon(
                onPressed: chooseDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(tt(value.text.isEmpty ? 'Choose a date' : value.text)),
              ),
              if (kind == 'reminder')
                Text(tt('Appears in Today and Remember. Phone alerts are not yet enabled.')),
              if(kind=='countdown')...[
                SwitchListTile(
                  contentPadding:EdgeInsets.zero,
                  title:Text(tt('Repeat every year')),
                  subtitle:Text(tt('For birthdays and annual celebrations')),
                  value:_repeatYearly,
                  onChanged:(next)=>setState(()=>_repeatYearly=next)),
                input(details,'What makes this moment special? (optional)',
                  max:1000,lines:2),
                Text(tt('Milestones use calendar dates, so both '
                  'partners see the same date in different time zones.')),
              ],
            ] else if (kind == 'image') ...[
              Text(tt('This photo remains private to authorized partners.')),
              const SizedBox(height: 12),
              input(details, 'Photo caption', max: 4000, lines: 3),
            ] else if (kind == 'tag') ...[
              Text(tt('Reuse a saved tag or create a new one.')),
              const SizedBox(height:8),
              input(value,'Tag',max:50,hint:tt('e.g. Health, Travel, Home')),
              if(tagsLoading)const LinearProgressIndicator(),
              if(existingTags.isNotEmpty)...[
                const SizedBox(height:6),
                Text(tt('Saved tags'),style:Theme.of(context).textTheme.labelLarge),
                Wrap(spacing:6,runSpacing:5,children:[
                  for(final tag in existingTags.where((tag)=>
                     value.text.trim().isEmpty||
                     tag.toLowerCase().contains(value.text.trim().toLowerCase())))
                    ActionChip(
                      avatar:const Icon(Icons.sell_outlined,size:15),
                      label:Text(tt(tag)),onPressed:()=>_chooseTag(tag)),
                ]),
              ],
            ] else if (kind == 'price') ...[
              Text(tt('Capture the amount and currency observed for this option.')),
            ] else ...[
              input(value,
                kind == 'link' ? 'Website URL' :
                kind == 'location' ? 'Place, address, or coordinates' :
                kind == 'price' ? 'Amount' :
                kind == 'spec' ? 'Specification value' :
                kind == 'note' ? 'Full note' :
                kind == 'step' ? 'Step instructions (optional)' :
                kind == 'option' ? 'Why this is an option (optional)' :
                kind == 'mention' ? tt('Person or message') : tt('Details'),
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
                kind != 'contact' && kind != 'voice') ...[
              const SizedBox(height: 12),
              input(details, 'Additional note (optional)', max: 4000, lines: 3),
            ],
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(tt(error!), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: save,
              icon: const Icon(Icons.check), label: Text(tt('Save'))),
          ],
        ),
      ),
    );
  }

  TextEditingController priceOrValue(String kind) =>
      kind == 'price' ? value : price;
}
