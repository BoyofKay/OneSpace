import 'package:material_ui/material_ui.dart';

/// R54 (spec 2.6): how an item's outcome looks in every list.
/// Completed family: struck through, muted, green check. Cancelled: struck
/// through, red cross. Missed: muted with an amber tag (no strike). Anything
/// else looks normal.
class StatusLook {
  const StatusLook._();

  static const completedFamily = {'completed', 'done', 'celebrated', 'enjoyed',
    'watched', 'purchased', 'booked', 'delivered', 'registered'};

  static bool isCompleted(String? status) => completedFamily.contains(status);
  static bool isCancelled(String? status) => status == 'cancelled';
  static bool isMissed(String? status) => status == 'missed';
  static bool isFinal(String? status) =>
      isCompleted(status) || isCancelled(status) || isMissed(status);

  /// Title style for a list row, built on [base].
  static TextStyle? title(BuildContext context, String? status, [TextStyle? base]) {
    final colors = Theme.of(context).colorScheme;
    if (isCompleted(status)) {
      return (base ?? const TextStyle()).copyWith(
          decoration: TextDecoration.lineThrough, color: colors.onSurfaceVariant);
    }
    if (isCancelled(status)) {
      return (base ?? const TextStyle()).copyWith(
          decoration: TextDecoration.lineThrough, color: colors.onSurfaceVariant);
    }
    if (isMissed(status)) {
      return (base ?? const TextStyle()).copyWith(color: colors.onSurfaceVariant);
    }
    return base;
  }

  /// The leading mark for a finished item, or null to keep the row's own icon.
  static Widget? mark(String? status) {
    if (isCompleted(status)) {
      return const Icon(Icons.check_circle, color: Color(0xFF2E7D32));
    }
    if (isCancelled(status)) {
      return const Icon(Icons.cancel, color: Color(0xFFC62828));
    }
    if (isMissed(status)) {
      return const Icon(Icons.error_outline, color: Color(0xFFF9A825));
    }
    return null;
  }
}
