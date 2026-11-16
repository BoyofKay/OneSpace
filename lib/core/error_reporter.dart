import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/support/support_screens.dart' show AppInfo;

/// R74: crashes and errors are sent automatically (message + first stack
/// lines, app version, platform — never content). Each distinct error is sent
/// once per app run; network drops are ignored.
class ErrorReporter {
  ErrorReporter._();
  static final _sent = <String>{};

  static void report(Object error, StackTrace? stack, {String? context}) {
    if (error is SocketException || error is TimeoutException || error is HttpException) return;
    final text = error.toString();
    if (text.contains('ClientException') || text.contains('Connection closed') ||
        text.contains('Failed host lookup')) {
      return;
    }
    final key = text.length > 200 ? text.substring(0, 200) : text;
    if (_sent.length >= 30 || !_sent.add(key)) return;
    try {
      final lines = (stack?.toString() ?? '').split('\n').take(25).join('\n');
      unawaited(Supabase.instance.client.rpc('log_client_error', params: {
        'p_error': text.length > 1000 ? text.substring(0, 1000) : text,
        'p_stack': lines.length > 4000 ? lines.substring(0, 4000) : lines,
        'p_context': context == null ? null : (context.length > 300 ? context.substring(0, 300) : context),
        'p_app_version': AppInfo.version,
        'p_platform': AppInfo.platform,
      }).then((_) {}, onError: (_) {}));
    } catch (_) {
      // Supabase not ready yet — nothing to do.
    }
  }
}
