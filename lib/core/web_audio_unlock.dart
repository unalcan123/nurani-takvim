import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

/// Tarayıcılar, kullanıcı etkileşimi olmadan başlatılan sesleri (autoplay)
/// engeller. Ezan, vakit girdiğinde bir zamanlayıcı tarafından (kullanıcı
/// dokunuşu olmadan) tetiklendiği için web'de sessizce engellenebilir.
///
/// Bu widget, kullanıcı uygulamada herhangi bir yere ilk kez dokunduğunda
/// paylaşılan ses çalarını bir kez sessizce çalıp durdurarak tarayıcıya
/// "kullanıcı etkileşimi oldu" bilgisini verir; böylece sayfa açık kaldığı
/// sürece sonraki otomatik ezan/uyarı sesleri engellenmez. Yalnızca web'de
/// çalışır ve ses seviyesini kalıcı olarak değiştirmez.
class WebAudioUnlocker extends StatefulWidget {
  final Widget child;
  const WebAudioUnlocker({super.key, required this.child});

  @override
  State<WebAudioUnlocker> createState() => _WebAudioUnlockerState();
}

class _WebAudioUnlockerState extends State<WebAudioUnlocker> {
  bool _unlocked = false;

  Future<void> _unlockOnce() async {
    if (_unlocked) return;
    _unlocked = true;
    final probe = AudioPlayer();
    try {
      await probe.setVolume(0);
      await probe.setAsset('assets/audio/ezan_yatsi.mp3');
      await probe.play();
      await probe.pause();
    } catch (_) {
      // Kilit açma denemesi başarısız olursa sessizce yok say;
      // ezan sayfası kendi hata yönetimini zaten yapıyor.
    } finally {
      unawaited(probe.dispose());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _unlockOnce(),
      child: widget.child,
    );
  }
}
