import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import '../../../core/audio_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../../theme.dart';

class AlarmPage extends ConsumerStatefulWidget {
  final String nextPrayerName;

  const AlarmPage({super.key, required this.nextPrayerName});

  @override
  ConsumerState<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends ConsumerState<AlarmPage> {
  late final AudioManager _audio;
  bool _closing = false;
  String? _background;
  StreamSubscription? _playerStateSubscription;

  /// Tarayıcı otomatik oynatmayı (autoplay) engellediğinde `true` olur —
  /// bu durumda kullanıcının tek dokunuşla sesi başlatabilmesi için bir
  /// buton gösterilir (dokunma, tarayıcının aradığı "kullanıcı etkileşimi"
  /// sayılır ve engeli aşar).
  bool _playbackBlocked = false;

  @override
  void initState() {
    super.initState();
    _audio = ref.read(audioManagerProvider);
    _playerStateSubscription = _audio.player.processingStateStream.listen((
      state,
    ) {
      if (state == ProcessingState.completed) unawaited(_closePage());
    });
    _loadBackground();
    _initPlayer();
  }

  Future<void> _loadBackground() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final images =
        manifest
            .listAssets()
            .where((p) => p.startsWith('assets/images/kabe/'))
            .toList();
    if (mounted && images.isNotEmpty) {
      setState(() => _background = images[Random().nextInt(images.length)]);
    }
  }

  void _onPlaybackError(Object error) {
    debugPrint('Ezan oynatılamadı: $error');
    unawaited(_audio.stopAdhan());
    if (mounted && !_closing) setState(() => _playbackBlocked = true);
  }

  Future<void> _initPlayer() async {
    if (_closing) return;
    setState(() => _playbackBlocked = false);
    try {
      await _audio.playAdhan(widget.nextPrayerName, onError: _onPlaybackError);
    } catch (e) {
      _onPlaybackError(e);
    }
  }

  Future<void> _closePage() async {
    if (_closing) return;
    _closing = true;
    await _audio.stopAdhan();
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: tvBgDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_background != null) Image.asset(_background!, fit: BoxFit.cover),
          ColoredBox(color: Colors.black.withValues(alpha: 0.40)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.mosque, size: 100, color: Colors.amber),
                    const SizedBox(height: 32),
                    Text(
                      '${widget.nextPrayerName} Vakti Girdi',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _playbackBlocked
                          ? 'Ses başlatılamadı. Yeniden deneyebilirsiniz.'
                          : 'Ezan okunuyor...',
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white70,
                      ),
                    ),
                    if (_playbackBlocked) ...[
                      const SizedBox(height: 32),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 14,
                          ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 16,
                        ),
                      ),
                      onPressed: _closePage,
                      child: const Text(
                        'DURDUR',
                        style: TextStyle(fontSize: 20, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
