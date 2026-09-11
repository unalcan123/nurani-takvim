import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'media_player_controller.dart';

String _formatDuration(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = d.inHours;
  return hours > 0
      ? '$hours:$minutes:$seconds'
      : '${d.inMinutes}:$seconds';
}

/// Aranabilir (seek), duraklat/devam ettir kontrollü tam ekran oynatıcı
/// paneli. [NowPlayingBar]'a dokunulunca alttan açılır.
class FullPlayerSheet extends ConsumerWidget {
  const FullPlayerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(mediaPlayerControllerProvider);
    return ValueListenableBuilder<MediaTrack?>(
      valueListenable: controller.currentTrack,
      builder: (context, track, _) {
        if (track == null) return const SizedBox.shrink();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Icon(
                  Icons.graphic_eq,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  track.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (track.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    track.subtitle!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 8),
                StreamBuilder<Duration>(
                  stream: controller.positionStream,
                  builder: (context, positionSnapshot) {
                    final position = positionSnapshot.data ?? Duration.zero;
                    return StreamBuilder<Duration?>(
                      stream: controller.durationStream,
                      builder: (context, durationSnapshot) {
                        final duration = durationSnapshot.data ??
                            controller.duration ??
                            Duration.zero;
                        final maxMs = duration.inMilliseconds > 0
                            ? duration.inMilliseconds.toDouble()
                            : 1.0;
                        final valueMs = position.inMilliseconds
                            .clamp(0, maxMs.toInt())
                            .toDouble();
                        return Column(
                          children: [
                            Slider(
                              value: valueMs,
                              max: maxMs,
                              onChanged: (v) => controller.seek(
                                Duration(milliseconds: v.toInt()),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_formatDuration(position)),
                                  Text(_formatDuration(duration)),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 8),
                StreamBuilder<PlayerState>(
                  stream: controller.playerStateStream,
                  builder: (context, snapshot) {
                    final playing = snapshot.data?.playing ?? false;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          iconSize: 40,
                          icon: const Icon(Icons.replay_10),
                          onPressed: () => controller.seek(
                            controller.position - const Duration(seconds: 10),
                          ),
                        ),
                        const SizedBox(width: 16),
                        IconButton.filled(
                          iconSize: 48,
                          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                          onPressed: () =>
                              playing ? controller.pause() : controller.resume(),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          iconSize: 40,
                          icon: const Icon(Icons.forward_10),
                          onPressed: () => controller.seek(
                            controller.position + const Duration(seconds: 10),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
