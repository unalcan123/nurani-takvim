import 'custom_audio_store.dart';

enum PrayerType {
  fajr,
  dhuhr,
  asr,
  maghrib,
  isha;

  bool get isFajr => this == PrayerType.fajr;

  static PrayerType fromPrayerName(String prayerName) {
    switch (prayerName) {
      case 'İmsak':
      case 'Sabah':
        return PrayerType.fajr;
      case 'Öğle':
        return PrayerType.dhuhr;
      case 'İkindi':
        return PrayerType.asr;
      case 'Akşam':
        return PrayerType.maghrib;
      case 'Yatsı':
        return PrayerType.isha;
      default:
        return PrayerType.dhuhr;
    }
  }
}

enum AdhanType {
  makkah,
  madinah,
  world,
  custom;

  String get storageValue => name;

  static AdhanType fromStorage(String? value) => AdhanType.values.firstWhere(
        (e) => e.storageValue == value,
        orElse: () => AdhanType.makkah,
      );
}

class AdhanSettings {
  final AdhanType type;
  final String? worldAssetPath;
  final String? customAudioId;

  const AdhanSettings({
    this.type = AdhanType.makkah,
    this.worldAssetPath,
    this.customAudioId,
  });

  AdhanSettings copyWith({
    AdhanType? type,
    String? worldAssetPath,
    String? customAudioId,
    bool clearWorldAssetPath = false,
    bool clearCustomAudioId = false,
  }) {
    return AdhanSettings(
      type: type ?? this.type,
      worldAssetPath: clearWorldAssetPath ? null : (worldAssetPath ?? this.worldAssetPath),
      customAudioId: clearCustomAudioId ? null : (customAudioId ?? this.customAudioId),
    );
  }
}

class AdhanSource {
  final String title;
  final String? assetPath;
  final CustomAudioFile? customFile;

  const AdhanSource.asset({required this.title, required String path})
      : assetPath = path,
        customFile = null;

  const AdhanSource.custom({required this.title, required CustomAudioFile file})
      : assetPath = null,
        customFile = file;

  bool get isAsset => assetPath != null;
}

const String makkahNormalAdhanAsset = 'assets/audio/adhan/makkah/ezan_mekke.mp3';
const String makkahFajrAdhanAsset = 'assets/audio/adhan/makkah/fecr_mekke.mp3';
const String madinahNormalAdhanAsset = 'assets/audio/adhan/madinah/ezan_medine.mp3';
const String madinahFajrAdhanAsset = 'assets/audio/adhan/madinah/fecr_medine.mp3';

String cleanAdhanTitle(String assetOrFileName) {
  var title = assetOrFileName.replaceAll('\\', '/').split('/').last;
  title = title.replaceFirst(RegExp(r'\.(mp3|m4a|wav|ogg)$', caseSensitive: false), '');
  title = title.replaceAll('_', ' ');
  title = title.replaceAll(RegExp(r'\s*\([^)]*[\u0600-\u06ff][^)]*\)\s*'), ' ');
  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  return title.isEmpty ? 'Ezan' : title;
}

Future<AdhanSource> resolveSelectedAdhan({
  required PrayerType prayer,
  required AdhanSettings settings,
  required CustomAudioStore customAudioStore,
}) async {
  switch (settings.type) {
    case AdhanType.makkah:
      return AdhanSource.asset(
        title: prayer.isFajr ? 'Mekke - Sabah Ezanı' : 'Mekke - Mescid-i Haram',
        path: prayer.isFajr ? makkahFajrAdhanAsset : makkahNormalAdhanAsset,
      );
    case AdhanType.madinah:
      return AdhanSource.asset(
        title: prayer.isFajr ? 'Medine - Sabah Ezanı' : 'Medine - Mescid-i Nebevi',
        path: prayer.isFajr ? madinahFajrAdhanAsset : madinahNormalAdhanAsset,
      );
    case AdhanType.world:
      final path = settings.worldAssetPath;
      if (path != null && path.isNotEmpty) {
        return AdhanSource.asset(title: cleanAdhanTitle(path), path: path);
      }
      return _fallbackSource(prayer);
    case AdhanType.custom:
      final id = settings.customAudioId;
      if (id != null) {
        final file = await customAudioStore.get(id);
        if (file != null) {
          return AdhanSource.custom(title: cleanAdhanTitle(file.fileName), file: file);
        }
      }
      return _fallbackSource(prayer);
  }
}

AdhanSource _fallbackSource(PrayerType prayer) {
  return AdhanSource.asset(
    title: prayer.isFajr ? 'Mekke - Sabah Ezanı' : 'Mekke - Mescid-i Haram',
    path: prayer.isFajr ? makkahFajrAdhanAsset : makkahNormalAdhanAsset,
  );
}
