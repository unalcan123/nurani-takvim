import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme.dart';
import '../../locations/presentation/country_page.dart';
import '../../settings/data/prefs_repository.dart';
import '../../times/presentation/time_utils.dart';
import '../../times/presentation/times_page.dart' show timesProvider;
import 'app_shell.dart';
import 'date_navigator.dart';
import 'selected_date_provider.dart';

class PrayerTimesPage extends ConsumerWidget {
  const PrayerTimesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
    final selectedDate = ref.watch(selectedDateProvider);
    final recentLocations = ref.watch(prefsRepositoryProvider).getRecentLocations();
    final lastLocation = recentLocations.isNotEmpty ? recentLocations.first : null;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Container(
      color: dashboardBg(brightness),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (isLandscape) ...[
            const _HomeBackButton(),
            const SizedBox(height: 10),
          ],
          const DateNavigatorBar(),
          const SizedBox(height: 12),
          if (lastLocation == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Expanded(child: Text('Namaz vakitlerini görmek için önce bir konum seçin.')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CountryPage())),
                      child: const Text('Konum Seç'),
                    ),
                  ],
                ),
              ),
            )
          else
            _FullTimesCard(ilceId: lastLocation.ilce.ilceId, ilceAdi: lastLocation.ilce.ilceAdi, date: selectedDate),
        ],
      ),
    );
  }
}

class _FullTimesCard extends ConsumerWidget {
  final String ilceId;
  final String ilceAdi;
  final DateTime date;

  const _FullTimesCard({required this.ilceId, required this.ilceAdi, required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTimes = ref.watch(timesProvider(ilceId));
    final brightness = Theme.of(context).brightness;

    return asyncTimes.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Namaz vakitleri alınamadı: $e'))),
      data: (list) {
        final vakit = findVakitForDate(list, date);
        if (vakit == null) {
          return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Bu tarih için namaz vakti verisi bulunamadı.')));
        }

        final tomorrow = findVakitForDate(list, date.add(const Duration(days: 1)));
        final now = phoneLocalNow();
        final activeName = currentPrayerName(vakit, now);
        final next = nextPrayerInfo(vakit, now, tomorrow: tomorrow);

        final times = [
          ('İmsak', vakit.imsak, Icons.nights_stay_outlined),
          ('Güneş', vakit.gunes, Icons.wb_twilight_outlined),
          ('Öğle', vakit.ogle, Icons.wb_sunny_outlined),
          ('İkindi', vakit.ikindi, Icons.sunny_snowing),
          ('Akşam', vakit.aksam, Icons.wb_twilight),
          ('Yatsı', vakit.yatsi, Icons.dark_mode_outlined),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: dashboardCardGold(brightness),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ilceAdi.toUpperCase(), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    Text(vakit.hicriTarihUzun, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Text('${next.name} vaktine kalan süre', style: Theme.of(context).textTheme.bodyMedium),
                    Text(
                      _formatRemaining(next.time.difference(now)),
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            ...times.map((t) {
              final isActive = t.$1 == activeName;
              return Card(
                color: isActive ? dashboardAccentGreen.withValues(alpha: 0.15) : null,
                child: ListTile(
                  leading: Icon(t.$3, color: isActive ? dashboardAccentGold : null),
                  title: Text(t.$1, style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
                  trailing: Text(t.$2, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _HomeBackButton extends ConsumerWidget {
  const _HomeBackButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: () => ref.read(dashboardSelectedTabProvider.notifier).state = 0,
        icon: const Icon(Icons.arrow_back),
        label: const Text('Ana Sayfa'),
      ),
    );
  }
}

String _formatRemaining(Duration d) {
  if (d.isNegative) return '00:00:00';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
}
