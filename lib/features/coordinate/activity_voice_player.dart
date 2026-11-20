import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'activity_media_scope.dart';
import 'activity_voice_rules.dart';
import 'package:onespace/l10n/phrases.dart';

/// One compact audio control, reused by chat bubbles and Activity components.
/// Playback remains authenticated; no signed URL is persisted or shown publicly.
/// The audio isn't fetched until a partner presses Play.
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
          DateTime.now().difference(signedAt!) >
              const Duration(seconds: 90);
      if (expired) {
        final db = Supabase.instance.client;
        final activityId = ActivityMediaScope.activityIdFromPath(widget.objectPath);
        final bucket = await ActivityMediaScope.voiceBucket(db, activityId);
        final url = await db.storage.from(bucket)
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
        setState(() => error = 'Unable to play this private voice note.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, playback) => StreamBuilder<Duration>(
        stream: player.positionStream,
        builder: (context, positionSnapshot) {
          final playing = playback.data?.playing ?? false;
          final actual = player.duration?.inMilliseconds ?? 0;
          final fallback = widget.seconds > 0
              ? widget.seconds * 1000 : 1000;
          final total = actual > 0 ? actual : fallback;
          final elapsed = positionSnapshot.data?.inMilliseconds ?? 0;
          final shown = elapsed > total ? total : elapsed;
          final enabled = player.duration != null && !loading;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: playing ? tt('Pause recording') : tt('Play recording'),
                    onPressed: loading ? null : toggle,
                    icon: loading
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(playing ? Icons.pause_circle_filled :
                            Icons.play_circle_fill, size: 33),
                  ),
                ),
                Expanded(
                  child: Semantics(
                    label: tt('Voice note playback position'),
                    child: Slider(
                      value: shown.toDouble(),
                      min: 0,
                      max: total.toDouble(),
                      onChanged: enabled ? (value) {
                        unawaited(player.seek(
                          Duration(milliseconds: value.round())));
                      } : null,
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    tt(ActivityVoiceRules.durationLabel(
                      ((total - shown) / 1000).ceil(),
                    )),
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ]),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(tt(error!), style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  )),
                ),
            ],
          );
        },
      ),
    );
  }
}
