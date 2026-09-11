import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/audio_manager.dart';
import '../../../core/bg_music_service.dart';

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
class MediaPlayerController {
  MediaPlayerController(this._ref) {
    _adhanSubscription = _ref.listen<bool>(adhanActiveProvider, (
      previous,
      active,
    ) {
      if (active) pause();
    });
  }

  final Ref _ref;
  final AudioPlayer player = AudioPlayer();
  late final ProviderSubscription<bool> _adhanSubscription;
  bool _disposed = false;

  final ValueNotifier<MediaTrack?> currentTrack = ValueNotifier(null);

  Stream<Duration> get positionStream => player.positionStream;
  Stream<Duration?> get durationStream => player.durationStream;
  Stream<PlayerState> get playerStateStream => player.playerStateStream;
  Duration get position => player.position;
  Duration? get duration => player.duration;
  bool get isPlaying => player.playing;

  Future<void> playTrack(MediaTrack track) async {
    if (_disposed) return;
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
    await player.stop();
    await _ref.read(bgMusicServiceProvider).resumeAfterAlarm();
  }

  void dispose() {
    _disposed = true;
    _adhanSubscription.close();
    currentTrack.dispose();
    unawaited(player.dispose());
  }
}
