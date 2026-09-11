import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'full_player_sheet.dart';
import 'media_player_controller.dart';

/// Ana sayfadaki "Menü" düğmesinin yanına konan, bir parça çalarken görünen
/// küçük başlat/durdur kontrolü. Hiçbir parça çalmıyorsa hiçbir şey göstermez.
class CompactPlayControls extends ConsumerWidget {
  const CompactPlayControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(mediaPlayerControllerProvider);
    return ValueListenableBuilder<MediaTrack?>(
      valueListenable: controller.currentTrack,
      builder: (context, track, _) {
        if (track == null) return const SizedBox.shrink();
        return Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF242B30),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: track.title,
                icon: const Icon(Icons.graphic_eq, color: Color(0xFFE9C981)),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const FullPlayerSheet(),
                ),
              ),
              StreamBuilder<PlayerState>(
                stream: controller.playerStateStream,
                builder: (context, snapshot) {
                  final playing = snapshot.data?.playing ?? false;
                  return IconButton(
                    tooltip: playing ? 'Duraklat' : 'Devam Et',
                    icon: Icon(
                      playing ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                    onPressed: () =>
                        playing ? controller.pause() : controller.resume(),
                  );
                },
              ),
              IconButton(
                tooltip: 'Durdur',
                icon: const Icon(Icons.stop, color: Colors.white),
                onPressed: controller.stop,
              ),
            ],
          ),
        );
      },
    );
  }
}
