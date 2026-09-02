import 'package:just_audio/just_audio.dart';

import 'custom_audio_store.dart';
import 'prayer_sound_settings.dart';

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
  required PrayerSoundSetting setting,
  required CustomAudioStore customAudioStore,
  double volume = 1.0,
}) async {
  if (setting.type == PrayerSoundType.silent) return false;

  switch (setting.type) {
    case PrayerSoundType.adhan:
      final asset = adhanAssetForPrayer(prayerName);
      if (asset == null) return false;
      await player.setAsset(asset);
      break;
    case PrayerSoundType.notification:
      await player.setAsset(notificationSoundAsset);
      break;
    case PrayerSoundType.custom:
      if (setting.customAudioId == null) return false;
      final file = await customAudioStore.get(setting.customAudioId!);
      if (file == null) return false;
      final uri = Uri.dataFromBytes(file.bytes, mimeType: file.mimeType);
      await player.setAudioSource(AudioSource.uri(uri));
      break;
    case PrayerSoundType.silent:
      return false;
  }

  await player.setVolume(volume.clamp(0.0, 1.0));
  await player.play();
  return true;
}
