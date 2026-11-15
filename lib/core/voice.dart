import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// R60–R61: speaking and listening, on the phone only. The recognizer and the
/// text-to-speech engine both run on the device; OneSpace never records or
/// uploads audio — only the recognized words reach the app.
class Voice {
  /// R64 (Ahmed): voice is hidden until it is mature. Flip to true to bring
  /// back the mic in the top bar and the "Voice command" icon shortcut.
  static const enabled = false;

  Voice._();
  static const _speech = MethodChannel('onespace/checklist_speech');
  static const _voice = MethodChannel('onespace/voice');

  /// Live state for the listening sheet.
  static final partial = ValueNotifier<String>('');
  static final level = ValueNotifier<double>(0);
  static final listening = ValueNotifier<bool>(false);
  static final speaking = ValueNotifier<bool>(false);

  static Completer<String?>? _final;
  static Completer<void>? _spoken;
  static VoidCallback? onLaunchVoice;
  static bool _wired = false;

  static void _wire() {
    if (_wired) return;
    _wired = true;
    _voice.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onReady':
          listening.value = true;
        case 'onPartial':
          partial.value = call.arguments?.toString() ?? '';
        case 'onLevel':
          final v = (call.arguments as num?)?.toDouble() ?? 0;
          level.value = ((v + 2) / 12).clamp(0.0, 1.0);
        case 'onEnd':
          listening.value = false;
        case 'onFinal':
          listening.value = false;
          final text = call.arguments?.toString() ?? '';
          if (text.isNotEmpty) partial.value = text;
          _final?.complete(text.isEmpty ? null : text);
          _final = null;
        case 'onError':
          listening.value = false;
          _final?.completeError(VoiceError(call.arguments?.toString() ?? 'error'));
          _final = null;
        case 'onSpeechDone':
          speaking.value = false;
          _spoken?.complete();
          _spoken = null;
        case 'launchVoice':
          onLaunchVoice?.call();
      }
    });
  }

  /// Call once at start-up; [onLaunch] runs when opened from the
  /// "Voice command" app shortcut.
  static Future<void> init(VoidCallback onLaunch) async {
    _wire();
    onLaunchVoice = onLaunch;
    try {
      final pending = await _voice.invokeMethod<bool>('takeLaunch');
      if (pending == true) onLaunch();
    } catch (_) {}
  }

  static String languageOf(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ar' ? 'ar' : 'en';

  /// Listens once with the in-app recognizer; returns the words (or null if
  /// nothing was heard). Throws [VoiceError] for permission/availability.
  static Future<String?> listenOnce(String language) async {
    _wire();
    partial.value = '';
    level.value = 0;
    await _final?.future.catchError((_) => null);
    final done = Completer<String?>();
    _final = done;
    try {
      await _voice.invokeMethod<bool>('start', {'language': language == 'ar' ? 'ar-SA' : 'en-US'});
    } on MissingPluginException {
      _final = null;
      throw const VoiceError('unavailable');
    }
    return done.future.timeout(const Duration(seconds: 20), onTimeout: () {
      _final = null;
      cancelListening();
      return null;
    }).catchError((Object e) {
      if (e is VoiceError && e.code == 'nothing') return null;
      throw e;
    });
  }

  static Future<void> stopListening() async {
    try { await _voice.invokeMethod<void>('stop'); } catch (_) {}
  }

  static Future<void> cancelListening() async {
    listening.value = false;
    try { await _voice.invokeMethod<void>('cancel'); } catch (_) {}
  }

  /// Speaks [text] and completes when the phone has finished saying it.
  static Future<void> say(String text, {String language = 'en'}) async {
    _wire();
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return;
    final done = Completer<void>();
    _spoken = done;
    speaking.value = true;
    try {
      await _speech.invokeMethod<void>('speak', {'text': clean, 'language': language, 'rate': 1.0});
    } catch (_) {
      speaking.value = false;
      _spoken = null;
      return;
    }
    final estimate = Duration(milliseconds: 1500 + clean.length * 75);
    await done.future.timeout(estimate, onTimeout: () { speaking.value = false; _spoken = null; });
  }

  static Future<void> stopSpeaking() async {
    speaking.value = false;
    _spoken?.complete();
    _spoken = null;
    try { await _speech.invokeMethod<void>('stop'); } catch (_) {}
  }
}

class VoiceError implements Exception {
  const VoiceError(this.code);
  final String code;
  String message(bool arabic) => switch (code) {
    'permission' => arabic ? 'اسمح لـ OneSpace باستخدام الميكروفون من إعدادات الهاتف.'
        : 'Allow OneSpace to use the microphone in your phone settings.',
    'unavailable' => arabic ? 'التعرف على الكلام غير متاح على هذا الهاتف.'
        : 'Speech recognition is not available on this phone.',
    'network' => arabic ? 'تحقق من الاتصال بالإنترنت وحاول مرة أخرى.'
        : 'Check your internet connection and try again.',
    _ => arabic ? 'لم أتمكن من السماع. حاول مرة أخرى.' : "I couldn't hear that. Try again.",
  };
}
