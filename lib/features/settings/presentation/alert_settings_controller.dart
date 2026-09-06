import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/alert_settings.dart';
import '../data/adhan_settings.dart';
import '../data/custom_audio_store.dart';
import '../data/prefs_repository.dart';
import '../data/prayer_sound_settings.dart';

final customAudioStoreProvider = Provider<CustomAudioStore>((ref) => CustomAudioStore());

final alertSettingsProvider = StateNotifierProvider<AlertSettingsNotifier, AlertSettings>((ref) {
  return AlertSettingsNotifier(ref.watch(customAudioStoreProvider), ref.watch(sharedPrefsProvider));
});

class AlertSettingsNotifier extends StateNotifier<AlertSettings> {
  final CustomAudioStore _customAudioStore;
  final SharedPreferences _prefs;

  AlertSettingsNotifier(this._customAudioStore, this._prefs) : super(AlertSettings()) {
    _loadSettings();
  }

  static const _keyPrayerAlarms = 'prayer_alarms';
  static const _keyPrayerSounds = 'prayer_sounds_v1';
  static const _keySelectedAdhanType = 'selected_adhan_type';
  static const _keySelectedAdhanAssetPath = 'selected_adhan_asset_path';
  static const _keySelectedAdhanCustomAudioId = 'selected_adhan_custom_audio_id';
  static const _keyEzanVolume = 'ezan_volume';
  static const _keyPreNotifications = 'pre_notifications';
  static const _keySlideDuration = 'slide_duration';
  static const _keySlideCategory = 'slide_category';
  static const _keyUserCategories = 'user_categories';
  static const _keyBgMusicPaths = 'bg_music_paths'; // Değişti: List için
  static const _keyBgMusicEnabled = 'bg_music_enabled';

  void touchLastUpdate() {
    state = state.copyWith(lastUpdate: DateTime.now().millisecondsSinceEpoch);
  }

  void _loadSettings() {
    final alarmMap = <String, bool>{};
    for (var name in prayerNames) {
      alarmMap[name] = _prefs.getBool('${_keyPrayerAlarms}_$name') ?? false;
    }

    final preNotifyMap = <int, bool>{};
    for (var m in preNotificationMinutes) {
      preNotifyMap[m] = _prefs.getBool('${_keyPreNotifications}_$m') ?? false;
    }

    final userCatsRaw = _prefs.getString(_keyUserCategories);
    Map<String, String> userCats = {};
    if (userCatsRaw != null) {
      userCats = Map<String, String>.from(json.decode(userCatsRaw));
    }

    final musicPaths = _prefs.getStringList(_keyBgMusicPaths) ?? [defaultBgMusicPath];

    final soundsRaw = _prefs.getString(_keyPrayerSounds);
    Map<String, PrayerSoundSetting> prayerSounds = defaultPrayerSounds();
    if (soundsRaw != null) {
      try {
        final decoded = Map<String, dynamic>.from(json.decode(soundsRaw));
        prayerSounds = {
          for (var name in prayerNames)
            name: decoded.containsKey(name)
                ? PrayerSoundSetting.fromJson(Map<String, dynamic>.from(decoded[name]))
                : const PrayerSoundSetting(),
        };
      } catch (_) {
        // Bozuk kayıt varsa varsayılanlara dön.
      }
    }

    final adhanSettings = AdhanSettings(
      type: AdhanType.fromStorage(_prefs.getString(_keySelectedAdhanType)),
      worldAssetPath: _prefs.getString(_keySelectedAdhanAssetPath),
      customAudioId: _prefs.getString(_keySelectedAdhanCustomAudioId),
    );

    state = state.copyWith(
      prayerAlarms: alarmMap,
      prayerSounds: prayerSounds,
      ezanVolume: _prefs.getDouble(_keyEzanVolume) ?? 1.0,
      adhanSettings: adhanSettings,
      preNotifications: preNotifyMap,
      slideDuration: _prefs.getInt(_keySlideDuration) ?? 15,
      slideCategory: _prefs.getString(_keySlideCategory) ?? 'all',
      userCategories: userCats,
      bgMusicPaths: musicPaths,
      bgMusicEnabled: _prefs.getBool(_keyBgMusicEnabled) ?? false,
    );
  }

  Future<void> togglePrayerAlarm(String name, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_keyPrayerAlarms}_$name', value);

    final newAlarms = Map<String, bool>.from(state.prayerAlarms);
    newAlarms[name] = value;
    state = state.copyWith(prayerAlarms: newAlarms);
  }

  Future<void> _persistPrayerSounds(Map<String, PrayerSoundSetting> sounds) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode({for (final e in sounds.entries) e.key: e.value.toJson()});
    await prefs.setString(_keyPrayerSounds, encoded);
  }

  /// [prayerName] için ses türünü değiştirir. `custom` seçiliyorsa
  /// [customAudioId] verilmelidir (bkz. [pickAndAssignCustomAudio]).
  Future<void> setPrayerSoundType(String prayerName, PrayerSoundType type, {String? customAudioId}) async {
    final newSounds = Map<String, PrayerSoundSetting>.from(state.prayerSounds);
    final current = newSounds[prayerName] ?? const PrayerSoundSetting();
    newSounds[prayerName] = current.copyWith(
      type: type,
      customAudioId: type == PrayerSoundType.custom ? (customAudioId ?? current.customAudioId) : null,
      clearCustomAudioId: type != PrayerSoundType.custom,
    );
    await _persistPrayerSounds(newSounds);
    state = state.copyWith(prayerSounds: newSounds);
  }

  /// [prayerName] için doğrudan bir kayıtlı özel ses dosyasını atar (dosya
  /// zaten [CustomAudioStore] içindeyse — örn. bir vaktin sesi bir başka
  /// vaktin daha önce yüklediği dosyayla değiştiriliyorsa).
  Future<void> assignCustomAudio(String prayerName, String customAudioId) async {
    await setPrayerSoundType(prayerName, PrayerSoundType.custom, customAudioId: customAudioId);
  }

  /// Bayt dizisinden yeni bir özel ses dosyası oluşturup [prayerName]'e atar.
  Future<CustomAudioFile> addAndAssignCustomAudio(String prayerName, String fileName, Uint8List bytes) async {
    final file = await _customAudioStore.add(fileName, bytes);
    await assignCustomAudio(prayerName, file.id);
    return file;
  }

  /// Bir özel ses dosyasını kalıcı olarak siler. Bu dosyayı kullanan bir
  /// vakit varsa, o vakit varsayılan (ezan) sesine döner — sessizce kırık bir
  /// referansta bırakılmaz.
  Future<void> deleteCustomAudio(String customAudioId) async {
    final newSounds = Map<String, PrayerSoundSetting>.from(state.prayerSounds);
    for (final entry in newSounds.entries) {
      if (entry.value.type == PrayerSoundType.custom && entry.value.customAudioId == customAudioId) {
        newSounds[entry.key] = const PrayerSoundSetting(type: PrayerSoundType.adhan);
      }
    }
    await _customAudioStore.remove(customAudioId);
    await _persistPrayerSounds(newSounds);
    state = state.copyWith(prayerSounds: newSounds);
  }

  Future<void> setEzanVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyEzanVolume, clamped);
    state = state.copyWith(ezanVolume: clamped);
  }

  Future<void> selectMakkahAdhan() async {
    await _persistAdhanSettings(const AdhanSettings(type: AdhanType.makkah));
  }

  Future<void> selectMadinahAdhan() async {
    await _persistAdhanSettings(const AdhanSettings(type: AdhanType.madinah));
  }

  Future<void> selectWorldAdhan(String assetPath) async {
    await _persistAdhanSettings(AdhanSettings(type: AdhanType.world, worldAssetPath: assetPath));
  }

  Future<CustomAudioFile> addAndSelectCustomAdhan(String fileName, Uint8List bytes) async {
    final file = await _customAudioStore.add(fileName, bytes);
    await _persistAdhanSettings(AdhanSettings(type: AdhanType.custom, customAudioId: file.id));
    return file;
  }

  Future<void> _persistAdhanSettings(AdhanSettings settings) async {
    await _prefs.setString(_keySelectedAdhanType, settings.type.storageValue);
    if (settings.worldAssetPath == null) {
      await _prefs.remove(_keySelectedAdhanAssetPath);
    } else {
      await _prefs.setString(_keySelectedAdhanAssetPath, settings.worldAssetPath!);
    }
    if (settings.customAudioId == null) {
      await _prefs.remove(_keySelectedAdhanCustomAudioId);
    } else {
      await _prefs.setString(_keySelectedAdhanCustomAudioId, settings.customAudioId!);
    }
    state = state.copyWith(adhanSettings: settings);
  }

  Future<void> togglePreNotification(int minute, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_keyPreNotifications}_$minute', value);

    final newNotify = Map<int, bool>.from(state.preNotifications);
    newNotify[minute] = value;
    state = state.copyWith(preNotifications: newNotify);
  }

  Future<void> setSlideDuration(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySlideDuration, seconds);
    state = state.copyWith(slideDuration: seconds);
  }

  Future<void> setSlideCategory(String category) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySlideCategory, category);
    state = state.copyWith(slideCategory: category);
  }

  void triggerRefresh() {
    state = state.copyWith(lastUpdate: DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> addUserCategory(String name) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final newCats = Map<String, String>.from(state.userCategories);
    newCats[id] = name;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserCategories, json.encode(newCats));

    state = state.copyWith(userCategories: newCats);
  }

  Future<void> removeUserCategory(String id) async {
    final newCats = Map<String, String>.from(state.userCategories);
    newCats.remove(id);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserCategories, json.encode(newCats));

    String newCategory = state.slideCategory;
    if (state.slideCategory == id) {
      newCategory = 'all';
      await prefs.setString(_keySlideCategory, newCategory);
    }

    state = state.copyWith(userCategories: newCats, slideCategory: newCategory);
  }

  // ✅ Birden fazla arka plan müziği ekle
  Future<void> addBgMusicPaths(List<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    final newList = {...state.bgMusicPaths, ...paths}.toList();
    await prefs.setStringList(_keyBgMusicPaths, newList);
    state = state.copyWith(bgMusicPaths: newList);
  }

  // ✅ Arka plan müziği kaldır
  Future<void> removeBgMusicPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final newList = state.bgMusicPaths.where((p) => p != path).toList();
    if (newList.isEmpty) newList.add(defaultBgMusicPath);
    await prefs.setStringList(_keyBgMusicPaths, newList);
    state = state.copyWith(bgMusicPaths: newList);
  }

  // ✅ Arka plan müzik aç/kapat
  Future<void> toggleBgMusic(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBgMusicEnabled, value);
    state = state.copyWith(bgMusicEnabled: value);
  }
}
