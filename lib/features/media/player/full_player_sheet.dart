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

/// Aranabilir (seek), önceki/sonraki sûreye geçiş ve duraklat/devam ettir
/// kontrollü tam ekran oynatıcı paneli. [NowPlayingBar]'a dokunulunca alttan
/// açılır.
class FullPlayerSheet extends ConsumerWidget {
  const FullPlayerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(mediaPlayerControllerProvider);
    return ValueListenableBuilder<MediaTrack?>(
      valueListenable: controller.currentTrack,
      builder: (context, track, _) {
        if (track == null) return const SizedBox.shrink();
        final textTheme = Theme.of(context).textTheme;
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
                // Sûre/bölüm adı: mevcut boyuttan (~16) yaklaşık %35 büyük.
                Text(
                  track.title,
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (track.subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    track.subtitle!,
                    textAlign: TextAlign.center,
                    style: textTheme.titleMedium?.copyWith(
                      color: textTheme.bodyMedium?.color,
                    ),
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
                                  Text(
                                    _formatDuration(position),
                                    style: textTheme.bodyLarge?.copyWith(
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                  Text(
                                    _formatDuration(duration),
                                    style: textTheme.bodyLarge?.copyWith(
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
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
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          iconSize: 32,
                          tooltip: 'Önceki Sûre',
                          icon: const Icon(Icons.skip_previous),
                          onPressed: controller.hasPrevious
                              ? controller.playPreviousSurah
                              : null,
                        ),
                        IconButton(
                          iconSize: 36,
                          tooltip: '10 saniye geri',
                          icon: const Icon(Icons.replay_10),
                          onPressed: controller.seekBackward10Seconds,
                        ),
                        IconButton.filled(
                          iconSize: 44,
                          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                          onPressed: () =>
                              playing ? controller.pause() : controller.resume(),
                        ),
                        IconButton(
                          iconSize: 36,
                          tooltip: '10 saniye ileri',
                          icon: const Icon(Icons.forward_10),
                          onPressed: controller.seekForward10Seconds,
                        ),
                        IconButton(
                          iconSize: 32,
                          tooltip: 'Sonraki Sûre',
                          icon: const Icon(Icons.skip_next),
                          onPressed:
                              controller.hasNext ? controller.playNextSurah : null,
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
