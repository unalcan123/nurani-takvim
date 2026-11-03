import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tvaap_clean/features/settings/data/adhan_settings.dart';
import 'package:tvaap_clean/features/settings/data/custom_audio_store.dart';
import 'package:tvaap_clean/features/settings/data/ezan_library.dart';

const _normalAsset = 'a_normal';
const _fajrAsset = 'a_fajr';
const _fajrRemote = 'r_fajr';

class _FakeLibrary extends EzanLibraryService {
  static const _entries = {
    _normalAsset: EzanLibraryEntry(id: _normalAsset, title: 'Normal',
        category: EzanLibraryCategory.normal, source: EzanLibrarySource.asset,
        assetPath: 'normal.mp3'),
    _fajrAsset: EzanLibraryEntry(id: _fajrAsset, title: 'Fecr',
        category: EzanLibraryCategory.fajr, source: EzanLibrarySource.asset,
        assetPath: 'fecr.mp3'),
    _fajrRemote: EzanLibraryEntry(id: _fajrRemote, title: 'Fecr Uzak',
        category: EzanLibraryCategory.fajr, source: EzanLibrarySource.remote,
        fileName: 'fecr.uzak.mp3'),
  };

  @override
  Future<EzanLibraryEntry?> findById(String id) async => _entries[id];
}

class _FakeCache extends EzanDownloadCache {
  @override
  Future<Uint8List?> cachedBytes(EzanLibraryEntry entry) async =>
      Uint8List.fromList([1, 2, 3]);
}

Future<AdhanSource> _resolve(PrayerType prayer, AdhanSettings settings) =>
    resolveSelectedAdhan(
      prayer: prayer,
      settings: settings,
      customAudioStore: CustomAudioStore(),
      libraryService: _FakeLibrary(),
      downloadCache: _FakeCache(),
    );

void main() {
  const normalPrayers = [
    PrayerType.dhuhr, PrayerType.asr, PrayerType.maghrib, PrayerType.isha,
  ];

  test('prayer names map to their own prayer type', () {
    expect(PrayerType.fromPrayerName('İmsak'), PrayerType.fajr);
    expect(PrayerType.fromPrayerName('Sabah'), PrayerType.fajr);
    expect(PrayerType.fromPrayerName('İkindi'), PrayerType.asr);
    expect(PrayerType.fromPrayerName('İkindi').isFajr, isFalse);
  });

  for (final (type, fajr, normal) in [
    (AdhanType.makkah, makkahFajrAdhanAsset, makkahNormalAdhanAsset),
    (AdhanType.madinah, madinahFajrAdhanAsset, madinahNormalAdhanAsset),
  ]) {
    test('$type plays the fajr recording only at fajr', () async {
      final settings = AdhanSettings(type: type);
      expect((await _resolve(PrayerType.fajr, settings)).assetPath, fajr);
      for (final prayer in normalPrayers) {
        expect((await _resolve(prayer, settings)).assetPath, normal);
      }
    });
  }

  test('a fajr entry stored as the normal selection never plays at ikindi',
      () async {
    const settings = AdhanSettings(type: AdhanType.library,
        libraryEntryId: _fajrAsset, libraryFajrEntryId: _fajrAsset);
    expect((await _resolve(PrayerType.asr, settings)).assetPath,
        makkahNormalAdhanAsset);
    expect((await _resolve(PrayerType.fajr, settings)).assetPath, 'fecr.mp3');
  });

  test('a fajr entry stored only as the normal selection still plays at fajr',
      () async {
    const settings = AdhanSettings(type: AdhanType.library,
        libraryEntryId: _fajrRemote);
    expect((await _resolve(PrayerType.fajr, settings)).title, 'Fecr Uzak');
    expect((await _resolve(PrayerType.asr, settings)).assetPath,
        makkahNormalAdhanAsset);
  });

  test('a normal library entry does not replace the fajr adhan', () async {
    const settings = AdhanSettings(type: AdhanType.library,
        libraryEntryId: _normalAsset);
    expect((await _resolve(PrayerType.asr, settings)).assetPath, 'normal.mp3');
    expect((await _resolve(PrayerType.fajr, settings)).assetPath,
        makkahFajrAdhanAsset);
  });

  test('separate library selections each play at their own prayer', () async {
    const settings = AdhanSettings(type: AdhanType.library,
        libraryEntryId: _normalAsset, libraryFajrEntryId: _fajrAsset);
    expect((await _resolve(PrayerType.fajr, settings)).assetPath, 'fecr.mp3');
    for (final prayer in normalPrayers) {
      expect((await _resolve(prayer, settings)).assetPath, 'normal.mp3');
    }
  });

  test('a world fajr recording is limited to fajr', () async {
    const path = 'assets/audio/adhan/dunya_ezan/Adhan_Fajr_Algeria.mp3';
    const settings = AdhanSettings(type: AdhanType.world, worldAssetPath: path);
    expect((await _resolve(PrayerType.fajr, settings)).assetPath, path);
    expect((await _resolve(PrayerType.asr, settings)).assetPath,
        makkahNormalAdhanAsset);
  });

  test('a world normal recording is limited to the normal prayers', () async {
    const path = 'assets/audio/adhan/dunya_ezan/Adhan_Kuwait.mp3';
    const settings = AdhanSettings(type: AdhanType.world, worldAssetPath: path);
    expect((await _resolve(PrayerType.asr, settings)).assetPath, path);
    expect((await _resolve(PrayerType.fajr, settings)).assetPath,
        makkahFajrAdhanAsset);
  });

  testWidgets('every library entry named as fajr is categorised as fajr',
      (tester) async {
    final manifest = await tester.runAsync(EzanLibraryService().loadManifest);
    final mislabeled = manifest!.entries.where((e) =>
        !e.isFajr &&
        RegExp(r'fajr|fecr|sabah', caseSensitive: false).hasMatch(e.title));
    expect(mislabeled.map((e) => e.title), isEmpty);
  });
}
