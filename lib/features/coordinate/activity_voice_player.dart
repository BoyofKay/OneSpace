import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'activity_voice_rules.dart';

/// Compact authenticated voice playback for both components and comments.
/// A new, short-lived signed link is requested on playback, not persisted.
class ActivityVoicePlayer extends StatefulWidget {
  const ActivityVoicePlayer({
    super.key,
    required this.objectPath,
    required this.seconds,
  });

  final String objectPath;
  final int seconds;

  @override
  State<ActivityVoicePlayer> createState() => _ActivityVoicePlayerState();
}

class _ActivityVoicePlayerState extends State<ActivityVoicePlayer> {
  final player = AudioPlayer();
  bool loading = false;
  String? error;
  DateTime? signedAt;

  @override
  void dispose() {
    unawaited(player.dispose());
    super.dispose();
  }

  Future<void> toggle() async {
    if (loading) return;
    if (player.playing) {
      await player.pause();
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final expired = signedAt == null ||
          DateTime.now().difference(signedAt!) > const Duration(seconds: 90);
      if (expired || player.processingState == ProcessingState.completed) {
        final url = await Supabase.instance.client.storage
            .from(ActivityVoiceRules.bucket)
            .createSignedUrl(widget.objectPath, 120);
        await player.setUrl(url);
        signedAt = DateTime.now();
      }
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero);
      }
      if (!mounted) return;
      unawaited(player.play());
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unable to play this private recording.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 38,
              height: 38,
              child: IconButton(
                tooltip: playing ? 'Pause voice note' : 'Play voice note',
                onPressed: loading ? null : toggle,
                icon: loading
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(playing ? Icons.pause_circle_outline :
                        Icons.play_circle_outline),
              ),
            ),
            Text('Voice · ${ActivityVoiceRules.durationLabel(widget.seconds)}',
              style: Theme.of(context).textTheme.bodyMedium),
          ]),
          if (error != null)
            Text(error!, style: TextStyle(
              color: Theme.of(context).colorScheme.error,
            )),
        ]);
      },
    );
  }
}
