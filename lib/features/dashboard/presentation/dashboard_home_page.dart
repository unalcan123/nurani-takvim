import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme.dart';
import '../../daily_content/data/daily_content_repository.dart';
import '../../daily_content/data/models.dart';
import '../../daily_content/presentation/content_card.dart';
import '../../favorites/data/models.dart';
import '../../locations/data/models.dart';
import '../../settings/data/prefs_repository.dart';
import '../../settings/presentation/content_visibility_controller.dart';
import '../../times/presentation/slayt_widget.dart';
import '../../times/presentation/time_utils.dart';
import '../../times/presentation/times_page.dart' show timesProvider;
import 'date_navigator.dart';
import 'selected_date_provider.dart';

const _wideBreakpoint = 1000.0;

/// Ana Sayfa. Kasıtlı olarak sade tutulur: yalnızca konum, tarih/hicri
/// tarih, hero/slayt alanı, namaz vakitleri, sonraki namaza geri sayım ve
/// dört günlük içerik kartı (+ paylaş butonları) bulunur. Tema, bildirim,
/// hesaplama yöntemi gibi hiçbir ayar kontrolü burada gösterilmez — hepsi
/// Ayarlar sayfasındadır (`settings_hub_page.dart`).
class DashboardHomePage extends ConsumerWidget {
  const DashboardHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final recentLocations = ref.watch(prefsRepositoryProvider).getRecentLocations();
    final lastLocation = recentLocations.isNotEmpty ? recentLocations.first : null;
    final bundle = ref.watch(dailyContentForDateProvider(selectedDate));
    final visibility = ref.watch(contentVisibilityProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;
        final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

        if (!wide && isLandscape) {
          return _LandscapeCompactLayout(
            ilceId: lastLocation?.ilce.ilceId,
            ilceAdi: lastLocation?.ilce.ilceAdi,
            date: selectedDate,
          );
        }

        final mainContent = _MainColumn(
          lastLocationLabel: lastLocation == null ? null : '${lastLocation.ilce.ilceAdi}, ${lastLocation.sehir.sehirAdi}',
          bundle: bundle,
          visibility: visibility,
          wide: wide,
        );

        final sidePanel = lastLocation == null
            ? const _NoLocationPanel()
            : _SidePanel(ilceId: lastLocation.ilce.ilceId, ilceAdi: lastLocation.ilce.ilceAdi, date: selectedDate);

        if (!wide) {
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [mainContent, const SizedBox(height: 12), sidePanel],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: ListView(padding: const EdgeInsets.all(16), children: [mainContent]),
            ),
            SizedBox(
              width: 320,
              child: ListView(padding: const EdgeInsets.fromLTRB(0, 16, 16, 16), children: [sidePanel]),
            ),
          ],
        );
      },
    );
  }
}

class _LocationLabel extends StatelessWidget {
  final String? label;

  const _LocationLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.location_on_outlined, size: 18),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label ?? 'Konum seçilmedi',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _MainColumn extends StatelessWidget {
  final String? lastLocationLabel;
  final DailyContentBundle? bundle;
  final ContentVisibility visibility;
  final bool wide;

  const _MainColumn({required this.lastLocationLabel, required this.bundle, required this.visibility, required this.wide});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    final cards = <_NamedCard>[
      if (visibility.showAyet && bundle != null)
        _NamedCard(
          'ayet',
          ContentCard(
            icon: Icons.menu_book_outlined,
            title: 'Günün Âyeti',
            body: '"${bundle!.ayet.meal}"',
            sourceLine: '${bundle!.ayet.sureAdi} Sûresi, ${bundle!.ayet.sureNo}:${bundle!.ayet.ayetNo}',
            shareText: shareTextForAyet(bundle!),
            isSampleData: bundle!.ayet.isSampleData,
            backgroundColor: dashboardCardGreen(brightness),
            favoriteType: FavoriteType.ayet,
            favoriteRefId: 'ayet:${bundle!.ayet.sureNo}:${bundle!.ayet.ayetNo}',
          ),
        ),
      if (visibility.showHadith && bundle != null)
        _NamedCard(
          'hadith',
          ContentCard(
            icon: Icons.eco_outlined,
            title: 'Günün Hadisi',
            body: bundle!.hadith.metin,
            sourceLine: bundle!.hadith.kaynak,
            shareText: shareTextForHadith(bundle!),
            isSampleData: bundle!.hadith.isSampleData,
            verified: bundle!.hadith.verified,
            backgroundColor: dashboardCardGreen(brightness),
            favoriteType: FavoriteType.hadith,
            favoriteRefId: 'hadith:${bundle!.hadith.metin.hashCode}',
          ),
        ),
      if (visibility.showEvent && bundle != null)
        _NamedCard(
          'event',
          bundle!.tarihiOlay != null
              ? ContentCard(
                  icon: Icons.history_edu_outlined,
                  title: 'Tarihte Bugün',
                  body: '${bundle!.tarihiOlay!.yil ?? ''} — ${bundle!.tarihiOlay!.baslik}',
                  sourceLine: bundle!.tarihiOlay!.kaynak,
                  shareText: shareTextForEvent(bundle!),
                  isSampleData: bundle!.tarihiOlay!.isSampleData,
                  backgroundColor: dashboardCardGold(brightness),
                  favoriteType: FavoriteType.event,
                  favoriteRefId: 'event:${bundle!.tarihiOlay!.ay}-${bundle!.tarihiOlay!.gun}',
                )
              : _EmptyEventCard(brightness: brightness),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LocationLabel(label: lastLocationLabel),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SlaytWidget(height: wide ? 260 : 200, userImages: const []),
        ),
        const SizedBox(height: 12),
        const DateNavigatorBar(),
        const SizedBox(height: 12),
        if (bundle == null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
        else if (cards.isNotEmpty)
          wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final c in cards) ...[Expanded(child: c.card), if (c != cards.last) const SizedBox(width: 10)],
                  ],
                )
              : Column(
                  children: [
                    for (final c in cards) ...[c.card, if (c != cards.last) const SizedBox(height: 10)],
                  ],
                ),
        if (bundle != null && visibility.showSoz) ...[
          const SizedBox(height: 10),
          ContentCard(
            icon: Icons.format_quote_outlined,
            title: 'Günün Sözü',
            body: '"${bundle!.soz.soz}"',
            sourceLine: [bundle!.soz.yazar, if (bundle!.soz.eser != null) bundle!.soz.eser!].join(' — '),
            shareText: shareTextForSoz(bundle!),
            isSampleData: bundle!.soz.isSampleData,
            verified: bundle!.soz.verified,
            backgroundColor: dashboardCardGreen(brightness),
            favoriteType: FavoriteType.soz,
            favoriteRefId: 'soz:${bundle!.soz.soz.hashCode}',
          ),
        ],
      ],
    );
  }
}

class _NamedCard {
  final String name;
  final Widget card;
  const _NamedCard(this.name, this.card);
}

String shareTextForAyet(DailyContentBundle b) =>
    '📖 Günün Âyeti\n\n"${b.ayet.meal}"\n\n(${b.ayet.sureAdi} Sûresi, ${b.ayet.sureNo}:${b.ayet.ayetNo})\n\nEzan Vakti uygulamasından paylaşıldı.';

String shareTextForHadith(DailyContentBundle b) =>
    '🌿 Günün Hadisi\n\n"${b.hadith.metin}"\n\n(${b.hadith.kaynak})\n\nEzan Vakti uygulamasından paylaşıldı.';

String shareTextForEvent(DailyContentBundle b) => b.tarihiOlay == null
    ? ''
    : '📜 Tarihte Bugün\n\n${b.tarihiOlay!.yil ?? ''} — ${b.tarihiOlay!.baslik}\n${b.tarihiOlay!.aciklama}\n\nEzan Vakti uygulamasından paylaşıldı.';

String shareTextForSoz(DailyContentBundle b) =>
    '💬 Günün Sözü\n\n"${b.soz.soz}"\n\n— ${b.soz.yazar}${b.soz.eser != null ? ', ${b.soz.eser}' : ''}\n\nEzan Vakti uygulamasından paylaşıldı.';

class _EmptyEventCard extends StatelessWidget {
  final Brightness brightness;

  const _EmptyEventCard({required this.brightness});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: dashboardCardGold(brightness),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.history_edu_outlined),
            SizedBox(width: 10),
            Expanded(child: Text('Bu tarih için kayıtlı bir tarihî olay henüz eklenmedi.')),
          ],
        ),
      ),
    );
  }
}

class _NoLocationPanel extends StatelessWidget {
  const _NoLocationPanel();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('Namaz vakitlerini görmek için Ayarlar > Konum bölümünden bir konum seçin.'),
      ),
    );
  }
}

/// Tarih/hicri tarih, sonraki namaza geri sayım ve namaz vakitleri
/// listesi — hiçbir ayar/kısayol butonu içermez.
class _SidePanel extends ConsumerWidget {
  final String ilceId;
  final String ilceAdi;
  final DateTime date;
  final bool showTimes;

  const _SidePanel({required this.ilceId, required this.ilceAdi, required this.date, this.showTimes = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTimes = ref.watch(timesProvider(ilceId));
    final brightness = Theme.of(context).brightness;

    return asyncTimes.when(
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
      error: (e, _) => Text('Namaz vakitleri alınamadı: $e'),
      data: (list) {
        final vakit = findVakitForDate(list, date);
        if (vakit == null) {
          return const Text('Bu tarih için namaz vakti verisi bulunamadı.');
        }
        final tomorrow = findVakitForDate(list, date.add(const Duration(days: 1)));
        final now = phoneLocalNow();
        final activeName = currentPrayerName(vakit, now);

        final times = prayerTimeEntries(vakit);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: dashboardCardGold(brightness),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Text(ilceAdi.toUpperCase(), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    Text(vakit.miladiTarihUzun, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                    Text(vakit.hicriTarihUzun, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: _LivePrayerCountdown(list: list),
              ),
            ),
            if (showTimes) ...[
              const SizedBox(height: 10),
              ...times.map((t) => Card(
                    color: t.$1 == activeName ? dashboardAccentGreen.withValues(alpha: 0.15) : null,
                    child: ListTile(
                      dense: true,
                      title: Text(t.$1, style: TextStyle(fontWeight: t.$1 == activeName ? FontWeight.bold : FontWeight.normal)),
                      trailing: Text(t.$2, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                  )),
            ],
          ],
        );
      },
    );
  }
}

List<(String, String)> prayerTimeEntries(Vakit vakit) => [
      ('İmsak', vakit.imsak),
      ('Güneş', vakit.gunes),
      ('Öğle', vakit.ogle),
      ('İkindi', vakit.ikindi),
      ('Akşam', vakit.aksam),
      ('Yatsı', vakit.yatsi),
    ];

String _formatRemaining(Duration d) {
  if (d.isNegative) return '00:00:00';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
}

class _LivePrayerCountdown extends StatefulWidget {
  final List<Vakit> list;

  const _LivePrayerCountdown({required this.list});

  @override
  State<_LivePrayerCountdown> createState() => _LivePrayerCountdownState();
}

class _LivePrayerCountdownState extends State<_LivePrayerCountdown> {
  late DateTime _now;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _now = phoneLocalNow();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = phoneLocalNow());
      }
    });
  }

  @override
  void didUpdateWidget(covariant _LivePrayerCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.list != widget.list) {
      _now = phoneLocalNow();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = findVakitForDate(widget.list, _now);
    if (today == null) return const Text('Bugün için namaz vakti verisi bulunamadı.');

    final tomorrow = findVakitForDate(widget.list, _now.add(const Duration(days: 1)));
    final next = nextPrayerInfo(today, _now, tomorrow: tomorrow);

    return Column(
      children: [
        Text('${next.name} Vaktine', style: Theme.of(context).textTheme.bodyMedium),
        SizedBox(
          width: double.infinity,
          height: 42,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _formatRemaining(next.time.difference(_now)),
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Image.network(
          today.ayinSekliURL,
          height: 44,
          errorBuilder: (_, __, ___) => const Icon(Icons.brightness_3, size: 40),
        ),
      ],
    );
  }
}

/// Telefon yatay (landscape) modunda kompakt Ana Sayfa: slayt + vakit
/// şeridi ortada, sağda dar bir panel (tarih/hicri + geri sayım + namaz
/// vakitleri). Hiçbir ayar butonu göstermez.
class _LandscapeCompactLayout extends ConsumerWidget {
  final String? ilceId;
  final String? ilceAdi;
  final DateTime date;

  const _LandscapeCompactLayout({required this.ilceId, required this.ilceAdi, required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: const SlaytWidget(height: double.infinity, userImages: []),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: ilceId == null
                      ? const _NoLocationPanel()
                      : SingleChildScrollView(
                          child: _SidePanel(
                            ilceId: ilceId!,
                            ilceAdi: ilceAdi!,
                            date: date,
                            showTimes: false,
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (ilceId != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 58),
              child: _LandscapePrayerTimesStrip(ilceId: ilceId!, date: date),
            ),
          ],
        ],
      ),
    );
  }
}

class _LandscapePrayerTimesStrip extends ConsumerWidget {
  final String ilceId;
  final DateTime date;

  const _LandscapePrayerTimesStrip({required this.ilceId, required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTimes = ref.watch(timesProvider(ilceId));

    return asyncTimes.when(
      loading: () => const SizedBox(height: 42, child: Center(child: LinearProgressIndicator())),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        final vakit = findVakitForDate(list, date);
        if (vakit == null) return const SizedBox.shrink();

        final now = phoneLocalNow();
        final activeName = currentPrayerName(vakit, now);

        return SizedBox(
          height: 42,
          child: Row(
            children: prayerTimeEntries(vakit).map((entry) {
              final isActive = entry.$1 == activeName;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: isActive ? dashboardAccentGreen.withValues(alpha: 0.18) : Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isActive ? dashboardAccentGold : Colors.black12),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entry.$1,
                          style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.w500),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          entry.$2,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
