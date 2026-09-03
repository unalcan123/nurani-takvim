import 'prayer_sound_settings.dart';

const List<String> prayerNames = ['İmsak', 'Öğle', 'İkindi', 'Akşam', 'Yatsı'];

const List<int> preNotificationMinutes = [30, 20, 10];

const Map<int, String> preNotificationAssets = {
  30: 'assets/audio/dakikakivaruyarisisesi_30.mp3',
  20: 'assets/audio/dakikakivaruyarisisesi_20.mp3',
  10: 'assets/audio/dakikakivaruyarisisesi_10.mp3',
};

/// Varsayılan arka plan müziği
const String defaultBgMusicPath = 'assets/music/Video download (1).mp3';

class AlertSettings {
  final Map<String, bool> prayerAlarms;

  /// Her vakit için bağımsız ses ayarı (ezan / kısa bildirim / kendi sesi / sessiz).
  final Map<String, PrayerSoundSetting> prayerSounds;

  /// Ezan/bildirim ortak ses seviyesi (0.0 - 1.0).
  final double ezanVolume;

  final Map<int, bool> preNotifications;
  final int slideDuration;
  final String slideCategory;
  final int lastUpdate;
  final Map<String, String> userCategories;

  // Birden fazla müzik desteği için List kullanıyoruz
  final List<String> bgMusicPaths;
  final bool bgMusicEnabled;

  AlertSettings({
    Map<String, bool>? prayerAlarms,
    Map<String, PrayerSoundSetting>? prayerSounds,
    this.ezanVolume = 1.0,
    Map<int, bool>? preNotifications,
    this.slideDuration = 15,
    this.slideCategory = 'all',
    this.lastUpdate = 0,
    this.userCategories = const {},
    this.bgMusicPaths = const [defaultBgMusicPath],
    this.bgMusicEnabled = true,
  })  : prayerAlarms = prayerAlarms ?? {for (var v in prayerNames) v: false},
        prayerSounds = prayerSounds ?? defaultPrayerSounds(),
        preNotifications = preNotifications ?? {for (var m in preNotificationMinutes) m: false};

  bool isPrayerEnabled(String prayerName) {
    return prayerAlarms[prayerName] ?? false;
  }

  PrayerSoundSetting soundFor(String prayerName) {
    return prayerSounds[prayerName] ?? const PrayerSoundSetting();
  }

  bool isPreNotificationEnabled(int minute) {
    return preNotifications[minute] ?? false;
  }

  AlertSettings copyWith({
    Map<String, bool>? prayerAlarms,
    Map<String, PrayerSoundSetting>? prayerSounds,
    double? ezanVolume,
    Map<int, bool>? preNotifications,
    int? slideDuration,
    String? slideCategory,
    int? lastUpdate,
    Map<String, String>? userCategories,
    List<String>? bgMusicPaths,
    bool? bgMusicEnabled,
  }) {
    return AlertSettings(
      prayerAlarms: prayerAlarms ?? this.prayerAlarms,
      prayerSounds: prayerSounds ?? this.prayerSounds,
      ezanVolume: ezanVolume ?? this.ezanVolume,
      preNotifications: preNotifications ?? this.preNotifications,
      slideDuration: slideDuration ?? this.slideDuration,
      slideCategory: slideCategory ?? this.slideCategory,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      userCategories: userCategories ?? this.userCategories,
      bgMusicPaths: bgMusicPaths ?? this.bgMusicPaths,
      bgMusicEnabled: bgMusicEnabled ?? this.bgMusicEnabled,
    );
  }
}
