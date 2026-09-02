import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/data/prefs_repository.dart';
import 'models.dart';

class FavoritesController extends StateNotifier<List<FavoriteItem>> {
  final PrefsRepository _prefs;

  FavoritesController(this._prefs) : super(_prefs.getFavorites());

  bool isFavorite(String refId) => state.any((f) => f.refId == refId);

  Future<void> toggle(FavoriteItem item) async {
    if (isFavorite(item.refId)) {
      state = state.where((f) => f.refId != item.refId).toList();
    } else {
      state = [item, ...state];
    }
    await _prefs.saveFavorites(state);
  }

  Future<void> remove(String refId) async {
    state = state.where((f) => f.refId != refId).toList();
    await _prefs.saveFavorites(state);
  }
}

final favoritesProvider = StateNotifierProvider<FavoritesController, List<FavoriteItem>>((ref) {
  return FavoritesController(ref.watch(prefsRepositoryProvider));
});
