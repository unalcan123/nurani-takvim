import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/dio_provider.dart';
import '../../settings/data/prefs_repository.dart';
import 'auto_location_service.dart';
import 'ezan_api.dart';
import 'location_repository.dart';

// Centralized providers for location feature
final dioProvider = Provider((ref) => createDio());
final ezanApiProvider = Provider((ref) => EzanApi(ref.watch(dioProvider)));
final locationRepoProvider = Provider<LocationRepository>((ref) {
  return LocationRepository(
    ref.watch(ezanApiProvider),
    ref.watch(prefsRepositoryProvider),
  );
});
final autoLocationServiceProvider = Provider<AutoLocationService>((ref) {
  return AutoLocationService(ref.watch(locationRepoProvider));
});
