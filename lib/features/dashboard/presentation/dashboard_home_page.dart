import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/live_clock.dart';
import '../../../core/responsive.dart';
import '../../../theme.dart';
import '../../locations/data/models.dart';
import '../../media/player/compact_play_controls.dart';
import '../../settings/data/prefs_repository.dart';
import '../../times/presentation/slayt_widget.dart';
import '../../times/presentation/time_utils.dart';
import '../../times/presentation/times_page.dart' show timesProvider;
import 'date_format.dart';
import 'location_flow.dart';

/// The home screen always shows today's live schedule, independently of the
/// date being browsed on the separate prayer-times / daily-content pages.
class DashboardHomePage extends ConsumerWidget {
  const DashboardHomePage({super.key, this.location});
  final SavedLocation? location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
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
      color: dashboardBg(brightness),
      child: LayoutBuilder(builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        final gap = (constraints.maxWidth * .012).clamp(10.0, 24.0);
        final phone = isPhoneSize(Size(constraints.maxWidth, constraints.maxHeight));
        // A landscape *phone* (short in height, e.g. a rotated 844x390) is
        // still `phone` (shortestSide-based, so width alone never
        // misclassifies it as a tablet) but is cramped very differently
        // from a landscape tablet/desktop — its right-hand info column gets
        // far less height, so its cards need denser chrome to render their
        // text at a readable size instead of being shrunk hard by FittedBox.
        final phoneLandscape = phone && landscape;
        // A phone-shaped portrait window gets the phone stack even when the
        // browser reports a wide viewport (Chrome's "desktop site" mode or
        // page zoom report ~980px on a phone). Tablets are 1.33-1.6 tall.
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final narrowPortrait = !landscape && (phone || h / w >= 1.75);
        // Phone-stack sizes are tuned for ~400px; wider phone-shaped
        // viewports scale them up instead of leaving tiny text.
        final scale = narrowPortrait ? (w / 400).clamp(1.0, 2.6) : 1.0;
        final stripHeightBase = (constraints.maxHeight * .155).clamp(76.0, 154.0);
        final stripHeight = phoneLandscape ? stripHeightBase * 0.68 : stripHeightBase;
        final city = _CityCard(location: selected, today: today, now: now, tight: phone);
        final countdown = _CountdownCard(today: today, next: next, now: now, unavailable: unavailable, tight: phone,
            needsLocation: selected == null,
            maxAspect: phone && !landscape ? 1.45 : 1.15);
        // Portrait phones are narrow enough that a single 6-column row
        // crushes each prayer name/time; split into a 3x2 grid there. A
        // landscape phone already has enough width for one row, but still
        // gets denser cell padding since it has less height to spend.
        final strip = PrayerTimeStrip(today: today, now: now,
            compact: narrowPortrait, dense: phoneLandscape);
        final menuButton = _HomeMenuButton(compact: phoneLandscape, scale: scale);
        final slide = ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SlaytWidget(
            key: const ValueKey('home-slideshow'),
            height: 0,
            showFullscreenButton: false,
            backgroundColor: brightness == Brightness.dark
                ? dashboardSidebarDark
                : const Color(0xFFE3E1DA),
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
                menuButton,
              ])),
            ]),
          );
        }
        // Portrait fills the viewport instead of scrolling a stack of fixed
        // heights: the countdown, the reason people open the app, comes right
        // after the place header and gets the biggest share; the slideshow
        // takes what is left. A tablet uses its width to put the city card
        // and the countdown side by side instead of stretching the phone stack.
        Widget hero({required double aspect}) => _CountdownCard(today: today, next: next,
            now: now, unavailable: unavailable, tight: narrowPortrait, needsLocation: selected == null,
            maxAspect: aspect, showLabel: false, digitEmphasis: narrowPortrait ? .95 : null);
        if (narrowPortrait) {
          final header = _PortraitHeader(location: selected, today: today, now: now, scale: scale);
          final stripH = (h * .17).clamp(118.0 * scale, 160.0 * scale);
          // Short windows (split screen, small phones) keep the same order
          // but scroll, so nothing is squeezed below a readable size.
          if (h < 600 * scale) {
            return ListView(padding: EdgeInsets.all(gap), children: [
              header,
              SizedBox(height: gap),
              SizedBox(height: 230 * scale, child: hero(aspect: 2.4)),
              SizedBox(height: gap),
              SizedBox(height: stripH, child: strip),
              SizedBox(height: gap),
              SizedBox(height: w * .62, child: slide),
              SizedBox(height: gap),
              menuButton,
            ]);
          }
          return Padding(
            padding: EdgeInsets.all(gap),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              header,
              SizedBox(height: gap),
              Expanded(flex: 52, child: hero(aspect: 2.4)),
              SizedBox(height: gap),
              SizedBox(height: stripH, child: strip),
              SizedBox(height: gap),
              Expanded(flex: 48, child: slide),
              SizedBox(height: gap),
              menuButton,
            ]),
          );
        }
        return Padding(
          padding: EdgeInsets.all(gap),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // The slideshow letterboxes its photos, so it only gets the height
            // a landscape photo needs; everything else goes to the top row.
            Expanded(child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(flex: 2, child: city),
                SizedBox(width: gap),
                Expanded(flex: 3, child: hero(aspect: 1.7)),
              ])),
            SizedBox(height: gap),
            SizedBox(height: (h * .095).clamp(92.0, 130.0), child: strip),
            SizedBox(height: gap),
            SizedBox(height: math.min(w * .62, h * .42), child: slide),
            SizedBox(height: gap),
            menuButton,
          ]),
        );
      }),
    );
  }
}

class _CityCard extends ConsumerWidget {
  const _CityCard({required this.location, required this.today, required this.now, this.tight = false});
  final SavedLocation? location;
  final Vakit? today;
  final DateTime now;

  /// Landscape phones give this card far less height than the flex share
  /// assumes. The FittedBox that wraps this card's content only *shrinks*
  /// to fit — it never gives extra room — so the way to make the rendered
  /// text bigger for the same available height is to shrink the unused
  /// spacing between elements, not the text itself, closing the gap
  /// between the content's natural height and what's actually available.
  final bool tight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
    final ink = dashboardInk(brightness);
    final muted = dashboardMuted(brightness);
    return _Surface(
      key: const ValueKey('home-city-card'),
      onTap: location == null ? null : () => showLocationSheet(context, ref),
      semanticLabel: 'Konumu değiştir',
      color: dashboardSurfaceCream(brightness),
      child: LayoutBuilder(builder: (context, c) {
        final cityName = location?.ilce.ilceAdi ?? 'Konum seçilmedi';

        if (tight) {
          // A landscape phone gives this card only ~50-70 logical px of
          // content height (see debug measurement in test/responsive_layout_test.dart)
          // — far too little for the tablet/desktop formula below, whose
          // *nominal* (pre-shrink) sizes only work because that formula
          // relies on the outer FittedBox to scale everything down by a
          // large, unpredictable factor. That approach also breaks when any
          // one line wraps (its unscaled multi-line height inflates the
          // whole column and shrinks every *other* line along with it) —
          // exactly what made city/date text unreadably tiny here before.
          // So this branch sets fixed, already-readable font sizes
          // directly (city 20, date/hicri 15 — within the 18-22 / 14-16
          // targets) with no icon and minimal gaps, and treats the outer
          // FittedBox purely as a last-resort safety net for the rare
          // 2-line city name.
          return Center(child: FittedBox(fit: BoxFit.scaleDown,
            child: SizedBox(width: c.maxWidth, child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(cityName, textAlign: TextAlign.center, maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ink, fontSize: 20,
                        height: 1.05, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text('${gunAdlari[now.weekday - 1]}, ${now.day} ${ayAdlari[now.month - 1]} ${now.year}',
                    textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(today?.hicriTarihUzun.isNotEmpty == true ? today!.hicriTarihUzun
                    : 'Hicri tarih bekleniyor', textAlign: TextAlign.center,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 15, fontWeight: FontWeight.w500)),
              ],
            )),
          ));
        }

        final size = (c.maxWidth * .125).clamp(isPhoneContext(context) ? 33.0 : 22.0, 44.0);
        return Center(child: FittedBox(fit: BoxFit.scaleDown,
          child: SizedBox(width: c.maxWidth, child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.location_on_rounded, color: dashboardAccentGold, size: size * .9),
              SizedBox(width: size * .15),
              Flexible(child: Text(cityName, textAlign: TextAlign.center, maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: ink, fontSize: size,
                      height: 1.1, fontWeight: FontWeight.w800))),
              if (location != null)
                Icon(Icons.expand_more_rounded, color: muted, size: size * .8),
            ]),
            SizedBox(height: size * .32),
            Text('${gunAdlari[now.weekday - 1]}, ${now.day} ${ayAdlari[now.month - 1]} ${now.year}',
                textAlign: TextAlign.center, style: TextStyle(color: muted,
                    fontSize: size * .56, fontWeight: FontWeight.w600)),
            SizedBox(height: size * .36),
            Container(
              padding: EdgeInsets.symmetric(horizontal: size * .42, vertical: size * .16),
              decoration: BoxDecoration(color: dashboardActiveCell(brightness),
                  borderRadius: BorderRadius.circular(size)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.nightlight_round, color: dashboardAccentGold, size: size * .52),
                SizedBox(width: size * .2),
                Flexible(child: Text(today?.hicriTarihUzun.isNotEmpty == true ? today!.hicriTarihUzun
                    : 'Hicri tarih bekleniyor', textAlign: TextAlign.center,
                    style: TextStyle(color: ink, fontSize: size * .52,
                        fontWeight: FontWeight.w600))),
              ]),
            ),
          ])),
        ));
      }),
    );
  }
}

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({required this.today, required this.next, required this.now, required this.unavailable, this.tight = false, this.maxAspect = 1.15, this.needsLocation = false, this.showLabel = true, this.digitEmphasis});

  /// Digit share of the card height; defaults to 1.25 when [tight].
  final double? digitEmphasis;

  /// The "KALAN SÜRE" label; portrait drops it so the title leads.
  final bool showLabel;

  /// Henüz konum seçilmediyse boş sayaç yerine konum seçme düğmeleri gösterilir.
  final bool needsLocation;

  /// Widest content width relative to the card's height. The digits fill this
  /// width, so a higher value enlarges them in a short, wide card.
  final double maxAspect;
  final Vakit? today;
  final ({String name, DateTime time})? next;
  final DateTime now;
  final String unavailable;

  /// Landscape phones give this card much less height than the 300px
  /// layout budget below assumes, so the enclosing FittedBox has to shrink
  /// everything hard to fit. Lowering that budget (and the spacer flex
  /// that pads it out) for a landscape phone closes most of that gap,
  /// making the actually-rendered digits/title noticeably bigger without
  /// touching their font-size formulas at all.
  final bool tight;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    const highlight = Color(0xFFE9C981);
    const soft = Color(0xD9FFFFFF);
    return _Surface(
      key: const ValueKey('home-countdown'),
      color: brightness == Brightness.dark ? dashboardCardGreenDark : dashboardAccentGreen,
      borderColor: dashboardAccentGold.withValues(alpha: .45),
      child: LayoutBuilder(builder: (context, bounds) {
        final c = BoxConstraints.tightFor(
          width: math.min(bounds.maxWidth, bounds.maxHeight * maxAspect),
          height: math.max(bounds.maxHeight, tight ? 200.0 : 300.0),
        );
        final titleSize = needsLocation ? (c.maxWidth * .06).clamp(16.0, 24.0)
            : (c.maxWidth * (tight ? .12 : .1)).clamp(18.0, 42.0);
        final labelSize = (c.maxWidth * .06).clamp(isPhoneContext(context) ? 14.0 : 12.5, 20.0);
        final clockSize = (c.maxWidth * .085).clamp(18.0, 34.0);
        final remaining = next?.time.difference(now);
        final value = remaining == null ? '--:--:--' : _formatRemaining(remaining);
        final previous = today == null ? null : _previousPrayer(today!, now);
        final progress = next == null || previous == null ? null
            : _elapsedFraction(previous.time, next!.time, now);
        return Center(child: FittedBox(fit: BoxFit.scaleDown,
          child: SizedBox(width: c.maxWidth, height: c.maxHeight,
            child: Column(children: [
          const Spacer(),
          // Wrapped in Flexible+FittedBox (like the countdown digits already
          // are) so a large system text-scale setting shrinks these lines
          // locally instead of overflowing this fixed-aspect card — the
          // enclosing FittedBox only rescales the *whole* column when its
          // natural size is too big, it can't stop this inner Column (which
          // has a real, tight height) from overflowing on its own.
          if (showLabel) ...[
            Flexible(child: FittedBox(fit: BoxFit.scaleDown,
              child: Text('KALAN SÜRE', style: TextStyle(color: highlight,
                  letterSpacing: 2.5, fontSize: labelSize, fontWeight: FontWeight.w700)))),
            SizedBox(height: (c.maxHeight * .02).clamp(3.0, 12.0)),
          ],
          Flexible(child: FittedBox(fit: BoxFit.scaleDown,
            child: Text(next == null ? unavailable : next!.name == 'Güneş'
                ? 'Güneşin Doğmasına' : '${next!.name} Vaktine',
                key: const ValueKey('countdown-target'), textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: titleSize,
                    height: 1.15, fontWeight: FontWeight.w700)))),
          SizedBox(height: (c.maxHeight * .03).clamp(4.0, 20.0)),
          if (needsLocation)
            _LocationPrompt(width: c.maxWidth, tight: tight)
          else
            StableCountdownDigits(value: value, emphasis: digitEmphasis ?? (tight ? 1.25 : 1.0),
                color: Colors.white, separatorColor: highlight),
          if (progress != null) ...[
            SizedBox(height: (c.maxHeight * .03).clamp(4.0, 20.0)),
            ClipRRect(borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                key: const ValueKey('countdown-progress'), value: progress,
                minHeight: (c.maxHeight * .02).clamp(4.0, 8.0),
                color: highlight, backgroundColor: const Color(0x33FFFFFF))),
            if (!tight) ...[
              const SizedBox(height: 8),
              Flexible(child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Flexible(child: FittedBox(fit: BoxFit.scaleDown,
                  child: Text('${previous!.name} ${_clock(previous.time)}',
                      style: TextStyle(color: soft, fontSize: labelSize,
                          fontWeight: FontWeight.w500)))),
                const SizedBox(width: 8),
                Flexible(child: FittedBox(fit: BoxFit.scaleDown,
                  child: Text('${next!.name} ${_clock(next!.time)}',
                      style: TextStyle(color: Colors.white, fontSize: labelSize,
                          fontWeight: FontWeight.w700)))),
              ])),
            ],
          ],
          const Spacer(),
          Container(height: 1, color: const Color(0x33FFFFFF)),
          SizedBox(height: tight ? 4 : 10),
          Flexible(child: FittedBox(fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.schedule_rounded, color: highlight, size: clockSize),
              const SizedBox(width: 8),
              Text('${_clock(now)}:${_two(now.second)}',
                  key: const ValueKey('home-live-clock'),
                  style: TextStyle(color: Colors.white, fontSize: clockSize,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w600)),
            ]))),
          SizedBox(height: tight ? 2 : 6),
        ]))));
      }),
    );
  }
}

/// The boundary the countdown's progress bar starts from. Before imsak that is
/// last night's yatsı, approximated from today's time.
({String name, DateTime time}) _previousPrayer(Vakit today, DateTime now) {
  DateTime at(String text) {
    final parts = text.split(':');
    return DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
  }

  ({String name, DateTime time})? previous;
  for (final (name, time) in prayerTimeEntries(today)) {
    final value = at(time);
    if (!value.isAfter(now)) previous = (name: name, time: value);
  }
  return previous ?? (name: 'Yatsı', time: at(today.yatsi).subtract(const Duration(days: 1)));
}

double _elapsedFraction(DateTime from, DateTime to, DateTime now) {
  final total = to.difference(from).inSeconds;
  if (total <= 0) return 0;
  return (now.difference(from).inSeconds / total).clamp(0.0, 1.0);
}

/// Each digit owns an equal, fixed slot. Font fallback and proportional glyphs
/// cannot move the neighbouring digits when a second changes.
class StableCountdownDigits extends StatelessWidget {
  const StableCountdownDigits({super.key, required this.value, this.emphasis = 1.0,
      this.color, this.separatorColor});
  final String value;

  /// Defaults to the dashboard ink color.
  final Color? color;

  /// Color of the ':' separators; defaults to [color].
  final Color? separatorColor;

  /// >1 makes the digits claim a bigger share of this card's natural height
  /// relative to the icon/title/label/clock around them — since the whole
  /// card is later rescaled together by one FittedBox, this shifts the
  /// balance toward more prominent digits rather than just scaling
  /// everything uniformly.
  final double emphasis;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? dashboardInk(Theme.of(context).brightness);
    final separator = separatorColor ?? ink;
    return Semantics(label: value, child: ExcludeSemantics(
      child: LayoutBuilder(builder: (context, c) {
        final fontSize = c.maxWidth / 4.8 * emphasis;
        return SizedBox(height: fontSize * 1.3, child: Row(
          key: const ValueKey('countdown-digits'),
          children: List.generate(value.length, (i) => Expanded(
            flex: value[i] == ':' ? 5 : 10,
            child: Center(child: FittedBox(fit: BoxFit.scaleDown,
              child: Text(value[i], key: ValueKey('countdown-digit-$i'),
                style: TextStyle(color: value[i] == ':' ? separator : ink, fontSize: fontSize,
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
  const PrayerTimeStrip({super.key, required this.today, required this.now,
      this.compact = false, this.dense = false});
  final Vakit? today;
  final DateTime now;

  /// When true, lays the six prayer times out as a 3x2 grid instead of a
  /// single row of 6 — a narrow phone can't give a 6-column row enough
  /// per-cell width to keep names/times readable.
  final bool compact;

  /// Shrinks each cell's own padding (~20%) for a landscape phone, which
  /// gives this strip noticeably less height than a landscape tablet/
  /// desktop gets from the same `stripHeight` fraction of screen height.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final ink = dashboardInk(brightness);
    final phoneFloor = isPhoneContext(context);
    final active = today == null ? null : currentPrayerName(today!, now);
    final entries = today == null
        ? [for (final name in ['İmsak', 'Güneş', 'Öğle', 'İkindi', 'Akşam', 'Yatsı']) (name, '--:--')]
        : prayerTimeEntries(today!);
    return LayoutBuilder(builder: (context, c) {
      final columns = compact ? 3 : entries.length;
      final hGap = (c.maxWidth * (compact ? .025 : .009)).clamp(4.0, 14.0);
      final cellWidth = (c.maxWidth - hGap * (columns - 1)) / columns;
      final nameSize = compact
          ? (cellWidth / 7.4).clamp(14.0, 34.0)
          : (c.maxWidth / 44).clamp(phoneFloor ? 14.0 : 12.0, 31.0);
      final timeSize = compact
          ? (cellWidth / 4.6).clamp(18.0, 52.0)
          : (c.maxWidth / 30).clamp(phoneFloor ? 18.0 : 17.0, 46.0);

      Widget cell(int i) => Semantics(selected: entries[i].$1 == active,
        child: Container(
          key: ValueKey('prayer-cell-${entries[i].$1}'),
          decoration: BoxDecoration(
            color: entries[i].$1 == active
                ? dashboardActiveCell(brightness)
                : dashboardSurfaceWhite(brightness),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: entries[i].$1 == active ? dashboardAccentGold
                : dashboardBorder(brightness), width: entries[i].$1 == active ? 3 : 1),
          ),
          padding: EdgeInsets.symmetric(horizontal: 5,
              vertical: (compact ? 6 : 8) * (dense ? 0.65 : 1.0)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(child: FittedBox(fit: BoxFit.scaleDown,
              child: Text(entries[i].$1, style: TextStyle(color: ink,
                  fontSize: nameSize, fontWeight: entries[i].$1 == active
                      ? FontWeight.w800 : FontWeight.w500)))),
            SizedBox(height: (compact ? 3 : 5) * (dense ? 0.65 : 1.0)),
            Flexible(child: FittedBox(fit: BoxFit.scaleDown,
              child: Text(entries[i].$2, style: TextStyle(color: ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontSize: timeSize, height: 1.15, fontWeight: FontWeight.w800)))),
          ]),
        ),
      );

      if (!compact) {
        return Row(key: const ValueKey('home-prayer-strip'), children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) SizedBox(width: hGap),
            Expanded(child: cell(i)),
          ],
        ]);
      }

      final rows = (entries.length / columns).ceil();
      final vGap = (c.maxHeight * .06).clamp(4.0, 12.0);
      return Column(key: const ValueKey('home-prayer-strip'),
        mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) SizedBox(height: vGap),
          Expanded(child: Row(children: [
            for (var col = 0; col < columns; col++) ...[
              if (col > 0) SizedBox(width: hGap),
              Expanded(child: r * columns + col < entries.length
                  ? cell(r * columns + col) : const SizedBox.shrink()),
            ],
          ])),
        ],
      ]);
    });
  }
}

class _Surface extends StatelessWidget {
  const _Surface({super.key, required this.color, this.borderColor, required this.child,
      this.onTap, this.semanticLabel, this.padding});
  final Color color;
  final Color? borderColor;
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Overrides the width-proportional padding.
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
    final radius = BorderRadius.circular(18);
    final body = Padding(
      padding: padding ?? EdgeInsets.all((c.maxWidth * .055).clamp(12.0, 26.0)),
      child: child,
    );
    return Container(
      decoration: BoxDecoration(color: color, borderRadius: radius,
        border: Border.all(color: borderColor ?? dashboardBorder(Theme.of(context).brightness)),
        boxShadow: const [BoxShadow(color: Color(0x09000000), blurRadius: 16, offset: Offset(0, 4))]),
      child: onTap == null ? body : Semantics(button: true, label: semanticLabel,
        child: Material(type: MaterialType.transparency, borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, borderRadius: radius, child: body))),
    );
  });
}

/// Dikey telefonda üstteki ince başlık: şehir (dokununca konum seçenekleri)
/// ve tek satırda miladi + hicri tarih.
class _PortraitHeader extends ConsumerWidget {
  const _PortraitHeader({required this.location, required this.today, required this.now,
      this.scale = 1});
  final SavedLocation? location;
  final Vakit? today;
  final DateTime now;

  /// 1 at ~400px wide; larger on wide phone-shaped viewports.
  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = Theme.of(context).brightness;
    final ink = dashboardInk(b);
    final muted = dashboardMuted(b);
    final hicri = today?.hicriTarihUzun.isNotEmpty == true ? today!.hicriTarihUzun : null;
    // Dar telefonlarda gün adı düşer ki hicri tarih kesilmeden sığsın.
    final narrow = MediaQuery.sizeOf(context).width / scale < 440;
    final day = '${now.day} ${ayAdlari[now.month - 1]} ${now.year}';
    final date = narrow ? day : '${gunAdlari[now.weekday - 1]}, $day';
    return _Surface(
      key: const ValueKey('home-city-card'),
      color: dashboardSurfaceCream(b),
      onTap: location == null ? null : () => showLocationSheet(context, ref),
      semanticLabel: 'Konumu değiştir',
      padding: EdgeInsets.fromLTRB(10 * scale, 12 * scale, 10 * scale, 12 * scale),
      child: Row(children: [
        // Sağdaki düğme kadar boşluk: şehir adı kartın tam ortasında durur.
        if (location != null) SizedBox(width: 46 * scale),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min, children: [
          Text(location?.ilce.ilceAdi ?? 'Konum seçilmedi', maxLines: 1,
              textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink, fontSize: 22 * scale, height: 1.15,
                  fontWeight: FontWeight.w800)),
          SizedBox(height: 2 * scale),
          Text(hicri == null ? date : '$date  ·  $hicri', maxLines: 1,
              textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted, fontSize: 14 * scale, fontWeight: FontWeight.w600)),
        ])),
        if (location != null) ...[
          SizedBox(width: 6 * scale),
          Container(
            width: 40 * scale, height: 40 * scale,
            decoration: BoxDecoration(color: dashboardActiveCell(b), shape: BoxShape.circle),
            child: Icon(Icons.edit_location_alt_outlined, color: ink, size: 22 * scale),
          ),
        ],
      ]),
    );
  }
}

class _HomeMenuButton extends StatelessWidget {
  const _HomeMenuButton({this.compact = false, this.scale = 1});

  /// Grows the bar on wide phone-shaped viewports (see the home layout).
  final double scale;

  /// A landscape phone's info column is too narrow to fit the play
  /// controls (when a track is loaded) next to a full "Menü" label without
  /// squeezing the button down to almost nothing. Shrinking the button to
  /// a plain icon — instead of stretching it via Expanded — lets both sit
  /// side by side at their own natural size, with the extra width (if any)
  /// left as plain background instead of forcing an ever-thinner label.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final button = compact
        ? FilledButton(
            key: const ValueKey('home-menu-button'),
            onPressed: () => Scaffold.of(context).openDrawer(),
            style: FilledButton.styleFrom(
              backgroundColor: dashboardAccentGreen,
              // Same rounded-rectangle shape as the prayer-time boxes
              // (radius 14), not a circle, so it reads as part of the same
              // family of controls.
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: EdgeInsets.zero,
              minimumSize: const Size(52, 48),
            ),
            child: const Icon(Icons.menu_rounded, color: Color(0xFFE9C981)),
          )
        : FilledButton.icon(
            key: const ValueKey('home-menu-button'),
            onPressed: () => Scaffold.of(context).openDrawer(),
            style: FilledButton.styleFrom(backgroundColor: dashboardAccentGreen, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: TextStyle(fontSize: 19 * scale, fontWeight: FontWeight.w600)),
            icon: Icon(Icons.menu_rounded, color: const Color(0xFFE9C981), size: 24 * scale),
            label: const Text('Menü'),
          );
    return SizedBox(
      height: 54 * scale,
      child: Row(children: [
        CompactPlayControls(compact: compact),
        const SizedBox(width: 8),
        if (compact) button else Expanded(child: button),
      ]),
    );
  }
}

List<(String, String)> prayerTimeEntries(Vakit vakit) => [
  ('İmsak', vakit.imsak), ('Güneş', vakit.gunes), ('Öğle', vakit.ogle),
  ('İkindi', vakit.ikindi), ('Akşam', vakit.aksam), ('Yatsı', vakit.yatsi),
];
String _two(int n) => n.toString().padLeft(2, '0');
String _clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
String _formatRemaining(Duration d) => d.isNegative ? '00:00:00'
    : '${_two(d.inHours)}:${_two(d.inMinutes.remainder(60))}:${_two(d.inSeconds.remainder(60))}';


/// Konum yokken geri sayım kartındaki tek düğme. Otomatik bulma, elle seçme
/// ve son konumlar açılan pencerede.
class _LocationPrompt extends ConsumerWidget {
  const _LocationPrompt({required this.width, required this.tight});
  final double width;
  final bool tight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const gold = Color(0xFFE9C981);
    final fontSize = (width * .05).clamp(16.0, 20.0);
    return SizedBox(
      width: width * .82,
      child: FilledButton.icon(
        key: const ValueKey('home-set-location'),
        style: FilledButton.styleFrom(
          backgroundColor: gold, foregroundColor: dashboardAccentGreen,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: tight ? 14 : 18),
          textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: () => showLocationSheet(context, ref),
        icon: Icon(Icons.my_location_rounded, size: fontSize + 4),
        label: const Text('Konumunu belirle'),
      ),
    );
  }
}
