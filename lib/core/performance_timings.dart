import 'package:flutter/foundation.dart';

/// Local, transient timings only. No account IDs, tokens, emails, titles, or
/// network payloads. Values are reset when the app process is restarted.
class PerformanceTimings {
  PerformanceTimings._();
  static final instance = PerformanceTimings._();
  final ValueNotifier<Map<String, int>> measurements =
      ValueNotifier<Map<String, int>>(const {});

  void record(String stage, Duration duration) {
    measurements.value = {
      ...measurements.value,
      stage: duration.inMilliseconds,
    };
  }

  String get report {
    if (measurements.value.isEmpty) return 'No timings collected yet.';
    return measurements.value.entries
        .map((entry) => '${entry.key}: ${entry.value} ms')
        .join('\n');
  }
}
