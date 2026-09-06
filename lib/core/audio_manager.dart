import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../features/settings/data/adhan_settings.dart';
import '../features/settings/data/prayer_sound_playback.dart';
import '../features/settings/presentation/alert_settings_controller.dart';
import 'bg_music_service.dart';
import 'notification_service.dart';

final adhanActiveProvider = StateProvider<bool>((ref) => false);
final audioManagerProvider = Provider<AudioManager>((ref) {
  final manager = AudioManager(ref);
  ref.onDispose(manager.dispose);
  return manager;
});

/// A single player owns both previews and the actual adhan. Request generations
/// prevent an interrupted asset load from starting playback after STOP.
class AudioManager with WidgetsBindingObserver {
  AudioManager(this.ref, {AudioPlayer? audioPlayer})
    : player = audioPlayer ?? AudioPlayer() {
    WidgetsBinding.instance.addObserver(this);
    _completion = player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && !_adhan) {
        unawaited(stopPreview());
      }
    });
  }

  final Ref ref;
  final AudioPlayer player;
  final ValueNotifier<String?> previewKey = ValueNotifier(null);
  late final StreamSubscription<ProcessingState> _completion;
  Future<void> _queue = Future.value();
  int _generation = 0;
  bool _adhan = false;
  bool _disposed = false;
  Object? _previewOwner;

  Future<void> _serialize(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.catchError((Object e) => debugPrint('Audio: $e'));
    return next;
  }

  Future<void> stopAllForAdhan() async {
    _adhan = true;
    ref.read(adhanActiveProvider.notifier).state = true;
    ref.read(notificationServiceProvider).adhanActive = true;
    ++_generation;
    _previewOwner = null;
    previewKey.value = null;
    await Future.wait([
      ref.read(bgMusicServiceProvider).pauseForAlarm(),
      ref.read(notificationServiceProvider).stopTransientAudio(),
      player.stop(),
    ]);
    await _queue;
  }

  Future<void> playAdhan(
    String prayerName, {
    required void Function(Object) onError,
  }) {
    final generation = ++_generation;
    return _serialize(() async {
      if (!_adhan || generation != _generation || _disposed) return;
      final settings = ref.read(alertSettingsProvider);
      final source = await resolveSelectedAdhan(
        prayer: PrayerType.fromPrayerName(prayerName),
        settings: settings.adhanSettings,
        customAudioStore: ref.read(customAudioStoreProvider),
      );
      if (generation != _generation || _disposed) return;
      await ref.read(notificationServiceProvider).setAdhanPlaybackActive(true);
      if (generation != _generation || _disposed) return;
      await playAdhanSource(
        player: player,
        source: source,
        volume: settings.ezanVolume,
        canPlay: () => generation == _generation && _adhan && !_disposed,
        onError: (e) {
          if (generation == _generation) onError(e);
        },
      );
    });
  }

  Future<void> playPreview(
    Object owner,
    String key,
    FutureOr<AdhanSource> source,
  ) async {
    if (_adhan || _disposed) return;
    final generation = ++_generation;
    _previewOwner = owner;
    previewKey.value = key;
    await player.stop();
    await _serialize(() async {
      if (_adhan || generation != _generation || _disposed) return;
      await ref.read(bgMusicServiceProvider).pauseForAlarm();
      await ref.read(notificationServiceProvider).stopTransientAudio();
      if (_adhan || generation != _generation || _disposed) return;
      try {
        final resolved = await source;
        if (_adhan || generation != _generation || _disposed) return;
        await playAdhanSource(
          player: player,
          source: resolved,
          volume: ref.read(alertSettingsProvider).ezanVolume,
          canPlay: () => !_adhan && generation == _generation && !_disposed,
          onError: (e) {
            debugPrint('Önizleme oynatılamadı: $e');
            if (generation == _generation) unawaited(stopPreview(owner));
          },
        );
      } catch (_) {
        if (generation == _generation) await stopPreview(owner);
        rethrow;
      }
    });
  }

  Future<void> stopPreview([Object? owner]) async {
    if (_adhan ||
        _disposed ||
        _previewOwner == null ||
        (owner != null && owner != _previewOwner)) {
      return;
    }
    final generation = ++_generation;
    _previewOwner = null;
    previewKey.value = null;
    await player.stop();
    if (!_adhan && generation == _generation && !_disposed) {
      await ref.read(bgMusicServiceProvider).resumeAfterAlarm();
    }
  }

  Future<void> stopAdhan() async {
    ++_generation;
    await player.stop();
    await _queue;
    await ref.read(notificationServiceProvider).setAdhanPlaybackActive(false);
  }

  Future<void> resumeAfterAdhan() async {
    _adhan = false;
    ref.read(notificationServiceProvider).adhanActive = false;
    ref.read(adhanActiveProvider.notifier).state = false;
    await ref.read(bgMusicServiceProvider).resumeAfterAlarm();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(stopPreview());
  }

  void dispose() {
    _disposed = true;
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _completion.cancel();
    player.dispose();
    previewKey.dispose();
  }
}
