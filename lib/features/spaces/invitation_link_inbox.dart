import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  String? _pending;
  String? get pendingCode => _pending;

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
    final code = invitationCodeFromUri(uri, qa: !OneSpaceEnv.isProduction);
    if (code == null || code == _pending) return;
    _pending = code;
    notifyListeners();
    try {
      await _storage.write(key: _pendingKey, value: code);
    } catch (_) {
      // In memory remains available for this session.
    }
  }

  Future<void> clear() async {
    _pending = null;
    notifyListeners();
    try {
      await _storage.delete(key: _pendingKey);
    } catch (_) {}
  }
}
