import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'full_player_sheet.dart';
import 'media_player_controller.dart';

/// Bir parça çalarken ekranın altında sabit duran mini oynatıcı çubuğu.
/// Hiçbir parça çalmıyorsa hiçbir şey göstermez (yer kaplamaz).
class NowPlayingBar extends ConsumerWidget {
  const NowPlayingBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(mediaPlayerControllerProvider);
    return ValueListenableBuilder<MediaTrack?>(
      valueListenable: controller.currentTrack,
      builder: (context, track, _) {
        if (track == null) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          child: Material(
            elevation: 8,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: InkWell(
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => const FullPlayerSheet(),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (track.subtitle != null)
                            Text(
                              track.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    StreamBuilder<PlayerState>(
                      stream: controller.playerStateStream,
                      builder: (context, snapshot) {
                        final playing = snapshot.data?.playing ?? false;
                        return IconButton(
                          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                          onPressed: () =>
                              playing ? controller.pause() : controller.resume(),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: controller.stop,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
