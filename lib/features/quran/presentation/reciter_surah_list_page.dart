import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/presentation/app_shell.dart';
import '../../media/player/media_player_controller.dart';
import '../../media/player/now_playing_bar.dart';
import '../data/mp3quran_reciter_service.dart';
import '../data/quran_audio_cache.dart';
import '../data/surah_list.dart';

class ReciterSurahListPage extends ConsumerStatefulWidget {
  final QuranReciter reciter;
  final QuranMoshaf moshaf;

  const ReciterSurahListPage({
    super.key,
    required this.reciter,
    required this.moshaf,
  });

  @override
  ConsumerState<ReciterSurahListPage> createState() =>
      _ReciterSurahListPageState();
}

class _ReciterSurahListPageState extends ConsumerState<ReciterSurahListPage> {
  final _surahService = SurahListService();
  final _cache = QuranAudioCache();
  late Future<List<SurahInfo>> _future;
  final Map<int, double> _downloadProgress = {};
  final Set<int> _cachedSurahs = {};

  @override
  void initState() {
    super.initState();
    _future = _surahService.loadSurahs().then((all) async {
      final available = widget.moshaf.surahNumbers.toSet();
      final list = all.where((s) => available.contains(s.sureNo)).toList();
      final results = await Future.wait(
        list.map((s) async => MapEntry(s.sureNo, await _cache.isCached(_trackId(s.sureNo)))),
      );
      if (mounted) {
        setState(() {
          _cachedSurahs.addAll(results.where((r) => r.value).map((r) => r.key));
        });
      }
      return list;
    });
  }

  String _trackId(int sureNo) => 'q_${widget.reciter.id}_${widget.moshaf.id}_$sureNo';

  Future<MediaTrack> _buildTrack(SurahInfo surah) async {
    final trackId = _trackId(surah.sureNo);
    final cachedPath = await _cache.cachedFilePath(trackId);
    final source = cachedPath != null
        ? Uri.file(cachedPath)
        : Uri.parse(widget.moshaf.surahUrl(surah.sureNo));
    return MediaTrack(
      id: trackId,
      title: '${surah.sureNo}. ${surah.turkishName}',
      subtitle: widget.reciter.name,
      source: source,
    );
  }

  /// [surahs] içindeki [index]'teki sûreden başlayarak tüm listeyi bir çalma
  /// listesi olarak ayarlar — böylece "sonraki/önceki sûre" ve bir sûre
  /// bitince otomatik geçiş bu hafızın tüm sûreleri arasında çalışır.
  Future<void> _play(List<SurahInfo> surahs, int index) async {
    final controller = ref.read(mediaPlayerControllerProvider);
    final tracks = await Future.wait(surahs.map(_buildTrack));
    await controller.playPlaylist(tracks, startIndex: index);
    if (!mounted) return;
    ref.read(dashboardSelectedTabProvider.notifier).state = 0;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _download(SurahInfo surah) async {
    final trackId = _trackId(surah.sureNo);
    setState(() => _downloadProgress[surah.sureNo] = 0.0);
    try {
      await _cache.ensureDownloaded(
        trackId,
        widget.moshaf.surahUrl(surah.sureNo),
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress[surah.sureNo] = p);
        },
      );
      if (mounted) setState(() => _cachedSurahs.add(surah.sureNo));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İndirme başarısız: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadProgress.remove(surah.sureNo));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.reciter.name)),
      body: FutureBuilder<List<SurahInfo>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Liste okunamadı: ${snapshot.error}'));
          }
          final surahs = snapshot.data ?? const <SurahInfo>[];
          return ListView.separated(
            itemCount: surahs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final surah = surahs[index];
              final progress = _downloadProgress[surah.sureNo];
              final cached = _cachedSurahs.contains(surah.sureNo);
              return ListTile(
                leading: CircleAvatar(child: Text('${surah.sureNo}')),
                title: Text(surah.turkishName),
                subtitle: Text('${surah.arabicName} • ${surah.ayahCount} âyet'),
                onTap: () => _play(surahs, index),
                trailing: progress != null
                    ? SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(value: progress),
                      )
                    : IconButton(
                        icon: Icon(
                          cached ? Icons.download_done : Icons.download_outlined,
                        ),
                        tooltip: cached ? 'İndirildi' : 'Çevrimdışı için indir',
                        onPressed: cached ? null : () => _download(surah),
                      ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: const NowPlayingBar(),
    );
  }
}
