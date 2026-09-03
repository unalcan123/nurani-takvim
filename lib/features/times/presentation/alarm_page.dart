import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../../theme.dart';
import '../../settings/data/prayer_sound_playback.dart';
import '../../settings/data/prayer_sound_settings.dart';
import '../../settings/presentation/alert_settings_controller.dart';

class AlarmPage extends ConsumerStatefulWidget {
  final String nextPrayerName;

  const AlarmPage({super.key, required this.nextPrayerName});

  @override
  ConsumerState<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends ConsumerState<AlarmPage> {
  final _audioPlayer = AudioPlayer();
  StreamSubscription? _playerStateSubscription;

  /// Tarayıcı otomatik oynatmayı (autoplay) engellediğinde `true` olur —
  /// bu durumda kullanıcının tek dokunuşla sesi başlatabilmesi için bir
  /// buton gösterilir (dokunma, tarayıcının aradığı "kullanıcı etkileşimi"
  /// sayılır ve engeli aşar).
  bool _playbackBlocked = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final settings = ref.read(alertSettingsProvider);
    final sound = settings.soundFor(widget.nextPrayerName);

    if (sound.type == PrayerSoundType.silent) return;

    if (mounted) setState(() => _playbackBlocked = false);

    try {
      final played = await playPrayerSound(
        player: _audioPlayer,
        prayerName: widget.nextPrayerName,
        setting: sound,
        customAudioStore: ref.read(customAudioStoreProvider),
        volume: settings.ezanVolume,
      );
      if (!played) {
        debugPrint('Çalınacak ses bulunamadı (${widget.nextPrayerName}, ${sound.type}).');
        return;
      }

      _playerStateSubscription = _audioPlayer.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) {
          _closePage();
        }
      });
    } catch (e) {
      debugPrint("Ses dosyası çalınamadı (${widget.nextPrayerName}): $e");
      // Tarayıcı autoplay'i engellemiş olabilir (kullanıcı etkileşimi
      // olmadan tetiklenen bir zamanlayıcıdan çağrıldığı için) — sayfayı
      // kapatmak yerine kullanıcıya manuel başlatma butonu gösterilir.
      if (mounted) setState(() => _playbackBlocked = true);
    }
  }

  void _closePage() {
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: tvBgDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mosque, size: 100, color: Colors.amber),
            const SizedBox(height: 32),
            Text(
              '${widget.nextPrayerName} Vakti Girdi',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Ezan okunuyor...',
              style: TextStyle(fontSize: 18, color: Colors.white70),
            ),
            if (_playbackBlocked) ...[
              const SizedBox(height: 32),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                ),
                onPressed: _initPlayer,
                icon: const Icon(Icons.volume_up),
                label: const Text('Sesi Başlat'),
              ),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              ),
              onPressed: _closePage,
              child: const Text('DURDUR', style: TextStyle(fontSize: 20, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
