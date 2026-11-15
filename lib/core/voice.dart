import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// R60: speak and listen, device-only. Text-to-speech and the speech
/// recognizer both run on the phone; OneSpace never records or uploads audio.
class Voice {
  const Voice._();
  static const _speech = MethodChannel('onespace/checklist_speech');
  static const _listen = MethodChannel('onespace/voice');
  static final speaking = ValueNotifier<bool>(false);
  static Timer? _reset;

  static String languageOf(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ar' ? 'ar' : 'en';

  /// Reads [text] aloud; shows a "Stop" bar while it speaks.
  static Future<void> speak(BuildContext context, String text) async {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await _speech.invokeMethod<void>('speak', {'text': clean, 'language': languageOf(context), 'rate': 1.0});
      speaking.value = true;
      _reset?.cancel();
      // Roughly how long it takes to say it; the Stop bar hides afterwards.
      final seconds = (clean.split(' ').length / 2.6).ceil().clamp(2, 600);
      _reset = Timer(Duration(seconds: seconds), () => speaking.value = false);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(
        duration: Duration(seconds: seconds),
        content: const Row(children: [Icon(Icons.volume_up, color: Colors.white), SizedBox(width: 10),
          Expanded(child: Text('Reading aloud…'))]),
        action: SnackBarAction(label: 'Stop', onPressed: stop)));
    } on PlatformException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.message ?? 'Reading aloud is not available.')));
    } on MissingPluginException {
      messenger?.showSnackBar(const SnackBar(content: Text('Reading aloud is not available here.')));
    }
  }

  static Future<void> stop() async {
    speaking.value = false;
    _reset?.cancel();
    try { await _speech.invokeMethod<void>('stop'); } catch (_) {}
  }

  /// Opens the phone's speech recognizer; returns what was heard (or null).
  static Future<String?> listen(BuildContext context, {String? prompt}) async {
    final lang = languageOf(context) == 'ar' ? 'ar-SA' : 'en-US';
    try {
      return await _listen.invokeMethod<String>('listen', {'language': lang,
        'prompt': prompt ?? 'Say what you want to do'});
    } on PlatformException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message ?? 'Speech recognition is not available.')));
      }
    } on MissingPluginException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Voice commands are not available here.')));
      }
    }
    return null;
  }
}

