import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/live_clock.dart';
import '../../../core/responsive.dart';
import '../../../theme.dart';
import '../../locations/data/models.dart';
import '../../locations/presentation/country_page.dart';
import '../../media/player/compact_play_controls.dart';
import '../../settings/data/prefs_repository.dart';
import '../../times/presentation/slayt_widget.dart';
import '../../times/presentation/time_utils.dart';
import '../../times/presentation/times_page.dart' show timesProvider;
import 'date_format.dart';

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
        final stripHeightBase = (constraints.maxHeight * .155).clamp(76.0, 154.0);
        final stripHeight = phoneLandscape ? stripHeightBase * 0.68 : stripHeightBase;
        final city = _CityCard(location: selected, today: today, now: now, tight: phoneLandscape);
        final countdown = _CountdownCard(next: next, now: now, unavailable: unavailable, tight: phoneLandscape);
        // Portrait phones are narrow enough that a single 6-column row
        // crushes each prayer name/time; split into a 3x2 grid there. A
        // landscape phone already has enough width for one row, but still
        // gets denser cell padding since it has less height to spend.
        final strip = PrayerTimeStrip(today: today, now: now,
            compact: phone && !landscape, dense: phoneLandscape);
        final menuButton = _HomeMenuButton(compact: phoneLandscape);
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
        // Phone/portrait fallback keeps the same content and drawer access.
        // The city card gets extra height headroom on phone so its
        // phone-floor font sizes (see _CityCard) render at full size
        // instead of being shrunk back down by its FittedBox. The
        // countdown card's own width/height formula already produces large
        // digits at phone widths without needing more outer height — giving
        // it more height actually widens (and so enlarges) its content
        // beyond its fixed internal 300px layout budget and overflows, so
        // its box stays untouched.
        return ListView(padding: EdgeInsets.all(gap), children: [
          SizedBox(height: phone ? 285 : 215, child: city),
          SizedBox(height: gap),
          SizedBox(height: constraints.maxWidth * .72, child: slide),
          SizedBox(height: gap),
          SizedBox(height: phone ? 168 : 88, child: strip),
          SizedBox(height: gap),
          SizedBox(height: 270, child: countdown),
          SizedBox(height: gap),
          menuButton,
        ]);
      }),
    );
  }
}

class _CityCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final ink = dashboardInk(brightness);
    final muted = dashboardMuted(brightness);
    return _Surface(
      key: const ValueKey('home-city-card'),
      color: dashboardSurfaceCream(brightness),
      child: LayoutBuilder(builder: (context, c) {
        // Tight (landscape phone) mode always uses the max size — the whole
        // block gets rescaled to fit by the FittedBox below anyway, so
        // there's no benefit to a smaller nominal size, only less headroom.
        final size = tight ? 44.0
            : (c.maxWidth * .095).clamp(isPhoneContext(context) ? 33.0 : 18.0, 44.0);
        final gapScale = tight ? 0.35 : 1.0;
        final cityName = location?.ilce.ilceAdi ?? 'Şehir seçin';
        return Center(child: FittedBox(fit: BoxFit.scaleDown,
          child: SizedBox(width: c.maxWidth, child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.mosque_outlined, color: dashboardAccentGold, size: size * (tight ? 0.5 : 1.05)),
            SizedBox(height: (tight ? 3 : 8) * gapScale),
            // The branding caption is the least essential line here — skip
            // it on a landscape phone so the actually-useful city/date/hicri
            // lines below get more of this card's very limited height.
            if (!tight) ...[
              Text('NURANÎ TAKVİM', style: TextStyle(color: muted,
                  fontSize: size * .43, letterSpacing: 2.0, fontWeight: FontWeight.w700)),
              SizedBox(height: size * .45 * gapScale),
            ],
            // A long city name (e.g. "ROTTERDAM") word-wraps into an ugly
            // 2-line split when the card is this narrow; force it to a
            // single line and let it shrink to fit instead.
            SizedBox(width: c.maxWidth, child: FittedBox(fit: BoxFit.scaleDown,
              child: Text(cityName, maxLines: 1, softWrap: false,
                  style: TextStyle(color: ink, fontSize: size,
                      height: 1.1, fontWeight: FontWeight.w800)))),
            SizedBox(height: size * .4 * gapScale),
            // Combine date + weekday onto one line on a landscape phone to
            // save a full line of height.
            if (tight)
              Text('${gunAdlari[now.weekday - 1]}, ${now.day} ${ayAdlari[now.month - 1]} ${now.year}',
                  textAlign: TextAlign.center, style: TextStyle(color: ink,
                      fontSize: size * .5, fontWeight: FontWeight.w600))
            else ...[
              Text('${now.day} ${ayAdlari[now.month - 1]} ${now.year}',
                  textAlign: TextAlign.center, style: TextStyle(color: ink,
                      fontSize: size * .65, fontWeight: FontWeight.w600)),
              SizedBox(height: 4 * gapScale),
              Text(gunAdlari[now.weekday - 1], style: TextStyle(
                  color: muted, fontSize: size * .57)),
            ],
            SizedBox(height: size * .35 * gapScale),
            Container(width: 44, height: 2, color: dashboardAccentGold),
            SizedBox(height: size * .35 * gapScale),
            Text(today?.hicriTarihUzun.isNotEmpty == true ? today!.hicriTarihUzun
                : 'Hicri tarih bekleniyor', textAlign: TextAlign.center,
                style: TextStyle(color: ink, fontSize: size * .57,
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
  const _CountdownCard({required this.next, required this.now, required this.unavailable, this.tight = false});
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
    final ink = dashboardInk(brightness);
    final muted = dashboardMuted(brightness);
    return _Surface(
      key: const ValueKey('home-countdown'),
      color: dashboardSurfaceWhite(brightness),
      child: LayoutBuilder(builder: (context, bounds) {
        final c = BoxConstraints.tightFor(
          width: math.min(bounds.maxWidth, bounds.maxHeight * 1.15),
          height: math.max(bounds.maxHeight, tight ? 200.0 : 300.0),
        );
        final titleSize = (c.maxWidth * (tight ? .12 : .095)).clamp(18.0, 42.0);
        final clockSize = (c.maxWidth * .09).clamp(18.0, 36.0);
        final remaining = next?.time.difference(now);
        final value = remaining == null ? '--:--:--' : _formatRemaining(remaining);
        final spacerFlex = tight ? 1 : 2;
        return Center(child: FittedBox(fit: BoxFit.scaleDown,
          child: SizedBox(width: c.maxWidth, height: c.maxHeight,
            child: Column(children: [
          Spacer(flex: spacerFlex),
          Icon(Icons.schedule_rounded, color: dashboardAccentGold,
              size: (c.maxHeight * .11).clamp(22.0, 58.0)),
          const Spacer(),
          // Wrapped in Flexible+FittedBox (like the countdown digits already
          // are) so a large system text-scale setting shrinks these lines
          // locally instead of overflowing this fixed-aspect card — the
          // enclosing FittedBox only rescales the *whole* column when its
          // natural size is too big, it can't stop this inner Column (which
          // has a real, tight height) from overflowing on its own.
          Flexible(child: FittedBox(fit: BoxFit.scaleDown,
            child: Text(next == null ? unavailable : next!.name == 'Güneş'
                ? 'Güneşin Doğmasına' : '${next!.name} Vaktine',
                key: const ValueKey('countdown-target'), textAlign: TextAlign.center,
                style: TextStyle(color: ink, fontSize: titleSize,
                    height: 1.15, fontWeight: FontWeight.w700)))),
          SizedBox(height: (c.maxHeight * .035).clamp(6.0, 24.0)),
          StableCountdownDigits(value: value, emphasis: tight ? 1.25 : 1.0),
          const SizedBox(height: 8),
          Flexible(child: FittedBox(fit: BoxFit.scaleDown,
            child: Text('KALAN SÜRE', style: TextStyle(color: muted,
                letterSpacing: 2, fontSize: (c.maxWidth * .044)
                    .clamp(isPhoneContext(context) ? 14.0 : 10.0, 18.0),
                fontWeight: FontWeight.w600)))),
          Spacer(flex: spacerFlex),
          Container(height: 1, color: dashboardBorder(brightness)),
          const Spacer(),
          Flexible(child: FittedBox(fit: BoxFit.scaleDown,
            child: Text('${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}',
                key: const ValueKey('home-live-clock'),
                style: TextStyle(color: muted, fontSize: clockSize,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w500)))),
          const Spacer(),
        ]))));
      }),
    );
  }
}

/// Each digit owns an equal, fixed slot. Font fallback and proportional glyphs
/// cannot move the neighbouring digits when a second changes.
class StableCountdownDigits extends StatelessWidget {
  const StableCountdownDigits({super.key, required this.value, this.emphasis = 1.0});
  final String value;

  /// >1 makes the digits claim a bigger share of this card's natural height
  /// relative to the icon/title/label/clock around them — since the whole
  /// card is later rescaled together by one FittedBox, this shifts the
  /// balance toward more prominent digits rather than just scaling
  /// everything uniformly.
  final double emphasis;

  @override
  Widget build(BuildContext context) {
    final ink = dashboardInk(Theme.of(context).brightness);
    return Semantics(label: value, child: ExcludeSemantics(
      child: LayoutBuilder(builder: (context, c) {
        final fontSize = c.maxWidth / 4.8 * emphasis;
        return SizedBox(height: fontSize * 1.3, child: Row(
          key: const ValueKey('countdown-digits'),
          children: List.generate(value.length, (i) => Expanded(
            flex: value[i] == ':' ? 5 : 10,
            child: Center(child: FittedBox(fit: BoxFit.scaleDown,
              child: Text(value[i], key: ValueKey('countdown-digit-$i'),
                style: TextStyle(color: ink, fontSize: fontSize,
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
          ? (cellWidth / 7.4).clamp(14.0, 20.0)
          : (c.maxWidth / 44).clamp(phoneFloor ? 14.0 : 12.0, 31.0);
      final timeSize = compact
          ? (cellWidth / 4.6).clamp(18.0, 30.0)
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
  const _Surface({super.key, required this.color, required this.child});
  final Color color;
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) => Container(
    padding: EdgeInsets.all((c.maxWidth * .055).clamp(12.0, 26.0)),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18),
      border: Border.all(color: dashboardBorder(Theme.of(context).brightness)),
      boxShadow: const [BoxShadow(color: Color(0x09000000), blurRadius: 16, offset: Offset(0, 4))]),
    child: child,
  ));
}

class _HomeMenuButton extends StatelessWidget {
  const _HomeMenuButton({this.compact = false});

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
              textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
            icon: const Icon(Icons.menu_rounded, color: Color(0xFFE9C981)),
            label: const Text('Menü'),
          );
    return SizedBox(
      height: 54,
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
String _formatRemaining(Duration d) => d.isNegative ? '00:00:00'
    : '${_two(d.inHours)}:${_two(d.inMinutes.remainder(60))}:${_two(d.inSeconds.remainder(60))}';
