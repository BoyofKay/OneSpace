/// Structured, reusable contact information attached to an Activity or
/// an individual Option. Blank fields stay blank: hours are never inferred.
class ActivityContact {
  const ActivityContact({
    this.person = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.workingHours = '',
    this.company = '',
    this.role = '',
    this.website = '',
    this.note = '',
  });

  final String person;
  final String phone;
  final String email;
  final String address;
  final String workingHours;
  final String company;
  final String role;
  final String website;
  final String note;

  static String _s(Object? value) => value?.toString().trim() ?? '';

  factory ActivityContact.fromPayload(Map<String, dynamic> payload) =>
      ActivityContact(
        person: _s(payload['contact_name']),
        phone: _s(payload['phone']),
        email: _s(payload['email']),
        address: _s(payload['address']),
        workingHours: _s(payload['working_hours']),
        company: _s(payload['company']),
        role: _s(payload['role']),
        website: _s(payload['website']),
        note: _s(payload['note']),
      );

  bool get hasDetails => [
    person, phone, email, address, workingHours, company, role, website, note,
  ].any((value) => value.isNotEmpty);

  /// Only a number that can be handed to a system dialer is accepted.
  /// No automatic calls are placed; the OS opens the phone app.
  String get dialableNumber =>
      phone.replaceAll(RegExp(r'[\s().-]'), '');

  bool get validPhone => phone.isEmpty ||
      RegExp(r'^\+?[0-9]{5,18}$').hasMatch(dialableNumber);

  bool get validEmail => email.isEmpty ||
      (email.length <= 254 &&
        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email));

  String? validate() {
    if (!hasDetails) return 'Add at least one contact detail.';
    if (person.length > 180 || phone.length > 80 ||
        email.length > 254 || address.length > 1000 ||
        workingHours.length > 800 || company.length > 180 ||
        role.length > 180 || website.length > 500 || note.length > 3000) {
      return 'One of the contact fields is too long.';
    }
    if (!validPhone) return 'Enter a valid telephone number (include country code when needed).';
    if (!validEmail) return 'Enter a valid email address.';
    return null;
  }

  Uri? get phoneUri => phone.isEmpty || !validPhone
      ? null : Uri(scheme: 'tel', path: dialableNumber);

  Uri? get emailUri => email.isEmpty || !validEmail
      ? null : Uri(scheme: 'mailto', path: email);

  Uri? get mapUri => address.isEmpty ? null :
      Uri.https('www.google.com', '/maps/search/', {
        'api': '1', 'query': address,
      });

  Map<String, dynamic> toPayload({Map<String, dynamic> original = const {}}) =>
      {
        ...original,
        'contact_name': person.trim(),
        'phone': phone.trim(),
        'email': email.trim(),
        'address': address.trim(),
        'working_hours': workingHours.trim(),
        'company':company.trim(),'role':role.trim(),
        'website':website.trim(),
        'note': note.trim(),
      };

  /// A single comparison value, only when the contact belongs to an Option.
  String get summary => [
    if (person.isNotEmpty) person,
    if (phone.isNotEmpty) phone,
    if (email.isNotEmpty) email,
    if (address.isNotEmpty) address,
    if (workingHours.isNotEmpty) 'Hours: $workingHours',
    if (company.isNotEmpty) 'Company: $company',
    if (role.isNotEmpty) 'Role: $role',
    if (website.isNotEmpty) 'Website: $website',
  ].join('\n');
}
