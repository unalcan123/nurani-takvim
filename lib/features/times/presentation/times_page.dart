import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/live_clock.dart';
import '../../../widgets/app_drawer.dart';
import '../../dashboard/presentation/dashboard_home_page.dart';
import '../../locations/data/location_providers.dart';
import '../../locations/data/models.dart';

final timesProvider = FutureProvider.autoDispose.family<List<Vakit>, String>((
  ref,
  ilceId,
) async {
  ref.watch(liveClockProvider.select((now) => (now.year, now.month, now.day)));
  // Retry expired offline data without invalidating an in-flight request each second.
  final retry = Timer(const Duration(minutes: 5), ref.invalidateSelf);
  ref.onDispose(retry.cancel);
  final repo = ref.watch(locationRepoProvider);
  return repo.vakitler(ilceId);
});

/// TV mode uses the same responsive home composition and the existing TV drawer.
class TimesPage extends StatelessWidget {
  final Ulke ulke;
  final Sehir sehir;
  final Ilce ilce;
  const TimesPage({super.key, required this.ulke, required this.sehir, required this.ilce});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: calendarBackground,
    drawer: const AppDrawer(),
    body: SafeArea(child: DashboardHomePage(
      location: SavedLocation(ulke: ulke, sehir: sehir, ilce: ilce),
    )),
  );
}
