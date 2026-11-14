/// Pure, date-safe presentation of the partner check-in request lifecycle.
/// Server-side trigger is the authority for whether an answer can be saved.
/// Legacy entries without expires_at stay open until answered.
class CheckinRequestRules {
  const CheckinRequestRules._();

  static const pending = 'pending';
  static const answered = 'answered';
  static const expired = 'expired';

  static String status(Map<String, dynamic> request, DateTime now) {
    if (request['responded_at'] != null) return answered;
    final deadline = DateTime.tryParse(
      (request['expires_at'] ?? '').toString(),
    );
    if (deadline != null && !now.toUtc().isBefore(deadline.toUtc())) {
      return expired;
    }
    return pending;
  }

  static bool canRespond(
    Map<String, dynamic> request,
    String? currentUserId,
    DateTime now,
  ) =>
      currentUserId != null &&
      request['recipient_id'] == currentUserId &&
      status(request, now) == pending;

  static String category(
    Map<String, dynamic> request,
    String? userId,
    DateTime now,
  ) {
    final state = status(request, now);
    if (state != pending) return 'history';
    return request['recipient_id'] == userId ? 'to_answer' : 'waiting';
  }

  static String label(
    Map<String, dynamic> request,
    DateTime now,
  ) => switch (status(request, now)) {
    answered => 'Answered',
    expired => 'Expired',
    _ => 'Awaiting response',
  };

  static String expiryHint(Map<String, dynamic> request, DateTime now) {
    if (status(request, now) != pending) return '';
    final deadline = DateTime.tryParse(
      (request['expires_at'] ?? '').toString(),
    );
    if (deadline == null) return 'No response deadline';
    final remaining = deadline.toUtc().difference(now.toUtc());
    if (remaining.inHours < 24) return 'Less than a day remaining';
    final days = (remaining.inHours / 24).ceil();
    return '$days days remaining';
  }

  static List<Map<String, dynamic>> filter(
    Iterable<Map<String, dynamic>> requests,
    String categoryName,
    String? userId,
    DateTime now,
  ) {
    final visible = requests.where((request) =>
      categoryName == 'all' || category(request, userId, now) == categoryName
    ).toList();
    visible.sort((a, b) {
      final ad = DateTime.tryParse((a['requested_at'] ?? '').toString());
      final bd = DateTime.tryParse((b['requested_at'] ?? '').toString());
      final date = (bd ?? DateTime(1970))
          .compareTo(ad ?? DateTime(1970));
      if (date != 0) return date;
      return (b['id'] ?? '').toString().compareTo(
        (a['id'] ?? '').toString(),
      );
    });
    return visible;
  }

  static int count(
    Iterable<Map<String, dynamic>> requests,
    String categoryName,
    String? userId,
    DateTime now,
  ) => requests.where(
    (request) => category(request, userId, now) == categoryName,
  ).length;
}
