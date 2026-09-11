import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/live_clock.dart';
import '../../locations/data/models.dart';
import '../../locations/presentation/country_page.dart';
import '../../media/player/compact_play_controls.dart';
import '../../settings/data/prefs_repository.dart';
import '../../times/presentation/slayt_widget.dart';
import '../../times/presentation/time_utils.dart';
import '../../times/presentation/times_page.dart' show timesProvider;
import 'date_format.dart';

const calendarBackground = Color(0xFFEEEFEF);
const calendarCream = Color(0xFFF7F0E1);
const calendarGold = Color(0xFFB38B42);
const calendarInk = Color(0xFF242B30);
const _muted = Color(0xFF62635E);

/// The home screen always shows today's live schedule, independently of the
/// date being browsed on the separate prayer-times / daily-content pages.
class DashboardHomePage extends ConsumerWidget {
  const DashboardHomePage({super.key, this.location});
  final SavedLocation? location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(liveClockProvider);
    final recent = ref.watch(prefsRepositoryProvider).getRecentLocations();
    final selected = location ?? (recent.isEmpty ? null : recent.first);
    final result = selected == null ? null : ref.watch(timesProvider(selected.ilce.ilceId));
    final list = result?.valueOrNull;
    final today = list == null ? null : findVakitForDate(list, now);
    final tomorrow = list == null ? null : findVakitForDate(list,
        DateTime(now.year, now.month, now.day + 1));
    final next = today == null ? null : nextPrayerInfo(today, now, tomorrow: tomorrow);
    final unavailable = selected == null ? 'Vakitler için şehir seçin'
        : result?.hasError == true ? 'Vakitler alınamadı. Yeniden denenecek.'
        : 'Güncel vakitler yükleniyor';

    return ColoredBox(
      color: calendarBackground,
      child: LayoutBuilder(builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        final gap = (constraints.maxWidth * .012).clamp(10.0, 24.0);
        final stripHeight = (constraints.maxHeight * .155).clamp(76.0, 154.0);
        final city = _CityCard(location: selected, today: today, now: now);
        final countdown = _CountdownCard(next: next, now: now, unavailable: unavailable);
        final strip = PrayerTimeStrip(today: today, now: now);
        final slide = ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: const SlaytWidget(
            key: ValueKey('home-slideshow'),
            height: 0,
            showFullscreenButton: false,
            backgroundColor: Color(0xFFE3E1DA),
          ),
        );
        if (landscape) {
          return Padding(
            padding: EdgeInsets.all(gap),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 3, child: Column(children: [
                Expanded(child: slide),
                SizedBox(height: gap),
                SizedBox(height: stripHeight, child: strip),
              ])),
              SizedBox(width: gap),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(flex: 34, child: city),
                SizedBox(height: gap),
                Expanded(flex: 66, child: countdown),
                SizedBox(height: gap),
                const _HomeMenuButton(),
              ])),
            ]),
          );
        }
        // Phone/portrait fallback keeps the same content and drawer access.
        return ListView(padding: EdgeInsets.all(gap), children: [
          SizedBox(height: 215, child: city),
          SizedBox(height: gap),
          SizedBox(height: constraints.maxWidth * .72, child: slide),
          SizedBox(height: gap),
          SizedBox(height: 88, child: strip),
          SizedBox(height: gap),
          SizedBox(height: 270, child: countdown),
          SizedBox(height: gap),
          const _HomeMenuButton(),
        ]);
      }),
    );
  }
}

class _CityCard extends StatelessWidget {
  const _CityCard({required this.location, required this.today, required this.now});
  final SavedLocation? location;
  final Vakit? today;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      key: const ValueKey('home-city-card'),
      color: calendarCream,
      child: LayoutBuilder(builder: (context, c) {
        final size = (c.maxWidth * .095).clamp(18.0, 44.0);
        return Center(child: FittedBox(fit: BoxFit.scaleDown,
          child: SizedBox(width: c.maxWidth, child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.mosque_outlined, color: calendarGold, size: size * 1.05),
            const SizedBox(height: 8),
            Text('NURANÎ TAKVİM', style: TextStyle(color: _muted,
                fontSize: size * .43, letterSpacing: 2.0, fontWeight: FontWeight.w700)),
            SizedBox(height: size * .45),
            Text(location?.ilce.ilceAdi ?? 'Şehir seçin', textAlign: TextAlign.center,
                style: TextStyle(color: calendarInk, fontSize: size,
                    height: 1.1, fontWeight: FontWeight.w800)),
            SizedBox(height: size * .4),
            Text('${now.day} ${ayAdlari[now.month - 1]} ${now.year}',
                textAlign: TextAlign.center, style: TextStyle(color: calendarInk,
                    fontSize: size * .65, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(gunAdlari[now.weekday - 1], style: TextStyle(
                color: _muted, fontSize: size * .57)),
            SizedBox(height: size * .35),
            Container(width: 44, height: 2, color: calendarGold),
            SizedBox(height: size * .35),
            Text(today?.hicriTarihUzun.isNotEmpty == true ? today!.hicriTarihUzun
                : 'Hicri tarih bekleniyor', textAlign: TextAlign.center,
                style: TextStyle(color: calendarInk, fontSize: size * .57,
                    fontWeight: FontWeight.w500)),
            if (location == null) TextButton(onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CountryPage())),
                child: const Text('Konum seç')),
          ])),
        ));
      }),
    );
  }
}

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({required this.next, required this.now, required this.unavailable});
  final ({String name, DateTime time})? next;
  final DateTime now;
  final String unavailable;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      key: const ValueKey('home-countdown'),
      color: Colors.white,
      child: LayoutBuilder(builder: (context, bounds) {
        final c = BoxConstraints.tightFor(
          width: math.min(bounds.maxWidth, bounds.maxHeight * 1.15),
          height: math.max(bounds.maxHeight, 300),
        );
        final titleSize = (c.maxWidth * .095).clamp(18.0, 42.0);
        final clockSize = (c.maxWidth * .09).clamp(18.0, 36.0);
        final remaining = next?.time.difference(now);
        final value = remaining == null ? '--:--:--' : _formatRemaining(remaining);
        return Center(child: FittedBox(fit: BoxFit.scaleDown,
          child: SizedBox(width: c.maxWidth, height: c.maxHeight,
            child: Column(children: [
          const Spacer(flex: 2),
          Icon(Icons.schedule_rounded, color: calendarGold,
              size: (c.maxHeight * .11).clamp(26.0, 58.0)),
          const Spacer(),
          Text(next == null ? unavailable : next!.name == 'Güneş'
              ? 'Güneşin Doğmasına' : '${next!.name} Vaktine',
              key: const ValueKey('countdown-target'), textAlign: TextAlign.center,
              style: TextStyle(color: calendarInk, fontSize: titleSize,
                  height: 1.15, fontWeight: FontWeight.w700)),
          SizedBox(height: (c.maxHeight * .035).clamp(6.0, 24.0)),
          StableCountdownDigits(value: value),
          const SizedBox(height: 8),
          Text('KALAN SÜRE', style: TextStyle(color: _muted,
              letterSpacing: 2, fontSize: (c.maxWidth * .044).clamp(10.0, 18.0),
              fontWeight: FontWeight.w600)),
          const Spacer(flex: 2),
          Container(height: 1, color: const Color(0xFFE7E4DC)),
          const Spacer(),
          Text('${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}',
              key: const ValueKey('home-live-clock'),
              style: TextStyle(color: _muted, fontSize: clockSize,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w500)),
          const Spacer(),
        ]))));
      }),
    );
  }
}

/// Each digit owns an equal, fixed slot. Font fallback and proportional glyphs
/// cannot move the neighbouring digits when a second changes.
class StableCountdownDigits extends StatelessWidget {
  const StableCountdownDigits({super.key, required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    return Semantics(label: value, child: ExcludeSemantics(
      child: LayoutBuilder(builder: (context, c) {
        final fontSize = c.maxWidth / 4.8;
        return SizedBox(height: fontSize * 1.3, child: Row(
          key: const ValueKey('countdown-digits'),
          children: List.generate(value.length, (i) => Expanded(
            flex: value[i] == ':' ? 5 : 10,
            child: Center(child: FittedBox(fit: BoxFit.scaleDown,
              child: Text(value[i], key: ValueKey('countdown-digit-$i'),
                style: TextStyle(color: calendarInk, fontSize: fontSize,
                    fontFamily: 'monospace', fontFeatures: const [FontFeature.tabularFigures()],
                    height: 1.05, fontWeight: FontWeight.w900)),
            )),
          )),
        ));
      }),
    ));
  }
}

class PrayerTimeStrip extends StatelessWidget {
  const PrayerTimeStrip({super.key, required this.today, required this.now});
  final Vakit? today;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final active = today == null ? null : currentPrayerName(today!, now);
    final entries = today == null
        ? [for (final name in ['İmsak', 'Güneş', 'Öğle', 'İkindi', 'Akşam', 'Yatsı']) (name, '--:--')]
        : prayerTimeEntries(today!);
    return LayoutBuilder(builder: (context, c) {
      final nameSize = (c.maxWidth / 44).clamp(12.0, 31.0);
      final timeSize = (c.maxWidth / 30).clamp(17.0, 46.0);
      return Row(key: const ValueKey('home-prayer-strip'), children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) SizedBox(width: (c.maxWidth * .009).clamp(4.0, 14.0)),
          Expanded(child: Semantics(selected: entries[i].$1 == active,
            child: Container(
              key: ValueKey('prayer-cell-${entries[i].$1}'),
              decoration: BoxDecoration(
                color: entries[i].$1 == active ? const Color(0xFFF4E6C5) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: entries[i].$1 == active ? calendarGold
                    : const Color(0xFFE1E2DF), width: entries[i].$1 == active ? 3 : 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Flexible(child: FittedBox(fit: BoxFit.scaleDown,
                  child: Text(entries[i].$1, style: TextStyle(color: calendarInk,
                      fontSize: nameSize, fontWeight: entries[i].$1 == active
                          ? FontWeight.w800 : FontWeight.w500)))),
                const SizedBox(height: 5),
                Flexible(child: FittedBox(fit: BoxFit.scaleDown,
                  child: Text(entries[i].$2, style: TextStyle(color: calendarInk,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontSize: timeSize, height: 1.15, fontWeight: FontWeight.w800)))),
              ]),
            ),
          )),
        ],
      ]);
    });
  }
}

class _Surface extends StatelessWidget {
  const _Surface({super.key, required this.color, required this.child});
  final Color color;
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) => Container(
    padding: EdgeInsets.all((c.maxWidth * .055).clamp(12.0, 26.0)),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE0DDD5)),
      boxShadow: const [BoxShadow(color: Color(0x09000000), blurRadius: 16, offset: Offset(0, 4))]),
    child: child,
  ));
}

class _HomeMenuButton extends StatelessWidget {
  const _HomeMenuButton();
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    child: Row(children: [
      const CompactPlayControls(),
      const SizedBox(width: 8),
      Expanded(child: FilledButton.icon(
        key: const ValueKey('home-menu-button'),
        onPressed: () => Scaffold.of(context).openDrawer(),
        style: FilledButton.styleFrom(backgroundColor: calendarInk, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
        icon: const Icon(Icons.menu_rounded, color: Color(0xFFE9C981)),
        label: const Text('Menü'),
      )),
    ]),
  );
}

List<(String, String)> prayerTimeEntries(Vakit vakit) => [
  ('İmsak', vakit.imsak), ('Güneş', vakit.gunes), ('Öğle', vakit.ogle),
  ('İkindi', vakit.ikindi), ('Akşam', vakit.aksam), ('Yatsı', vakit.yatsi),
];
String _two(int n) => n.toString().padLeft(2, '0');
String _formatRemaining(Duration d) => d.isNegative ? '00:00:00'
    : '${_two(d.inHours)}:${_two(d.inMinutes.remainder(60))}:${_two(d.inSeconds.remainder(60))}';
