import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'voice.dart';
import 'voice_assistant.dart';
import 'voice_commands.dart';
import 'package:onespace/l10n/phrases.dart';

/// R61: the OneSpace listening sheet — a hands-free conversation.
///
/// Listen → show the words live → do it → say the answer → listen again
/// ("Anything else?") until the person says "no", stays quiet twice, or
/// closes the sheet. Pages that need a tap (editors) close the sheet and open.
class VoiceSessionSheet extends StatefulWidget {
  const VoiceSessionSheet({super.key, this.goToday});
  final VoidCallback? goToday;

  static Future<void> show(BuildContext context, {VoidCallback? goToday}) async {
    final page = await showModalBottomSheet<Widget>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => VoiceSessionSheet(goToday: goToday));
    await Voice.stopSpeaking();
    await Voice.cancelListening();
    if (page != null && context.mounted) {
      await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => page));
    }
  }

  @override
  State<VoiceSessionSheet> createState() => _VoiceSessionSheetState();
}

enum _Phase { listening, thinking, speaking, idle }

class _Turn {
  _Turn(this.heard, this.reply);
  final String heard;
  String reply;
}

class _VoiceSessionSheetState extends State<VoiceSessionSheet> {
  _Phase phase = _Phase.idle;
  final turns = <_Turn>[];
  VoiceCommand? pendingChoice;
  String? problem;
  int silent = 0;
  bool closed = false;
  late String lang;
  bool showHelp = false;

  bool get ar => lang == 'ar';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    lang = Voice.languageOf(context);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  @override
  void dispose() {
    closed = true;
    super.dispose();
  }

  Future<void> _listen() async {
    if (closed || !mounted) return;
    setState(() { phase = _Phase.listening; problem = null; });
    String? heard;
    try {
      heard = await Voice.listenOnce(lang);
    } on VoiceError catch (e) {
      if (mounted) setState(() { phase = _Phase.idle; problem = e.message(ar); });
      return;
    }
    if (closed || !mounted) return;
    if (heard == null || heard.trim().isEmpty) {
      silent++;
      if (silent >= 2 || turns.isNotEmpty) { _close(); return; }
      setState(() => phase = _Phase.idle);
      return;
    }
    silent = 0;
    await _run(VoiceCommandRules.parse(heard, DateTime.now()));
  }

  Future<void> _run(VoiceCommand command) async {
    // Reply in the language the person spoke.
    lang = command.lang == 'ar' ? 'ar' : (VoiceCommandRules.isArabic(command.heard) ? 'ar' : command.lang);
    final turn = _Turn(command.heard, '…');
    setState(() { phase = _Phase.thinking; turns.add(turn); pendingChoice = null; showHelp = false; });
    final reply = await VoiceAssistant.handle(command);
    if (closed || !mounted) return;
    setState(() {
      turn.reply = reply.say;
      if (reply.choices) pendingChoice = command;
      if (command.action == VoiceAction.help) showHelp = true;
    });
    if (reply.goToday) widget.goToday?.call();
    if (reply.open != null) {
      if (reply.say.isNotEmpty) unawaited(Voice.say(reply.say, language: lang));
      if (mounted) Navigator.of(context).pop(reply.open);
      return;
    }
    if (reply.say.isNotEmpty) {
      setState(() => phase = _Phase.speaking);
      await Voice.say(reply.say, language: lang);
    }
    if (closed || !mounted) return;
    if (reply.end) { _close(); return; }
    if (reply.choices || command.action == VoiceAction.help) {
      setState(() => phase = _Phase.idle);
      return;
    }
    await _listen();
  }

  void _close() {
    if (closed || !mounted) return;
    closed = true;
    Navigator.of(context).maybePop();
  }

  void _choose(VoiceAction a) {
    final c = pendingChoice;
    if (c == null) return;
    _run(VoiceCommand(a, title: c.title, when: a == VoiceAction.event ? DateTime.now() : null,
      heard: c.heard, lang: c.lang));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String t(String en, String a) => ar ? a : en;
    final status = switch (phase) {
      _Phase.listening => turns.isEmpty ? t('Listening…', 'أستمع…') : t('Anything else?', 'شيء آخر؟'),
      _Phase.thinking => t('On it…', 'لحظة…'),
      _Phase.speaking => t('Speaking…', 'أتحدث…'),
      _Phase.idle => t('Tap the mic to talk', 'اضغط الميكروفون للتحدث'),
    };
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: SafeArea(child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .75),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(Icons.graphic_eq, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(tt(status), style: theme.textTheme.titleMedium)),
              IconButton(tooltip: t('Close', 'إغلاق'), icon: const Icon(Icons.close), onPressed: _close),
            ]),
            Flexible(child: ListView(shrinkWrap: true, reverse: false, children: [
              for (final turn in turns) ...[
                Align(alignment: AlignmentDirectional.centerEnd, child: Container(
                  margin: const EdgeInsets.only(top: 8, left: 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16)),
                  child: Text(tt(turn.heard), style: TextStyle(color: scheme.onPrimaryContainer)))),
                Align(alignment: AlignmentDirectional.centerStart, child: Container(
                  margin: const EdgeInsets.only(top: 6, right: 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16)),
                  child: Text(tt(turn.reply)))),
              ],
              if (showHelp || turns.isEmpty && phase != _Phase.listening) Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tt(t('You can say', 'يمكنك أن تقول')), style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  for (final e in ar ? VoiceAssistant.examplesAr : VoiceAssistant.examplesEn)
                    Padding(padding: const EdgeInsets.only(bottom: 6),
                      child: Text(tt(e), style: theme.textTheme.bodyMedium)),
                ])),
              if (pendingChoice != null) Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final o in [
                    (VoiceAction.reminder, Icons.alarm_add_outlined, t('Reminder', 'تذكير')),
                    (VoiceAction.note, Icons.note_add_outlined, t('Note', 'ملاحظة')),
                    (VoiceAction.event, Icons.event_outlined, t('Event', 'موعد')),
                    (VoiceAction.newList, Icons.checklist_outlined, t('To-do list', 'قائمة')),
                  ]) ActionChip(avatar: Icon(o.$2, size: 18), label: Text(tt(o.$3)), onPressed: () => _choose(o.$1)),
                ])),
            ])),
            if (phase == _Phase.listening) ValueListenableBuilder<String>(
              valueListenable: Voice.partial,
              builder: (_, words, __) => words.isEmpty ? const SizedBox(height: 8) : Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(tt(words), textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(color: scheme.primary)))),
            if (problem != null) Padding(padding: const EdgeInsets.only(top: 10),
              child: Text(tt(problem!), style: TextStyle(color: scheme.error))),
            const SizedBox(height: 14),
            _MicButton(phase: phase,
              onTap: () {
                if (phase == _Phase.listening) { Voice.stopListening(); return; }
                if (phase == _Phase.speaking) { Voice.stopSpeaking(); return; }
                silent = 0;
                _listen();
              }),
            const SizedBox(height: 6),
            Text(tt(phase == _Phase.speaking ? t('Tap to stop', 'اضغط للإيقاف')
              : phase == _Phase.listening ? t('Tap when you’re done', 'اضغط عند الانتهاء') : ''),
              style: theme.textTheme.bodySmall),
          ]),
        ),
      )),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.phase, required this.onTap});
  final _Phase phase;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<double>(
      valueListenable: Voice.level,
      builder: (_, level, __) {
        final grow = phase == _Phase.listening ? 1 + level * .35 : 1.0;
        return GestureDetector(onTap: onTap, child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 76 * grow, height: 76 * grow,
          decoration: BoxDecoration(shape: BoxShape.circle,
            color: phase == _Phase.listening ? scheme.primary : scheme.primaryContainer,
            boxShadow: phase == _Phase.listening ? [BoxShadow(color: scheme.primary.withValues(alpha: .35),
              blurRadius: 18 * grow, spreadRadius: 2)] : null),
          child: Icon(
            phase == _Phase.speaking ? Icons.stop_rounded : phase == _Phase.thinking ? Icons.more_horiz : Icons.mic,
            size: 34,
            color: phase == _Phase.listening ? scheme.onPrimary : scheme.onPrimaryContainer)));
      });
  }
}
