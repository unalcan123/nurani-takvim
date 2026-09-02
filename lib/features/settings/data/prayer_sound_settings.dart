/// Her namaz vakti için bağımsız olarak seçilebilecek bildirim sesi türü.
enum PrayerSoundType {
  /// Vaktin ezanı (İmsak için sabah ezanı, diğerleri için ilgili ezan kaydı).
  adhan,

  /// Kısa bildirim sesi (ezan yerine kısa bir uyarı sesi).
  notification,

  /// Kullanıcının cihazından seçtiği kendi ses dosyası / müziği.
  custom,

  /// Ses çalınmaz; bildirim sessiz gösterilir.
  silent;

  String get displayName => const {
        PrayerSoundType.adhan: 'Ezan Sesi',
        PrayerSoundType.notification: 'Kısa Bildirim Sesi',
        PrayerSoundType.custom: 'Kendi Sesim',
        PrayerSoundType.silent: 'Sessiz',
      }[this]!;

  static PrayerSoundType fromName(String? value) => PrayerSoundType.values.firstWhere(
        (e) => e.name == value,
        orElse: () => PrayerSoundType.adhan,
      );
}

/// Tek bir vakit için ses/bildirim ayarı. `enabled`, o vaktin alarmının açık
/// olup olmadığını değil — bu zaten [AlertSettings.prayerAlarms] üzerinden
/// yönetiliyor — o vaktin *sesli* mi yoksa *sessiz bildirim* mi olacağını
/// [type] üzerinden belirler ([PrayerSoundType.silent] seçilirse ses çalınmaz
/// ama bildirim yine de gösterilir).
class PrayerSoundSetting {
  final PrayerSoundType type;

  /// [type] == custom ise, [CustomAudioStore] içindeki dosyanın id'si.
  final String? customAudioId;

  const PrayerSoundSetting({
    this.type = PrayerSoundType.adhan,
    this.customAudioId,
  });

  PrayerSoundSetting copyWith({PrayerSoundType? type, String? customAudioId, bool clearCustomAudioId = false}) {
    return PrayerSoundSetting(
      type: type ?? this.type,
      customAudioId: clearCustomAudioId ? null : (customAudioId ?? this.customAudioId),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (customAudioId != null) 'customAudioId': customAudioId,
      };

  factory PrayerSoundSetting.fromJson(Map<String, dynamic> json) => PrayerSoundSetting(
        type: PrayerSoundType.fromName(json['type'] as String?),
        customAudioId: json['customAudioId'] as String?,
      );
}

/// Vakit isimleri ile aynı anahtarları kullanır (bkz. `alert_settings.dart`
/// içindeki `prayerNames`): 'İmsak', 'Öğle', 'İkindi', 'Akşam', 'Yatsı'.
/// Aynı map anahtarları uygulama genelinde (alarm eşleşmesi, bildirim
/// planlama) zaten kullanıldığı için ayrı bir anahtar seti (fajr/dhuhr/...)
/// tanımlamak yerine mevcut Türkçe isimler yeniden kullanılır.
Map<String, PrayerSoundSetting> defaultPrayerSounds() => {
      'İmsak': const PrayerSoundSetting(type: PrayerSoundType.adhan),
      'Öğle': const PrayerSoundSetting(type: PrayerSoundType.adhan),
      'İkindi': const PrayerSoundSetting(type: PrayerSoundType.adhan),
      'Akşam': const PrayerSoundSetting(type: PrayerSoundType.adhan),
      'Yatsı': const PrayerSoundSetting(type: PrayerSoundType.adhan),
    };

/// Vaktin ezan sesi asset yolunu döner (bkz. `assets/data/ezan_sesleri.json`).
String? adhanAssetForPrayer(String prayerName) {
  switch (prayerName) {
    case 'İmsak':
      return 'assets/audio/ezan_sabah.mp3';
    case 'Öğle':
      return 'assets/audio/ezan_ogle.mp3';
    case 'İkindi':
      return 'assets/audio/ezan_ikindi.mp3';
    case 'Akşam':
      return 'assets/audio/ezan_aksam.mp3';
    case 'Yatsı':
      return 'assets/audio/ezan_yatsi.mp3';
  }
  return null;
}

/// Android RAW resource adı (uzantısız) — `android/app/src/main/res/raw/`.
String? adhanRawResourceForPrayer(String prayerName) {
  switch (prayerName) {
    case 'İmsak':
      return 'ezan_sabah';
    case 'Öğle':
      return 'ezan_ogle';
    case 'İkindi':
      return 'ezan_ikindi';
    case 'Akşam':
      return 'ezan_aksam';
    case 'Yatsı':
      return 'ezan_yatsi';
  }
  return null;
}

/// Kısa bildirim sesi için hem asset hem RAW resource olarak zaten var olan
/// dosya yeniden kullanılır (bkz. `assets/audio/dakikakivaruyarisisesi_10.mp3`
/// / `android/.../raw/dakikakivaruyarisisesi_10.mp3`) — yeni bir ses dosyası
/// gerektirmez.
const String notificationSoundAsset = 'assets/audio/dakikakivaruyarisisesi_10.mp3';
const String notificationSoundRawResource = 'dakikakivaruyarisisesi_10';
