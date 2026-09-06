import 'dart:async';
import 'package:just_audio/just_audio.dart';

import 'adhan_settings.dart';
import 'custom_audio_store.dart';

/// [player] üzerinde [setting]'e göre ön plan (uygulama açıkken) sesini
/// hazırlar ve çalar. Sessiz seçiliyse hiçbir şey yapmadan döner.
///
/// Bu, hem gerçek vakit alarmı ([AlarmPage]) hem de Ayarlar sayfasındaki
/// "▶ Dinle" önizleme butonları tarafından ortak olarak kullanılır — ikisi de
/// aynı kodu çalıştırdığı için önizlemede duyulan ses, gerçek alarmda
/// duyulacak sesle birebir aynıdır.
///
/// Döner: sesin gerçekten hazırlanıp çalınıp çalınmadığı (custom seçiliyken
/// dosya bulunamazsa `false` döner, çağıran taraf kullanıcıyı bilgilendirebilir).
Future<bool> playPrayerSound({
  required AudioPlayer player,
  required String prayerName,
  required AdhanSettings adhanSettings,
  required CustomAudioStore customAudioStore,
  double volume = 1.0,
}) async {
  final source = await resolveSelectedAdhan(
    prayer: PrayerType.fromPrayerName(prayerName),
    settings: adhanSettings,
    customAudioStore: customAudioStore,
  );
  return playAdhanSource(player: player, source: source, volume: volume);
}

Future<bool> playAdhanSource({
  required AudioPlayer player,
  required AdhanSource source,
  double volume = 1.0,
  bool Function()? canPlay,
  void Function(Object)? onError,
}) async {
  if (source.assetPath != null) {
    await player.setAsset(source.assetPath!);
  } else if (source.customFile != null) {
    final file = source.customFile!;
    final uri = Uri.dataFromBytes(file.bytes, mimeType: file.mimeType);
    await player.setAudioSource(AudioSource.uri(uri));
  } else {
    return false;
  }

  await player.setVolume(volume.clamp(0.0, 1.0));
  if (canPlay != null && !canPlay()) return false;
  unawaited(player.play().catchError((Object error) {
    onError?.call(error);
  }));
  return true;
}
