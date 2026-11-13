import 'activity_contact.dart';

/// Builds a side-by-side comparison from existing Coordinate components.
/// Pure Dart: no network, UI or database access. A missing value means "not
/// recorded", never an inferred specification, price, or availability.
class ActivityComparisonColumn {
  const ActivityComparisonColumn({
    required this.id,
    required this.title,
    required this.sourceUrl,
    required this.values,
    required this.myOpinion,
    required this.partnerOpinion,
  });

  final String id;
  final String title;
  final String sourceUrl;
  final Map<String, String> values;
  final int? myOpinion;
  final int? partnerOpinion;
}

class ActivityComparisonRow {
  const ActivityComparisonRow({required this.key, required this.label});

  final String key;
  final String label;
}

class ActivityComparisonMatrix {
  const ActivityComparisonMatrix({required this.columns, required this.rows});

  final List<ActivityComparisonColumn> columns;
  final List<ActivityComparisonRow> rows;

  String value(String rowKey, ActivityComparisonColumn option) =>
      option.values[rowKey] ?? '—';

  static String _key(String label) =>
      label.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String _string(Object? value) => value?.toString().trim() ?? '';

  static Map<String, dynamic> _payload(Map<String, dynamic> item) {
    final raw = item['payload'];
    if (raw is! Map) return {};
    return Map<String, dynamic>.from(raw);
  }

  static ActivityComparisonMatrix build(
    List<Map<String, dynamic>> components, {
    List<Map<String, dynamic>> reactions = const [],
    String? currentUserId,
  }) {
    final optionRecords = components.where((c) =>
      c['kind'] == 'option' && c['archived_at'] == null &&
      c['id'] is String &&
      (c['parent_component_id'] == null)).toList();

    final rows = <String, String>{};
    final values = <String, Map<String, String>>{};
    void add(
      Map<String, String> target,
      String field,
      String value, {
      bool override = false,
    }) {
      if (field.trim().isEmpty || value.trim().isEmpty) return;
      final key = _key(field);
      rows.putIfAbsent(key, () => field.trim());
      if (override || !target.containsKey(key)) {
        target[key] = value.trim();
      } else if (target[key] != value.trim()) {
        target[key] = '${target[key]} · ${value.trim()}';
      }
    }

    final columns = <ActivityComparisonColumn>[];
    for (final option in optionRecords) {
      final optionId = option['id'] as String;
      final payload = _payload(option);
      final fields = <String, String>{};
      final basePrice = _string(payload['price']);
      final currency = _string(payload['currency']);
      add(fields, 'Price', basePrice.isEmpty ? '' :
          [currency, basePrice].where((s) => s.isNotEmpty).join(' '));
      add(fields, 'Specifications', _string(payload['specs']));
      add(fields, 'Details', _string(payload['value']));
      add(fields, 'Notes', _string(payload['note']));

      for (final item in components) {
        if (item['archived_at'] != null ||
            item['parent_component_id'] != optionId ||
            item['activity_id'] != option['activity_id']) {
          continue;
        }
        final kind = _string(item['kind']);
        if (!{'spec', 'price', 'note', 'date', 'location', 'link', 'tag', 'contact'}
            .contains(kind)) {
          continue;
        }
        final childPayload = _payload(item);
        final name = _string(item['label']);
        final value = _string(childPayload['value']);
        if (kind == 'price') {
          final money = [
            _string(childPayload['currency']), value,
          ].where((s) => s.isNotEmpty).join(' ');
          add(fields, 'Price', money, override: true);
        } else if (kind == 'contact') {
          final contact = ActivityContact.fromPayload(childPayload);
          add(fields, 'Contact person', contact.person);
          add(fields, 'Phone', contact.phone);
          add(fields, 'Email', contact.email);
          add(fields, 'Address', contact.address);
          add(fields, 'Working hours', contact.workingHours);
          add(fields, 'Contact notes', contact.note);
        } else {
          add(fields, name.isEmpty ? kind : name, value);
        }
      }

      final votes = reactions.where((r) => r['component_id'] == optionId);
      int? myOpinion;
      int? partnerOpinion;
      for (final vote in votes) {
        final number = vote['opinion'];
        final value = number is num ? number.toInt() : null;
        if (value != -1 && value != 0 && value != 1) continue;
        if (vote['user_id'] == currentUserId) {
          myOpinion = value;
        } else if (vote['user_id'] is String) {
          partnerOpinion = value;
        }
      }

      values[optionId] = fields;
      columns.add(ActivityComparisonColumn(
        id: optionId,
        title: _string(option['label']),
        sourceUrl: _string(payload['url']),
        values: Map.unmodifiable(fields),
        myOpinion: myOpinion,
        partnerOpinion: partnerOpinion,
      ));
    }

    final ordered = <String>[];
    for (final key in ['price', 'specifications', 'details']) {
      if (rows.containsKey(key)) ordered.add(key);
    }
    final other = rows.keys.where((key) =>
        !ordered.contains(key) && key != 'notes').toList()
      ..sort((a, b) => rows[a]!.toLowerCase().compareTo(rows[b]!.toLowerCase()));
    ordered.addAll(other);
    if (rows.containsKey('notes')) ordered.add('notes');

    return ActivityComparisonMatrix(
      columns: List.unmodifiable(columns),
      rows: List.unmodifiable([
        for (final key in ordered)
          ActivityComparisonRow(key: key, label: rows[key]!),
      ]),
    );
  }
}
