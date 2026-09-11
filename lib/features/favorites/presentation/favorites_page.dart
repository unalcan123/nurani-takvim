import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/presentation/app_shell.dart';
import '../../daily_content/presentation/content_card.dart';
import '../../hadith/data/hadith_audio_cache.dart';
import '../../hadith/data/hadith_audio_library.dart';
import '../../media/player/full_player_sheet.dart';
import '../../media/player/media_player_controller.dart';
import '../data/favorites_repository.dart';
import '../data/models.dart';

const _hadithAudioRefPrefix = 'hadith_audio:';

Future<void> _openHadithAudioFavorite(
  BuildContext context,
  WidgetRef ref,
  String refId,
) async {
  final entryId = refId.substring(_hadithAudioRefPrefix.length);
  final manifest = await HadithAudioLibraryService().loadManifest();
  final entry = manifest.byId(entryId);
  if (entry == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu hadis kaydı artık listede yok.')),
      );
    }
    return;
  }
  final cachedPath = await HadithAudioCache().cachedFilePath(entry);
  final source = cachedPath != null
      ? Uri.file(cachedPath)
      : Uri.parse(Uri.encodeFull('${manifest.baseUrl}${entry.fileName}'));
  await ref.read(mediaPlayerControllerProvider).playTrack(
        MediaTrack(
          id: entry.id,
          title: entry.title,
          subtitle: manifest.narrator,
          source: source,
        ),
      );
  if (context.mounted) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const FullPlayerSheet(),
    );
  }
}

IconData _iconFor(FavoriteType type) => switch (type) {
      FavoriteType.ayet => Icons.menu_book_outlined,
      FavoriteType.hadith => Icons.eco_outlined,
      FavoriteType.soz => Icons.format_quote_outlined,
      FavoriteType.event => Icons.history_edu_outlined,
    };

class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    final children = [
      if (isLandscape) ...[
        const _HomeBackButton(),
        const SizedBox(height: 10),
      ],
      if (favorites.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Henüz favori eklemediniz. Günlük içerik kartlarındaki kalp ikonuna dokunarak buraya ekleyebilirsiniz.',
            textAlign: TextAlign.center,
          ),
        )
      else
        ...favorites.map(
          (f) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ContentCard(
              icon: f.refId.startsWith(_hadithAudioRefPrefix)
                  ? Icons.play_circle_outline
                  : _iconFor(f.type),
              title: f.title,
              body: f.body,
              sourceLine: f.sourceLine,
              shareText: '${f.body}\n\n(${f.sourceLine})\n\nEzan Vakti uygulamasından paylaşıldı.',
              isSampleData: false,
              favoriteType: f.type,
              favoriteRefId: f.refId,
              onTap: f.refId.startsWith(_hadithAudioRefPrefix)
                  ? () => _openHadithAudioFavorite(context, ref, f.refId)
                  : null,
            ),
          ),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: children,
    );
  }
}

class _HomeBackButton extends ConsumerWidget {
  const _HomeBackButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: () => ref.read(dashboardSelectedTabProvider.notifier).state = 0,
        icon: const Icon(Icons.arrow_back),
        label: const Text('Ana Sayfa'),
      ),
    );
  }
}
