import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../favorites/data/models.dart';
import '../../locations/data/models.dart';

final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

final prefsRepositoryProvider =
    Provider<PrefsRepository>((ref) => PrefsRepository(ref.watch(sharedPrefsProvider)));

class PrefsRepository {
  final SharedPreferences _prefs;

  PrefsRepository(this._prefs);

  static const _recentLocationsKey = 'recent_locations';
  static const _themeModeKey = 'theme_mode';
  static const _cachedVakitlerKey = 'cached_vakitler_';
  static const _favoritesKey = 'favorite_content_items';

  List<FavoriteItem> getFavorites() {
    final jsonList = _prefs.getStringList(_favoritesKey) ?? [];
    return jsonList
        .map((s) => FavoriteItem.fromJson(json.decode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveFavorites(List<FavoriteItem> items) async {
    final jsonList = items.map((f) => json.encode(f.toJson())).toList();
    await _prefs.setStringList(_favoritesKey, jsonList);
  }

  static const _showAyetKey = 'content_show_ayet';
  static const _showHadithKey = 'content_show_hadith';
  static const _showEventKey = 'content_show_event';
  static const _showSozKey = 'content_show_soz';

  bool getShowAyet() => _prefs.getBool(_showAyetKey) ?? true;
  bool getShowHadith() => _prefs.getBool(_showHadithKey) ?? true;
  bool getShowEvent() => _prefs.getBool(_showEventKey) ?? true;
  bool getShowSoz() => _prefs.getBool(_showSozKey) ?? true;

  Future<void> setShowAyet(bool value) => _prefs.setBool(_showAyetKey, value);
  Future<void> setShowHadith(bool value) => _prefs.setBool(_showHadithKey, value);
  Future<void> setShowEvent(bool value) => _prefs.setBool(_showEventKey, value);
  Future<void> setShowSoz(bool value) => _prefs.setBool(_showSozKey, value);

  Future<void> saveVakitler(String ilceId, List<Vakit> list) async {
    final data = list.map((v) => v.toJson()).toList();
    await _prefs.setString(_cachedVakitlerKey + ilceId, json.encode(data));
  }

  List<Vakit>? getCachedVakitler(String ilceId) {
    final jsonStr = _prefs.getString(_cachedVakitlerKey + ilceId);
    if (jsonStr == null) return null;
    final List<dynamic> data = json.decode(jsonStr);
    return data.map((item) => Vakit.fromJson(item as Map<String, dynamic>)).toList();
  }

  List<SavedLocation> getRecentLocations() {
    final locationsJson = _prefs.getStringList(_recentLocationsKey) ?? [];
    return locationsJson
        .map((jsonString) => SavedLocation.fromJson(json.decode(jsonString) as Map<String, dynamic>))
        .toList();
  }

  Future<void> addRecentLocation(SavedLocation newLocation) async {
    final currentLocations = getRecentLocations();
    currentLocations.removeWhere((loc) => loc.ilce.ilceId == newLocation.ilce.ilceId);
    currentLocations.insert(0, newLocation);
    final updatedList = currentLocations.take(4).toList();
    final List<String> jsonList = updatedList.map((loc) => json.encode(loc.toJson())).toList();
    await _prefs.setStringList(_recentLocationsKey, jsonList);
  }

  ThemeMode getThemeMode() {
    final themeName = _prefs.getString(_themeModeKey);
    return ThemeMode.values.firstWhere((e) => e.name == themeName, orElse: () => ThemeMode.system);
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    await _prefs.setString(_themeModeKey, mode.name);
  }

}
