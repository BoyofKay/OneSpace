import '../coordinate/activity_contact.dart';

/// Searchable, read-only index of Contact components already attached to the
/// partner's RLS-visible Activities. No separate duplicate contact records.
class WorldContactEntry {
  const WorldContactEntry({
    required this.id,
    required this.activityId,
    required this.activityTitle,
    required this.label,
    required this.contact,
  });

  final String id;
  final String activityId;
  final String activityTitle;
  final String label;
  final ActivityContact contact;

  factory WorldContactEntry.fromRow(Map<String, dynamic> row) {
    final raw = row['payload'];
    final details = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final joined = row['activities'];
    final activity = joined is Map
        ? Map<String, dynamic>.from(joined)
        : <String, dynamic>{};
    return WorldContactEntry(
      id: row['id']?.toString() ?? '',
      activityId: row['activity_id']?.toString() ?? '',
      activityTitle: activity['title']?.toString() ?? 'Activity',
      label: row['label']?.toString() ?? 'Contact',
      contact: ActivityContact.fromPayload(details),
    );
  }

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      label, activityTitle, contact.person, contact.phone,
      contact.email, contact.address, contact.workingHours,
    ].any((value) => value.toLowerCase().contains(q));
  }

  static List<WorldContactEntry> filtered(
    List<WorldContactEntry> contacts, String query,
  ) => contacts.where((c) => c.matches(query)).toList()
    ..sort((a,b)=>a.label.toLowerCase().compareTo(b.label.toLowerCase()));
}
