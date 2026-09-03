import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme.dart';
import '../../dashboard/presentation/app_shell.dart';
import '../../dashboard/presentation/date_navigator.dart';
import '../../dashboard/presentation/selected_date_provider.dart';
import '../../favorites/data/models.dart';
import '../../locations/presentation/country_page.dart';
import '../../settings/data/prefs_repository.dart';
import '../../settings/presentation/content_visibility_controller.dart';
import '../../times/presentation/time_utils.dart';
import '../../times/presentation/times_page.dart' show timesProvider;
import '../data/daily_content_repository.dart';
import 'content_card.dart';

class DailyContentPage extends ConsumerWidget {
  const DailyContentPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
    final selectedDate = ref.watch(selectedDateProvider);
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    final recentLocations = ref.watch(prefsRepositoryProvider).getRecentLocations();
    final lastLocation = recentLocations.isNotEmpty ? recentLocations.first : null;

    final bundle = ref.watch(dailyContentForDateProvider(selectedDate));
    final historicalEvents = ref.watch(historicalEventsForDateProvider(selectedDate));
    final visibility = ref.watch(contentVisibilityProvider);

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
            if (lastLocation != null)
              _PrayerTimesMiniCard(ilceId: lastLocation.ilce.ilceId, ilceAdi: lastLocation.ilce.ilceAdi, date: selectedDate)
            else
              _NoLocationCard(
                onSelectLocation: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CountryPage()));
                },
              ),
            const SizedBox(height: 12),
            if (bundle == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (visibility.showAyet) ...[
                ContentCard(
                  icon: Icons.menu_book_outlined,
                  title: 'Günün Âyeti',
                  body: '"${bundle.ayet.meal}"',
                  sourceLine: '${bundle.ayet.sureAdi} Sûresi, ${bundle.ayet.sureNo}:${bundle.ayet.ayetNo} — ${bundle.ayet.kaynak}',
                  shareText:
                      '📖 Günün Âyeti\n\n"${bundle.ayet.meal}"\n\n(${bundle.ayet.sureAdi} Sûresi, ${bundle.ayet.sureNo}:${bundle.ayet.ayetNo})\n\nEzan Vakti uygulamasından paylaşıldı.',
                  isSampleData: bundle.ayet.isSampleData,
                  backgroundColor: dashboardCardGreen(brightness),
                  favoriteType: FavoriteType.ayet,
                  favoriteRefId: 'ayet:${bundle.ayet.sureNo}:${bundle.ayet.ayetNo}',
                ),
                const SizedBox(height: 10),
              ],
              if (visibility.showHadith) ...[
                ContentCard(
                  icon: Icons.eco_outlined,
                  title: 'Günün Hadisi',
                  body: bundle.hadith.metin,
                  sourceLine: [
                    bundle.hadith.kaynak,
                    if (bundle.hadith.kitapBolum != null) bundle.hadith.kitapBolum!,
                    if (bundle.hadith.hadisNo != null) 'Hadis No: ${bundle.hadith.hadisNo}',
                  ].join(' • '),
                  shareText: '🌿 Günün Hadisi\n\n"${bundle.hadith.metin}"\n\n(${bundle.hadith.kaynak})\n\nEzan Vakti uygulamasından paylaşıldı.',
                  isSampleData: bundle.hadith.isSampleData,
                  verified: bundle.hadith.verified,
                  backgroundColor: dashboardCardGreen(brightness),
                  favoriteType: FavoriteType.hadith,
                  favoriteRefId: 'hadith:${bundle.hadith.metin.hashCode}',
                ),
                const SizedBox(height: 10),
              ],
              if (visibility.showEvent) ...[
                if (historicalEvents.isNotEmpty)
                  for (final event in historicalEvents) ...[
                    ContentCard(
                      icon: Icons.history_edu_outlined,
                      title: 'Tarihte Bugün',
                      body: '${event.yil ?? ''} — ${event.baslik}\n\n${event.aciklama}',
                      sourceLine: event.kaynak,
                      shareText: '📜 Tarihte Bugün\n\n${event.yil ?? ''} — ${event.baslik}\n${event.aciklama}\n\nEzan Vakti uygulamasından paylaşıldı.',
                      isSampleData: event.isSampleData,
                      backgroundColor: dashboardCardGold(brightness),
                      favoriteType: FavoriteType.event,
                      favoriteRefId: 'event:${event.ay}-${event.gun}-${event.baslik.hashCode}',
                    ),
                    if (event != historicalEvents.last) const SizedBox(height: 8),
                  ]
                else
                  Card(
                    color: dashboardCardGold(brightness),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.history_edu_outlined, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('Bu tarih için henüz tarihî olay eklenmemiş.'),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
              ],
              if (visibility.showSoz)
                ContentCard(
                  icon: Icons.format_quote_outlined,
                  title: 'Günün Sözü',
                  body: '"${bundle.soz.soz}"',
                  sourceLine: [bundle.soz.yazar, if (bundle.soz.eser != null) bundle.soz.eser!].join(' — '),
                  shareText: '💬 Günün Sözü\n\n"${bundle.soz.soz}"\n\n— ${bundle.soz.yazar}${bundle.soz.eser != null ? ', ${bundle.soz.eser}' : ''}\n\nEzan Vakti uygulamasından paylaşıldı.',
                  isSampleData: bundle.soz.isSampleData,
                  verified: bundle.soz.verified,
                  backgroundColor: dashboardCardGreen(brightness),
                  favoriteType: FavoriteType.soz,
                  favoriteRefId: 'soz:${bundle.soz.soz.hashCode}',
                ),
            ],
          ],
      ),
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
        onPressed: () {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
          ref.read(dashboardSelectedTabProvider.notifier).state = 0;
        },
        icon: const Icon(Icons.arrow_back),
        label: const Text('Ana Sayfa'),
      ),
    );
  }
}

class _PrayerTimesMiniCard extends ConsumerWidget {
  final String ilceId;
  final String ilceAdi;
  final DateTime date;

  const _PrayerTimesMiniCard({required this.ilceId, required this.ilceAdi, required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTimes = ref.watch(timesProvider(ilceId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: asyncTimes.when(
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
          error: (e, _) => Text('Namaz vakitleri alınamadı: $e'),
          data: (list) {
            final vakit = findVakitForDate(list, date);
            if (vakit == null) {
              return const Text('Bu tarih için namaz vakti verisi bulunamadı.');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ilceAdi.toUpperCase(),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  vakit.hicriTarihUzun,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _VakitChip('İmsak', vakit.imsak),
                    _VakitChip('Güneş', vakit.gunes),
                    _VakitChip('Öğle', vakit.ogle),
                    _VakitChip('İkindi', vakit.ikindi),
                    _VakitChip('Akşam', vakit.aksam),
                    _VakitChip('Yatsı', vakit.yatsi),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _VakitChip extends StatelessWidget {
  final String name;
  final String time;

  const _VakitChip(this.name, this.time);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(name, style: Theme.of(context).textTheme.labelSmall),
          Text(time, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _NoLocationCard extends StatelessWidget {
  final VoidCallback onSelectLocation;

  const _NoLocationCard({required this.onSelectLocation});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Expanded(child: Text('Namaz vakitlerini görmek için önce bir konum seçin.')),
            const SizedBox(width: 8),
            FilledButton(onPressed: onSelectLocation, child: const Text('Konum Seç')),
          ],
        ),
      ),
    );
  }
}
