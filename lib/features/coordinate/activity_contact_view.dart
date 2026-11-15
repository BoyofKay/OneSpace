import 'package:material_ui/material_ui.dart';

import 'activity_contact.dart';
import 'package:onespace/l10n/phrases.dart';

/// Compact actionable contact details inside any Activity or Option.
class ActivityContactView extends StatelessWidget {
  const ActivityContactView({
    super.key,
    required this.contact,
    required this.onPhone,
    required this.onEmail,
    required this.onMap,
  });

  final ActivityContact contact;
  final void Function(Uri uri) onPhone;
  final void Function(Uri uri) onEmail;
  final void Function(String address) onMap;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (contact.person.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${tt('Contact')}: ${contact.person}', style: style),
          ),
        if (contact.company.isNotEmpty || contact.role.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(children:[
              const Icon(Icons.business_outlined,size:17),
              const SizedBox(width:5),
              Expanded(child:Text(tt([
                if(contact.company.isNotEmpty)contact.company,
                if(contact.role.isNotEmpty)contact.role,
              ].join(' · ')),style:style)),
            ]),
          ),
        if (Uri.tryParse(contact.website) case final Uri website
            when website.hasAuthority &&
              (website.scheme=='https'||website.scheme=='http'))
          TextButton.icon(
            onPressed:()=>onEmail(website),
            icon:const Icon(Icons.language,size:17),
            label:Text(tt(contact.website)),
          ),
        if (contact.workingHours.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.schedule_outlined, size: 17),
                const SizedBox(width: 5),
                Expanded(child: Text(tt(contact.workingHours), style: style)),
              ],
            ),
          ),
        if (contact.phoneUri != null ||
            contact.emailUri != null ||
            contact.address.isNotEmpty)
          Wrap(
            spacing: 5,
            runSpacing: 0,
            children: [
              if (contact.phoneUri case final Uri phone)
                TextButton.icon(
                  onPressed: () => onPhone(phone),
                  icon: const Icon(Icons.call_outlined, size: 17),
                  label: Text(tt(contact.phone)),
                ),
              if (contact.emailUri case final Uri email)
                TextButton.icon(
                  onPressed: () => onEmail(email),
                  icon: const Icon(Icons.mail_outline, size: 17),
                  label: Text(tt(contact.email)),
                ),
              if (contact.address.isNotEmpty)
                TextButton.icon(
                  onPressed: () => onMap(contact.address),
                  icon: const Icon(Icons.map_outlined, size: 17),
                  label: Text(tt(contact.address)),
                ),
            ],
          ),
      ],
    );
  }
}
