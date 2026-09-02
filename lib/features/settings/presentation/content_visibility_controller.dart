import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/prefs_repository.dart';

/// Ana Sayfa / Günlük İçerik sayfalarında hangi günlük içerik kartlarının
/// gösterileceğini kontrol eder (Ayarlar > İçerik).
class ContentVisibility {
  final bool showAyet;
  final bool showHadith;
  final bool showEvent;
  final bool showSoz;

  const ContentVisibility({
    this.showAyet = true,
    this.showHadith = true,
    this.showEvent = true,
    this.showSoz = true,
  });

  ContentVisibility copyWith({bool? showAyet, bool? showHadith, bool? showEvent, bool? showSoz}) => ContentVisibility(
        showAyet: showAyet ?? this.showAyet,
        showHadith: showHadith ?? this.showHadith,
        showEvent: showEvent ?? this.showEvent,
        showSoz: showSoz ?? this.showSoz,
      );
}

class ContentVisibilityController extends StateNotifier<ContentVisibility> {
  final PrefsRepository _prefs;

  ContentVisibilityController(this._prefs)
      : super(ContentVisibility(
          showAyet: _prefs.getShowAyet(),
          showHadith: _prefs.getShowHadith(),
          showEvent: _prefs.getShowEvent(),
          showSoz: _prefs.getShowSoz(),
        ));

  Future<void> setShowAyet(bool value) async {
    state = state.copyWith(showAyet: value);
    await _prefs.setShowAyet(value);
  }

  Future<void> setShowHadith(bool value) async {
    state = state.copyWith(showHadith: value);
    await _prefs.setShowHadith(value);
  }

  Future<void> setShowEvent(bool value) async {
    state = state.copyWith(showEvent: value);
    await _prefs.setShowEvent(value);
  }

  Future<void> setShowSoz(bool value) async {
    state = state.copyWith(showSoz: value);
    await _prefs.setShowSoz(value);
  }
}

final contentVisibilityProvider = StateNotifierProvider<ContentVisibilityController, ContentVisibility>((ref) {
  return ContentVisibilityController(ref.watch(prefsRepositoryProvider));
});
