import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'full_player_sheet.dart';
import 'media_player_controller.dart';

/// Ana sayfadaki "Menü" düğmesinin yanına konan, bir parça çalarken görünen
/// küçük başlat/durdur kontrolü. Hiçbir parça çalmıyorsa hiçbir şey göstermez.
class CompactPlayControls extends ConsumerWidget {
  const CompactPlayControls({super.key, this.compact = false});

  /// A landscape phone doesn't have room for this bar's full 48px buttons
  /// next to the home menu button — shrink the tap targets a bit (still a
  /// reasonable ~40px, above the WCAG AA 44px-ish minimum is preferred but
  /// not always possible in this tight spot) so both fit without crowding.
  /// The full-size controls are always one tap away via the player sheet.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(mediaPlayerControllerProvider);
    return ValueListenableBuilder<MediaTrack?>(
      valueListenable: controller.currentTrack,
      builder: (context, track, _) {
        if (track == null) return const SizedBox.shrink();
        final buttonConstraints = compact
            ? const BoxConstraints(minWidth: 40, minHeight: 40)
            : const BoxConstraints(minWidth: 48, minHeight: 48);
        final iconSize = compact ? 20.0 : 24.0;
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
                constraints: buttonConstraints,
                padding: EdgeInsets.zero,
                iconSize: iconSize,
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
                    constraints: buttonConstraints,
                    padding: EdgeInsets.zero,
                    iconSize: iconSize,
                    icon: Icon(
                      playing ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                    onPressed: () =>
                        playing ? controller.pause() : controller.resume(),
                  );
                },
              ),
              if (!compact)
                IconButton(
                  tooltip: 'Durdur',
                  constraints: buttonConstraints,
                  padding: EdgeInsets.zero,
                  iconSize: iconSize,
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
