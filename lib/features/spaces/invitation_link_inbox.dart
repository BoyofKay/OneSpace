import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_env.dart';
import 'invitation_code.dart';

/// Keeps an incoming invitation through sign-in / device unlock.
/// No invitation is accepted without the recipient pressing "Join space".
class InvitationLinkInbox extends ChangeNotifier {
  InvitationLinkInbox._();
  static final InvitationLinkInbox instance = InvitationLinkInbox._();
  static const _storage = FlutterSecureStorage();
  static const _pendingKey = 'onespace_pending_incoming_invite_v1';

  StreamSubscription<Uri>? _subscription;
  StreamSubscription<AuthState>? _auth;
  String? _pending;
  String? get pendingCode => _pending;
  bool _keepThroughSignOut = false;

  /// QA: an invitation lasts for one sign-in. Signing out forgets it, unless
  /// the person signs out on purpose to sign in with the invited email.
  void keepThroughNextSignOut() => _keepThroughSignOut = true;

  /// Call once Supabase is ready (the signed-in shell does).
  void watchSignOut() {
    if (OneSpaceEnv.usesLegacyBackend || _auth != null) return;
    try {
      _auth = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
        if (s.event == AuthChangeEvent.signedOut) {
          if (_keepThroughSignOut) { _keepThroughSignOut = false; }
          else if (_pending != null) { unawaited(clear()); }
        }
      });
    } catch (_) {/* Supabase not ready (tests): nothing to forget. */}
  }

  Future<void> start() async {
    if (_subscription != null) return;
    final links = AppLinks();
    // Begin listening first: don't lose links delivered while starting.
    _subscription = links.uriLinkStream.listen((uri) {
      unawaited(_receive(uri));
    }, onError: (Object _) {
      // A malformed external link must never interrupt authentication.
    });

    try {
      final saved = await _storage.read(key: _pendingKey);
      final valid = saved == null ? null : normalizedInvitationCode(saved);
      if (_pending == null && valid != null) {
        _pending = valid;
        notifyListeners();
      }
    } catch (_) {
      // Keystore unavailability does not block an invite received now.
    }
    try {
      final initial = await links.getInitialLink();
      if (initial != null) await _receive(initial);
    } catch (_) {
      // Continue to support in-app manual code entry.
    }
  }

  Future<void> _receive(Uri uri) async {
    final code = invitationCodeFromUri(uri, qa: !OneSpaceEnv.usesLegacyBackend);
    if (code == null || code == _pending) return;
    _pending = code;
    try {
      // Persist before notifying. A successful join can immediately clear
      // the invite; a delayed write must never resurrect an accepted code.
      await _storage.write(key: _pendingKey, value: code);
    } catch (_) {
      // In-memory code is still available for this session.
    }
    notifyListeners();
  }

  /// QA-only recovery if the browser invitation link was lost during sign in.
  /// Server verifies the signed-in email before exposing its own invitation.
  Future<void> rememberVerifiedQaAddressedCode(String code) async {
    if (OneSpaceEnv.usesLegacyBackend ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(code)) return;
    await _receive(invitationAppLink(code.toLowerCase(), qa: true));
  }

  Future<void> clear() async {
    _pending = null;
    notifyListeners();
    try {
      await _storage.delete(key: _pendingKey);
    } catch (_) {}
  }
}
