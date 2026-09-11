import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/audio_manager.dart';
import '../../../core/bg_music_service.dart';

const _seekStep = Duration(seconds: 10);

/// Kuran/Hadis gibi uzun soluklu (aranabilir, duraklatılabilir) içerikler
/// için çalınmakta olan tek parça.
class MediaTrack {
  final String id;
  final String title;
  final String? subtitle;
  final Uri source;

  const MediaTrack({
    required this.id,
    required this.title,
    this.subtitle,
    required this.source,
  });
}

final mediaPlayerControllerProvider = Provider<MediaPlayerController>((ref) {
  final controller = MediaPlayerController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Ezan/önizleme için [AudioManager] kullanılırken, bu sınıf Kuran/Hadis gibi
/// uzun ses kayıtları için kendi `AudioPlayer`'ını yönetir — ilerleme çubuğu,
/// atlama (seek) ve duraklat/devam ettir gerektiren bambaşka bir kullanım
/// deseni olduğu için [AudioManager]'ın kısa klip/önizleme mantığına
/// (generation sayaçları, tekli "preview" kavramı) eklenmedi.
///
/// Ezan çalmaya başladığında bu oynatıcı kendiliğinden duraklar (bkz.
/// [AudioManager.adhanActiveProvider]) — ezan hiçbir zaman bunun tarafından
/// engellenmez, yalnızca bu taraf ezana yol verir.
///
/// Bir çalma listesi (ör. bir hafızın tüm sûreleri, [playPlaylist]/[playSurah])
/// verilirse, bir parça tamamen bitince otomatik olarak listedeki bir
/// sonrakine geçilir (bkz. [_handleCompleted]). Tek parça çalan [playTrack]
/// (ör. Hadis dinleme) bu davranışa girmez — kendi tek elemanlı "listesi"
/// biter bitmez oynatıcı durur.
class MediaPlayerController {
  MediaPlayerController(this._ref) {
    _adhanSubscription = _ref.listen<bool>(adhanActiveProvider, (
      previous,
      active,
    ) {
      if (active) pause();
    });
    _completionSubscription = player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _handleCompleted();
      }
    });
  }

  final Ref _ref;
  final AudioPlayer player = AudioPlayer();
  late final ProviderSubscription<bool> _adhanSubscription;
  late final StreamSubscription<PlayerState> _completionSubscription;
  bool _disposed = false;

  final ValueNotifier<MediaTrack?> currentTrack = ValueNotifier(null);

  List<MediaTrack> _playlist = const [];
  int _currentIndex = -1;

  /// [_handleCompleted] aynı bitiş olayı için birden fazla kez tetiklenirse
  /// (just_audio'nun `completed` durumu, o duruma yeniden girilmeden bir
  /// dinleyici tarafından tekrar okunabilir) aynı sûreyi iki kez
  /// başlatmamak için — yalnızca çalmakta olan parça değiştiğinde sıfırlanır.
  String? _lastCompletedTrackId;

  int get currentIndex => _currentIndex;
  bool get hasNext => _currentIndex >= 0 && _currentIndex < _playlist.length - 1;
  bool get hasPrevious => _currentIndex > 0;

  Stream<Duration> get positionStream => player.positionStream;
  Stream<Duration?> get durationStream => player.durationStream;
  Stream<PlayerState> get playerStateStream => player.playerStateStream;
  Duration get position => player.position;
  Duration? get duration => player.duration;
  bool get isPlaying => player.playing;

  void _handleCompleted() {
    final track = currentTrack.value;
    if (track == null || _lastCompletedTrackId == track.id) return;
    _lastCompletedTrackId = track.id;
    if (hasNext) {
      playNextSurah();
    } else {
      // Liste bitti: başa sarıp tekrar başlatmıyoruz, sadece durduruyoruz.
      // İleride "tekrar çal" istenirse buraya (playSurah(0) gibi) eklenebilir.
      stop();
    }
  }

  /// Tek bir parçayı, bir çalma listesi bağlamı olmadan çalar (ör. Hadis
  /// dinleme) — bittiğinde otomatik olarak başka bir parçaya geçilmez.
  Future<void> playTrack(MediaTrack track) => _play([track], 0);

  /// [tracks] listesini çalma listesi olarak ayarlar ve [startIndex]'teki
  /// parçayı çalmaya başlar (ör. bir hafızın tüm sûreleri).
  Future<void> playPlaylist(List<MediaTrack> tracks, {int startIndex = 0}) {
    if (tracks.isEmpty) return Future.value();
    return _play(tracks, startIndex.clamp(0, tracks.length - 1));
  }

  /// Mevcut çalma listesinde [index]'teki parçaya geçer.
  Future<void> playSurah(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    await _play(_playlist, index);
  }

  Future<void> playNextSurah() async {
    if (!hasNext) return;
    await playSurah(_currentIndex + 1);
  }

  Future<void> playPreviousSurah() async {
    if (!hasPrevious) return;
    await playSurah(_currentIndex - 1);
  }

  Future<void> seekForward10Seconds() async {
    final dur = duration;
    var target = position + _seekStep;
    if (dur != null && target > dur) target = dur;
    await seek(target);
  }

  Future<void> seekBackward10Seconds() async {
    var target = position - _seekStep;
    if (target < Duration.zero) target = Duration.zero;
    await seek(target);
  }

  Future<void> _play(List<MediaTrack> playlist, int index) async {
    if (_disposed) return;
    final track = playlist[index];
    _playlist = playlist;
    _currentIndex = index;
    _lastCompletedTrackId = null;
    currentTrack.value = track;
    await _ref.read(bgMusicServiceProvider).pauseForAlarm();
    await player.setAudioSource(AudioSource.uri(track.source));
    await player.play();
  }

  Future<void> pause() async {
    if (_disposed || !player.playing) return;
    await player.pause();
  }

  Future<void> resume() async {
    if (_disposed || currentTrack.value == null) return;
    await player.play();
  }

  Future<void> seek(Duration position) async {
    if (_disposed) return;
    await player.seek(position);
  }

  Future<void> stop() async {
    if (_disposed) return;
    currentTrack.value = null;
    _playlist = const [];
    _currentIndex = -1;
    await player.stop();
    await _ref.read(bgMusicServiceProvider).resumeAfterAlarm();
  }

  void dispose() {
    _disposed = true;
    _adhanSubscription.close();
    unawaited(_completionSubscription.cancel());
    currentTrack.dispose();
    unawaited(player.dispose());
  }
}
