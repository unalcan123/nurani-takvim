import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../features/settings/presentation/alert_settings_controller.dart';

/// Global arka plan müziği; yalnızca kayıtlı kullanıcı tercihi açıksa çalar.
final bgMusicServiceProvider = Provider<BgMusicService>((ref) {
  final service = BgMusicService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Mute durumunu takip eden StateProvider
final bgMusicMutedProvider = StateProvider<bool>((ref) => false);

class BgMusicService {
  final Ref _ref;
  final AudioPlayer _player;
  bool _initialized = false;
  bool _suspended = false;
  int _loadGeneration = 0;
  List<String> _currentPaths = [];

  BgMusicService(this._ref, {AudioPlayer? audioPlayer})
    : _player = audioPlayer ?? AudioPlayer();

  AudioPlayer get player => _player;

  /// Uygulama başlangıcında çağrılır
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Ayar değişikliklerini dinle
    _ref.listen(alertSettingsProvider, (prev, next) {
      if (prev == null) return;

      // Müzik kapatıldıysa dur
      if (!next.bgMusicEnabled) {
        _player.stop();
        _currentPaths = [];
        return;
      }

      // Müzik listesi değiştiyse veya yeni açıldıysa yeniden yükle
      if (next.bgMusicPaths.isNotEmpty &&
          (_listEquals(next.bgMusicPaths, _currentPaths) == false ||
              !prev.bgMusicEnabled)) {
        _loadPlaylistAndPlay(next.bgMusicPaths);
      }
    });

    // Mute dinle
    _ref.listen(bgMusicMutedProvider, (prev, next) {
      _player.setVolume(next ? 0.0 : 1.0);
    });

    // İlk açılışta müziği çalmaya başla
    final settings = _ref.read(alertSettingsProvider);
    if (settings.bgMusicEnabled && settings.bgMusicPaths.isNotEmpty) {
      await _loadPlaylistAndPlay(settings.bgMusicPaths);
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _loadPlaylistAndPlay(List<String> paths) async {
    try {
      _currentPaths = List.from(paths);

      final playlist = ConcatenatingAudioSource(
        children:
            paths.map((path) {
              if (path.startsWith('assets/')) {
                return AudioSource.uri(Uri.parse('asset:///$path'));
              } else if (kIsWeb) {
                return AudioSource.uri(Uri.parse(path));
              } else {
                return AudioSource.uri(Uri.file(path));
              }
            }).toList(),
      );

      final generation = ++_loadGeneration;
      await _player.setAudioSource(playlist, preload: true);
      if (generation != _loadGeneration) return;
      _player.setLoopMode(LoopMode.all);

      final isMuted = _ref.read(bgMusicMutedProvider);
      _player.setVolume(isMuted ? 0.0 : 1.0);

      if (!_suspended && _ref.read(alertSettingsProvider).bgMusicEnabled) {
        unawaited(
          _player.play().catchError((Object e) => debugPrint('Müzik: $e')),
        );
      }
    } catch (e) {
      debugPrint('BgMusicService çalma listesi hatası: $e');
    }
  }

  void toggleMute() {
    final notifier = _ref.read(bgMusicMutedProvider.notifier);
    notifier.state = !notifier.state;
  }

  Future<void> pauseForAlarm() async {
    _suspended = true;
    try {
      await _player.pause();
    } catch (e) {
      debugPrint('BgMusicService alarm öncesi durdurma hatası: $e');
    }
  }

  Future<void> resumeAfterAlarm() async {
    _suspended = false;
    final settings = _ref.read(alertSettingsProvider);
    if (!settings.bgMusicEnabled || settings.bgMusicPaths.isEmpty) return;
    if (_player.audioSource == null ||
        !_listEquals(settings.bgMusicPaths, _currentPaths)) {
      await _loadPlaylistAndPlay(settings.bgMusicPaths);
    } else {
      unawaited(
        _player.play().catchError((Object e) => debugPrint('Müzik: $e')),
      );
    }
  }

  void dispose() {
    _player.stop();
    _player.dispose();
  }
}
