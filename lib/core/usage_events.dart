import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/support/support_screens.dart' show AppInfo;
import 'app_env.dart';

/// D78: privacy-light usage events, so the Command Center can show session
/// length, which tabs/screens are used and how often notifications are opened.
///
/// Only an event NAME, an optional number (seconds) and a time are sent —
/// never titles, notes, names, messages, photos or anything typed.
/// Names follow `kind` or `kind/Detail` (e.g. `tab/today`, `screen/TripsScreen`,
/// `session_end` with seconds, `push_open/notification`). Events are batched and
/// sent through `log_app_events` (signed-in users only, rate-limited server-side,
/// kept 180 days, deleted with the account). People can switch it off in
/// Settings → Privacy → "Share usage statistics".
class UsageEvents with WidgetsBindingObserver {
  UsageEvents._();
  static final UsageEvents instance = UsageEvents._();
  static const _prefKey = 'onespace.usage_events.enabled';
  static final _valid = RegExp(r'^[a-z0-9_]+(/[A-Za-z0-9_.-]+)?$');

  final List<Map<String, Object?>> _queue = [];
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);
  DateTime? _sessionStart;
  bool _started = false;

  /// Called once the signed-in home screen is shown.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      enabled.value = (await SharedPreferences.getInstance()).getBool(_prefKey) ?? true;
    } catch (_) {}
    WidgetsBinding.instance.addObserver(this);
    _beginSession();
    try {
      // The next person who signs in on this phone starts their own session.
      Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        if (state.event == AuthChangeEvent.signedIn && _sessionStart == null) {
          _beginSession();
        } else if (state.event == AuthChangeEvent.signedOut) {
          _sessionStart = null;
          _queue.clear();
        }
      });
    } catch (_) {}
    Timer.periodic(const Duration(seconds: 60), (_) => flush());
  }

  Future<void> setEnabled(bool on) async {
    enabled.value = on;
    if (!on) _queue.clear();
    try { (await SharedPreferences.getInstance()).setBool(_prefKey, on); } catch (_) {}
  }

  /// Records one event. Unknown/unsafe names are ignored, never sent.
  void log(String name, {int? seconds}) {
    if (!enabled.value || !_valid.hasMatch(name) || name.length > 80) return;
    if (_queue.length >= 300) return;
    final uid = _uid();
    if (uid == null) return;
    _queue.add({
      'u': uid,
      'n': name,
      if (seconds != null) 'v': seconds.clamp(0, 86400),
      't': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// A screen opened with `Navigator.push`, named by its widget class.
  void screen(Widget page) => log('screen/${page.runtimeType}'.replaceAll(RegExp(r'[^A-Za-z0-9_./-]'), ''));

  void _beginSession() {
    _sessionStart = DateTime.now();
    log('session_start');
  }

  void _endSession() {
    final began = _sessionStart;
    if (began == null) return;
    _sessionStart = null;
    log('session_end', seconds: DateTime.now().difference(began).inSeconds);
    unawaited(flush());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_sessionStart == null) _beginSession();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _endSession();
    }
  }

  static String? _uid() {
    try { return Supabase.instance.client.auth.currentUser?.id; } catch (_) { return null; }
  }

  /// Call before an intentional sign-out, while the session is still valid,
  /// so this person's last events are sent as theirs.
  Future<void> flushBeforeSignOut() async {
    final began = _sessionStart;
    _sessionStart = null;
    if (began != null) {
      log('session_end', seconds: DateTime.now().difference(began).inSeconds);
    }
    try { await flush().timeout(const Duration(seconds: 3)); } catch (_) {}
    _queue.clear();
  }

  Future<void> flush() async {
    if (_queue.isEmpty || !enabled.value) return;
    final db = Supabase.instance.client;
    final uid = db.auth.currentUser?.id;
    if (uid == null) { _queue.clear(); return; }
    // Events recorded while someone else was signed in on this phone are
    // never sent under the current account.
    _queue.removeWhere((e) => e['u'] != uid);
    if (_queue.isEmpty) return;
    final batch = _queue.take(200)
        .map((e) => Map<String, Object?>.of(e)..remove('u')).toList();
    _queue.removeRange(0, batch.length);
    try {
      await db.rpc('log_app_events', params: {
        'p_events': batch,
        'p_platform': AppInfo.platform,
        'p_app_version': '${AppInfo.version}${OneSpaceEnv.isProduction ? '' : '-qa'}',
      });
    } catch (_) {
      // Offline or the function is not deployed yet: drop quietly, never retry forever.
    }
  }
}
