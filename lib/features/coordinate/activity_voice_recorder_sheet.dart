import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'activity_voice_rules.dart';
import 'activity_voice_service.dart';

/// Record → Stop → Preview → Send or Discard.
/// No recording starts until the user explicitly taps Record and grants mic
/// permission. The draft stays on the device when an upload fails.
class ActivityVoiceRecorderSheet extends StatefulWidget {
  const ActivityVoiceRecorderSheet({
    super.key,
    required this.activityId,
    required this.destination,
    this.parentComponentId,
    this.replyToCommentId,
    this.relatedComponentId,
    this.contextLabel,
  });

  final String activityId;
  final VoiceDestination destination;
  final String? parentComponentId;
  final String? replyToCommentId;
  final String? relatedComponentId;
  final String? contextLabel;

  @override
  State<ActivityVoiceRecorderSheet> createState() =>
      _ActivityVoiceRecorderSheetState();
}

class _ActivityVoiceRecorderSheetState extends State<ActivityVoiceRecorderSheet>
    with WidgetsBindingObserver {
  final recorder = AudioRecorder();
  final preview = AudioPlayer();
  Timer? ticker;
  DateTime? startedAt;
  String? draftPath;
  bool recording = false;
  bool sending = false;
  bool busy = false;
  bool previewReady = false;
  bool foreground = true;
  int seconds = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The microphone button that opened this sheet IS the user's explicit
    // Record action. No redundant second 'Record' tap is required.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(startRecording());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground && recording) {
      // Never keep capturing audio after the app leaves the foreground.
      unawaited(stopRecording());
    }
  }

  Future<void> startRecording() async {
    if (recording || busy || sending) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!await recorder.hasPermission()) {
        throw const FormatException(
          'Microphone permission is required to record a voice note.');
      }
      if (!mounted || !foreground) return;
      await deleteDraft();
      final folder = await getTemporaryDirectory();
      final path = '${folder.path}/onespace-${const Uuid().v4()}.m4a';
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) {
        await recorder.cancel();
        return;
      }
      setState(() {
        draftPath = path;
        startedAt = DateTime.now();
        seconds = 0;
        recording = true;
        previewReady = false;
      });
      ticker?.cancel();
      ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !recording || startedAt == null) return;
        final elapsed = DateTime.now().difference(startedAt!).inSeconds;
        if (elapsed >= ActivityVoiceRules.maxSeconds) {
          unawaited(stopRecording());
        } else {
          setState(() => seconds = elapsed);
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = 'Could not start recording: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> stopRecording() async {
    if (!recording || busy || sending) return;
    setState(() => busy = true);
    ticker?.cancel();
    try {
      final path = await recorder.stop();
      final elapsed = startedAt == null
          ? 0 : DateTime.now().difference(startedAt!).inSeconds;
      if (mounted) {
        setState(() {
          recording = false;
          draftPath = path;
          seconds = elapsed < 0 ? 0 :
              (elapsed > ActivityVoiceRules.maxSeconds
                  ? ActivityVoiceRules.maxSeconds : elapsed);
          if (path == null || elapsed < 1) {
            error = 'Record at least one second before sending.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          recording = false;
          error = 'Could not stop recording: $e';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> togglePreview() async {
    final path = draftPath;
    if (path == null || recording || sending || busy) return;
    try {
      if (preview.playing) {
        await preview.pause();
      } else {
        if (!previewReady) {
          await preview.setFilePath(path);
          previewReady = true;
        }
        if (preview.processingState == ProcessingState.completed) {
          await preview.seek(Duration.zero);
        }
        unawaited(preview.play());
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to preview this recording.');
    }
  }

  Future<void> deleteDraft() async {
    await preview.stop();
    previewReady = false;
    final path = draftPath;
    draftPath = null;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> discardAndClose() async {
    if (sending || busy) return;
    setState(() => busy = true);
    ticker?.cancel();
    try {
      if (recording) {
        await recorder.cancel();
        recording = false;
      }
      await deleteDraft();
      if (mounted) Navigator.of(context).pop(false);
    } catch (e) {
      if (mounted) setState(() => error = 'Unable to discard recording: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> sendVoice() async {
    final path = draftPath;
    if (path == null || recording || busy || sending) return;
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final bytes = await File(path).readAsBytes();
      ActivityVoiceRules.validate(bytes, seconds);
      await ActivityVoiceService(Supabase.instance.client).send(
        bytes: bytes,
        seconds: seconds,
        activityId: widget.activityId,
        destination: widget.destination,
        parentComponentId: widget.parentComponentId,
        replyToCommentId: widget.replyToCommentId,
        relatedComponentId: widget.relatedComponentId,
      );
      await deleteDraft();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // Keep the local file intact; user can retry or explicitly discard it.
      if (mounted) setState(() => error = 'Unable to send. Retry or discard. $e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _deleteIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Temporary local files may already be removed by the OS.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker?.cancel();
    if (recording) unawaited(recorder.cancel());
    unawaited(recorder.dispose());
    unawaited(preview.dispose());
    final path = draftPath;
    if (path != null) {
      unawaited(_deleteIfExists(path));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = draftPath != null && !recording && seconds >= 1;
    final isComment = widget.destination == VoiceDestination.comment;
    final title = isComment ? 'Voice message' : 'Activity voice note';
    final status = busy
        ? 'Opening microphone…'
        : recording
            ? 'Recording — tap Stop when finished'
            : ready
                ? 'Ready to share · listen first if you want'
                : error == null ? 'Microphone is ready' : 'Try recording again';

    return PopScope(
      canPop: false,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16,
              MediaQuery.viewInsetsOf(context).bottom + 12),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.mic_rounded, size: 22),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title,
                    style: Theme.of(context).textTheme.titleMedium)),
                  IconButton(
                    tooltip: 'Discard voice recording',
                    onPressed: sending || busy ? null : discardAndClose,
                    icon: const Icon(Icons.close),
                  ),
                ]),
                if (widget.contextLabel case final String contextLabel)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(contextLabel, maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                  ),
                Text(status, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 10),
                Row(children: [
                  Icon(
                    recording ? Icons.fiber_manual_record :
                    ready ? Icons.check_circle_outline :
                    Icons.mic_none_outlined,
                    size: 20,
                    color: recording ? Theme.of(context).colorScheme.error
                      : null,
                  ),
                  const SizedBox(width: 6),
                  Text(ActivityVoiceRules.durationLabel(seconds),
                    style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  if (recording)
                    FilledButton.icon(
                      onPressed: busy ? null : stopRecording,
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('Stop'),
                    )
                  else if (ready)
                    FilledButton.icon(
                      onPressed: sending ? null : sendVoice,
                      icon: sending
                          ? const SizedBox(width: 17, height: 17,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded),
                      label: Text(sending ? 'Sending…' : 'Send'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: busy ? null : startRecording,
                      icon: const Icon(Icons.mic_rounded),
                      label: const Text('Try again'),
                    ),
                ]),
                if (ready) ...[
                  const SizedBox(height: 7),
                  StreamBuilder<PlayerState>(
                    stream: preview.playerStateStream,
                    builder: (context, snapshot) => Row(children: [
                      OutlinedButton.icon(
                        onPressed: sending ? null : togglePreview,
                        icon: Icon(snapshot.data?.playing == true
                            ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        label: Text(snapshot.data?.playing == true
                            ? 'Pause preview' : 'Play preview'),
                      ),
                      const Spacer(),
                      Text('Max 2 minutes',
                          style: Theme.of(context).textTheme.labelSmall),
                    ]),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 7),
                  Text(error!, style: TextStyle(
                    color: Theme.of(context).colorScheme.error)),
                ],
                if (!recording) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: sending || busy ? null : discardAndClose,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Discard'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
