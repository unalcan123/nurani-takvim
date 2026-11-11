import 'custom_audio_store.dart';
import 'ezan_library.dart';

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
  custom,
  library;

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

  /// [AdhanType.library] seçiliyken: normal (fecr dışı) dört vakit için
  /// kullanılan kütüphane kaydının kimliği.
  final String? libraryEntryId;

  /// [AdhanType.library] seçiliyken: sabah (fecr) vakti için seçilen kaydın
  /// kimliği. `null` ise sabah vaktinde varsayılan Mekke sabah ezanı çalınır;
  /// normal bir kayıt sabah vaktinde hiçbir zaman kullanılmaz.
  final String? libraryFajrEntryId;

  /// Vakit başına ezan seçimi. Değer bir kütüphane kaydı kimliği,
  /// `custom:<id>` (telefondan seçilen dosya) ya da `asset:<yol>` olabilir.
  /// Kaydı olmayan vakit varsayılan Mekke ezanını çalar (sabahta fecr kaydı).
  final Map<PrayerType, String> perPrayer;

  const AdhanSettings({
    this.type = AdhanType.makkah,
    this.worldAssetPath,
    this.customAudioId,
    this.libraryEntryId,
    this.libraryFajrEntryId,
    this.perPrayer = const {},
  });

  /// Eski tek seçimli ayarı vakit başına seçime çevirir. Sonuç her vakitte
  /// eskisiyle aynı sesi çalar; fecr kaydı yine yalnızca sabah kullanılır.
  Map<PrayerType, String> legacyPerPrayer() {
    final out = <PrayerType, String>{};
    for (final prayer in PrayerType.values) {
      final fajr = prayer.isFajr;
      String? token;
      switch (type) {
        case AdhanType.makkah:
          break;
        case AdhanType.madinah:
          token = fajr ? 'a_fecr_medine' : 'a_ezan_medine';
        case AdhanType.world:
          final path = worldAssetPath;
          if (path != null && _isFajrRecordingPath(path) == fajr) {
            token = '$assetTokenPrefix$path';
          }
        case AdhanType.custom:
          if (customAudioId != null) token = '$customTokenPrefix$customAudioId';
        case AdhanType.library:
          // Eski sürümler sabah için normal kaydı da deniyordu; kategori
          // çözümlemede yeniden denetlendiği için ikisi de aday olarak kalır.
          token = fajr ? (libraryFajrEntryId ?? libraryEntryId) : libraryEntryId;
      }
      if (token != null) out[prayer] = token;
    }
    return out;
  }

  AdhanSettings copyWith({
    AdhanType? type,
    String? worldAssetPath,
    String? customAudioId,
    String? libraryEntryId,
    String? libraryFajrEntryId,
    bool clearWorldAssetPath = false,
    bool clearCustomAudioId = false,
    bool clearLibraryFajrEntryId = false,
    Map<PrayerType, String>? perPrayer,
  }) {
    return AdhanSettings(
      type: type ?? this.type,
      worldAssetPath: clearWorldAssetPath ? null : (worldAssetPath ?? this.worldAssetPath),
      customAudioId: clearCustomAudioId ? null : (customAudioId ?? this.customAudioId),
      libraryEntryId: libraryEntryId ?? this.libraryEntryId,
      libraryFajrEntryId: clearLibraryFajrEntryId
          ? null
          : (libraryFajrEntryId ?? this.libraryFajrEntryId),
      perPrayer: perPrayer ?? this.perPrayer,
    );
  }
}

const String customTokenPrefix = 'custom:';
const String assetTokenPrefix = 'asset:';

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
  EzanLibraryService? libraryService,
  EzanDownloadCache? downloadCache,
}) async {
  final token = settings.perPrayer[prayer];
  if (token != null) {
    return await _resolveToken(
          token,
          prayer: prayer,
          customAudioStore: customAudioStore,
          libraryService: libraryService,
          downloadCache: downloadCache,
        ) ??
        _fallbackSource(prayer);
  }
  if (settings.perPrayer.isNotEmpty || settings.type == AdhanType.makkah) {
    return _fallbackSource(prayer);
  }
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
      // A world recording is one file, so only use it for the prayer group it
      // was recorded for: a fajr adhan contains "es-salâtü hayrun mine'n-nevm".
      if (path != null &&
          path.isNotEmpty &&
          _isFajrRecordingPath(path) == prayer.isFajr) {
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
    case AdhanType.library:
      // Older versions could store a fajr recording as the normal selection,
      // so the entry's category is checked here as well as at selection time.
      final ids = prayer.isFajr
          ? [settings.libraryFajrEntryId, settings.libraryEntryId]
          : [settings.libraryEntryId];
      final service = libraryService ?? EzanLibraryService();
      for (final id in ids) {
        if (id == null) continue;
        final entry = await service.findById(id);
        if (entry != null && entry.isFajr == prayer.isFajr) {
          if (entry.source == EzanLibrarySource.asset) {
            return AdhanSource.asset(title: entry.title, path: entry.assetPath!);
          }
          final cache = downloadCache ?? EzanDownloadCache();
          final bytes = await cache.cachedBytes(entry);
          if (bytes != null) {
            return AdhanSource.custom(
              title: entry.title,
              file: CustomAudioFile(
                id: entry.id,
                fileName: '${entry.title}.mp3',
                bytes: bytes,
                addedAt: DateTime.now(),
              ),
            );
          }
        }
      }
      return _fallbackSource(prayer);
  }
}

/// Bir vaktin seçim kaydını sese çevirir. Kayıt bulunamazsa, indirilmemişse
/// ya da kaydın vakit grubu tutmuyorsa (normal vakitte fecr kaydı gibi)
/// `null` döner; çağıran taraf varsayılan Mekke ezanını çalar.
Future<AdhanSource?> _resolveToken(
  String token, {
  required PrayerType prayer,
  required CustomAudioStore customAudioStore,
  EzanLibraryService? libraryService,
  EzanDownloadCache? downloadCache,
}) async {
  if (token.startsWith(customTokenPrefix)) {
    final file =
        await customAudioStore.get(token.substring(customTokenPrefix.length));
    if (file == null) return null;
    return AdhanSource.custom(title: cleanAdhanTitle(file.fileName), file: file);
  }
  if (token.startsWith(assetTokenPrefix)) {
    final path = token.substring(assetTokenPrefix.length);
    if (_isFajrRecordingPath(path) != prayer.isFajr) return null;
    return AdhanSource.asset(title: cleanAdhanTitle(path), path: path);
  }
  final entry = await (libraryService ?? EzanLibraryService()).findById(token);
  if (entry == null || entry.isFajr != prayer.isFajr) return null;
  if (entry.source == EzanLibrarySource.asset) {
    return AdhanSource.asset(title: entry.title, path: entry.assetPath!);
  }
  final bytes = await (downloadCache ?? EzanDownloadCache()).cachedBytes(entry);
  if (bytes == null) return null;
  return AdhanSource.custom(
    title: entry.title,
    file: CustomAudioFile(
      id: entry.id,
      fileName: '${entry.title}.mp3',
      bytes: bytes,
      addedAt: DateTime.now(),
    ),
  );
}

bool _isFajrRecordingPath(String path) =>
    RegExp(r'fajr|fecr|الفجر', caseSensitive: false).hasMatch(path);

AdhanSource _fallbackSource(PrayerType prayer) {
  return AdhanSource.asset(
    title: prayer.isFajr ? 'Mekke - Sabah Ezanı' : 'Mekke - Mescid-i Haram',
    path: prayer.isFajr ? makkahFajrAdhanAsset : makkahNormalAdhanAsset,
  );
}
