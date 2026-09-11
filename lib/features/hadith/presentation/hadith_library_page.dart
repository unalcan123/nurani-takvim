import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../favorites/data/favorites_repository.dart';
import '../../favorites/data/models.dart';
import '../../media/player/media_player_controller.dart';
import '../../media/player/now_playing_bar.dart';
import '../data/hadith_audio_cache.dart';
import '../data/hadith_audio_library.dart';

const _favoriteRefPrefix = 'hadith_audio:';

class HadithLibraryPage extends ConsumerStatefulWidget {
  const HadithLibraryPage({super.key});

  @override
  ConsumerState<HadithLibraryPage> createState() => _HadithLibraryPageState();
}

class _HadithLibraryPageState extends ConsumerState<HadithLibraryPage> {
  final _library = HadithAudioLibraryService();
  final _cache = HadithAudioCache();
  final _searchController = TextEditingController();
  late Future<HadithAudioManifest> _future;
  String _query = '';
  final Map<String, double> _downloadProgress = {};
  final Set<String> _cachedIds = {};

  @override
  void initState() {
    super.initState();
    _future = _library.loadManifest().then((manifest) async {
      final results = await Future.wait(
        manifest.entries.map((e) async => MapEntry(e.id, await _cache.isCached(e))),
      );
      if (mounted) {
        setState(() {
          _cachedIds.addAll(results.where((r) => r.value).map((r) => r.key));
        });
      }
      return manifest;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _play(HadithAudioManifest manifest, HadithAudioEntry entry) async {
    final controller = ref.read(mediaPlayerControllerProvider);
    final cachedPath = await _cache.cachedFilePath(entry);
    if (cachedPath != null) {
      await controller.playTrack(
        MediaTrack(
          id: entry.id,
          title: entry.title,
          subtitle: manifest.narrator,
          source: Uri.file(cachedPath),
        ),
      );
      return;
    }
    // Henüz indirilmemiş: doğrudan archive.org'dan akışla çal.
    await controller.playTrack(
      MediaTrack(
        id: entry.id,
        title: entry.title,
        subtitle: manifest.narrator,
        source: Uri.parse(Uri.encodeFull('${manifest.baseUrl}${entry.fileName}')),
      ),
    );
  }

  Future<void> _download(HadithAudioManifest manifest, HadithAudioEntry entry) async {
    setState(() => _downloadProgress[entry.id] = 0.0);
    try {
      await _cache.ensureDownloaded(
        entry,
        baseUrl: manifest.baseUrl,
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress[entry.id] = p);
        },
      );
      if (mounted) setState(() => _cachedIds.add(entry.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İndirme başarısız: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadProgress.remove(entry.id));
    }
  }

  void _toggleFavorite(HadithAudioManifest manifest, HadithAudioEntry entry) {
    ref.read(favoritesProvider.notifier).toggle(
          FavoriteItem(
            type: FavoriteType.hadith,
            refId: '$_favoriteRefPrefix${entry.id}',
            title: entry.title,
            body: 'Riyazüs Salihin — ${entry.title}',
            sourceLine: 'Riyazüs Salihin (İmam Nevevî) — Okuyan: ${manifest.narrator}',
            savedAt: DateTime.now(),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoritesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Hadis Dinle')),
      body: FutureBuilder<HadithAudioManifest>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Liste okunamadı: ${snapshot.error}'));
          }
          final manifest = snapshot.data!;
          final query = _query.trim().toLowerCase();
          final items = query.isEmpty
              ? manifest.entries
              : manifest.entries
                  .where((e) => e.title.toLowerCase().contains(query))
                  .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Bölüm ara',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Riyazüs Salihin (İmam Nevevî) — Okuyan: ${manifest.narrator} — Kaynak: archive.org',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = items[index];
                    final progress = _downloadProgress[entry.id];
                    final cached = _cachedIds.contains(entry.id);
                    final isFavorite = favorites
                        .any((f) => f.refId == '$_favoriteRefPrefix${entry.id}');
                    return ListTile(
                      title: Text(entry.title),
                      subtitle: Text(
                        cached
                            ? 'İndirildi — çevrimdışı hazır'
                            : '${entry.sizeMb.toStringAsFixed(1)} MB',
                      ),
                      onTap: () => _play(manifest, entry),
                      trailing: progress != null
                          ? SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(value: progress),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    isFavorite ? Icons.favorite : Icons.favorite_border,
                                    color: isFavorite ? Colors.redAccent : null,
                                  ),
                                  onPressed: () => _toggleFavorite(manifest, entry),
                                ),
                                IconButton(
                                  icon: Icon(
                                    cached
                                        ? Icons.download_done
                                        : Icons.download_outlined,
                                  ),
                                  tooltip: cached
                                      ? 'İndirildi'
                                      : 'Çevrimdışı için indir',
                                  onPressed:
                                      cached ? null : () => _download(manifest, entry),
                                ),
                              ],
                            ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: const NowPlayingBar(),
    );
  }
}
