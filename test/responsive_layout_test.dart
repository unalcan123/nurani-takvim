import 'package:tvaap_clean/core/live_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tvaap_clean/core/audio_manager.dart';
import 'package:tvaap_clean/core/bg_music_service.dart';
import 'package:tvaap_clean/core/notification_service.dart';
import 'package:tvaap_clean/core/prayer_alarm_coordinator.dart';
import 'package:tvaap_clean/features/dashboard/presentation/app_shell.dart';
import 'package:tvaap_clean/features/dashboard/presentation/dashboard_home_page.dart';
import 'package:tvaap_clean/features/daily_content/data/daily_content_repository.dart';
import 'package:tvaap_clean/features/locations/data/models.dart';
import 'package:tvaap_clean/features/settings/data/prefs_repository.dart';
import 'package:tvaap_clean/features/settings/presentation/prayer_sound_section.dart';
import 'package:tvaap_clean/features/times/presentation/slayt_widget.dart';
import 'package:tvaap_clean/features/times/presentation/times_page.dart';
import 'adhan_flow_test.dart' show TestPlayer, TestNotifications;

class LayoutNotifications extends TestNotifications {
  @override
  Future<bool?> areNotificationsEnabled() async => true;
  @override
  Future<bool?> canUseFullScreenIntent() async => true;
}

Future<({ProviderContainer container, TestPlayer player})> layoutEnvironment(
  WidgetTester tester, {
  DateTime Function()? nowSource,
}) async {
  SharedPreferences.setMockInitialValues({'slide_category': 'kabe'});
  final prefs = await SharedPreferences.getInstance();
  await PrefsRepository(prefs).addRecentLocation(
    SavedLocation(
      ulke: Ulke(ulkeAdi: 'Hollanda', ulkeAdiEn: 'Netherlands', ulkeId: '1'),
      sehir: Sehir(
        sehirAdi: 'Rotterdam',
        sehirAdiEn: 'Rotterdam',
        sehirId: '2',
      ),
      ilce: Ilce(ilceAdi: 'Rotterdam', ilceAdiEn: 'Rotterdam', ilceId: '3'),
    ),
  );
  final source = LocalJsonDailyContentSource();
  await tester.runAsync(source.ensureLoaded);
  final now = nowSource?.call() ?? DateTime.now();
  final times = [
    for (final d in [now, now.add(const Duration(days: 1))])
      Vakit(
        miladiTarihKisa: '',
        miladiTarihKisaIso8601: '${d.day}.${d.month}.${d.year}',
        miladiTarihUzun: 'Rotterdam',
        miladiTarihUzunIso8601: '',
        hicriTarihKisa: '',
        hicriTarihUzun: '29 Rebiülevvel 1448',
        ayinSekliURL: 'https://example.invalid/moon.png',
        greenwichOrtalamaZamani: 0,
        imsak: '05:00',
        gunes: '06:30',
        ogle: '13:00',
        ikindi: '16:00',
        aksam: '19:00',
        yatsi: '23:59',
        kibleSaati: '',
      ),
  ];
  final player = TestPlayer();
  final notifications = LayoutNotifications();
  final container = ProviderContainer(
    overrides: [
      if (nowSource != null) clockSourceProvider.overrideWithValue(nowSource),
      sharedPrefsProvider.overrideWithValue(prefs),
      dailyContentSourceProvider.overrideWith((ref) async => source),
      timesProvider('3').overrideWith((ref) async => times),
      notificationServiceProvider.overrideWithValue(notifications),
      bgMusicServiceProvider.overrideWith((ref) {
        final music = BgMusicService(ref, audioPlayer: TestPlayer());
        ref.onDispose(music.dispose);
        return music;
      }),
      audioManagerProvider.overrideWith((ref) {
        final audio = AudioManager(ref, audioPlayer: player);
        ref.onDispose(audio.dispose);
        return audio;
      }),
    ],
  );
  addTearDown(() {
    container.dispose();
    notifications.events.close();
  });
  return (container: container, player: player);
}

void resize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> showLayout(
  WidgetTester tester,
  ProviderContainer container,
  Widget child, {
  double textScale = 1,
}) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto'),
          navigatorObservers: [previewRouteObserver],
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
          home: child,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [
    const Size(320, 640), const Size(360, 780), const Size(390, 844),
    const Size(430, 932), const Size(600, 960),
    const Size(800, 1280), const Size(1024, 768), const Size(1280, 800),
    const Size(1920, 1080), const Size(844, 390),
  ]) {
    testWidgets('home uses drawer and horizontal prayer strip at $size', (tester) async {
      resize(tester, size);
      final env = await layoutEnvironment(tester);
      await showLayout(tester, env.container, const AppShell());
      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      final home = find.byType(DashboardHomePage);
      expect(find.descendant(of: home, matching: find.byType(SlaytWidget)), findsOneWidget);
      expect(find.byKey(const ValueKey('home-prayer-strip')), findsOneWidget);
      if (size.width > size.height) {
        final slide = tester.getRect(find.byKey(const ValueKey('home-slideshow')));
        final strip = tester.getRect(find.byKey(const ValueKey('home-prayer-strip')));
        final panel = tester.getRect(find.byKey(const ValueKey('home-city-card')));
        final countdown = tester.getRect(find.byKey(const ValueKey('home-countdown')));
        final menu = tester.getRect(find.byKey(const ValueKey('home-menu-button')));
        expect(slide.width / panel.width, closeTo(3, .01));
        expect(strip.top, greaterThan(slide.bottom));
        expect(strip.bottom, lessThanOrEqualTo(size.height));
        expect(countdown.top, greaterThan(panel.bottom));
        expect(menu.bottom, lessThanOrEqualTo(size.height));
        expect(find.descendant(of: home, matching: find.byType(ListView)), findsNothing);
        await tester.tap(find.byKey(const ValueKey('home-menu-button')));
        await tester.pumpAndSettle();
        expect(find.text('Ayarlar'), findsOneWidget);
        await tester.tap(find.text('Ayarlar'));
        await tester.pumpAndSettle();
        expect(env.container.read(dashboardSelectedTabProvider), 3);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  // Regression guard for a real bug: a nested FittedBox around the city
  // name reported its *unscaled* natural height upward, inflating the
  // whole city card's measured height and forcing the outer FittedBox to
  // shrink the city/date/hicri text far below readability on short
  // landscape phones. Assert the actual *rendered* (post-scale) font size
  // of each line lands in the requested range at the two reported sizes.
  for (final size in [const Size(690, 320), const Size(740, 360)]) {
    testWidgets('home city card text is readable on a short landscape phone at $size', (tester) async {
      resize(tester, size);
      final env = await layoutEnvironment(tester);
      await showLayout(tester, env.container, const AppShell());
      expect(tester.takeException(), isNull);

      double effectiveFontSize(Finder finder) {
        final element = finder.evaluate().single;
        final text = element.widget as Text;
        final scale = element.renderObject!.getTransformTo(null).getMaxScaleOnAxis();
        return text.style!.fontSize! * scale;
      }

      final cityCard = find.byKey(const ValueKey('home-city-card'));
      final cityTexts = find.descendant(of: cityCard, matching: find.byType(Text));
      expect(cityTexts, findsNWidgets(3));

      final citySize = effectiveFontSize(cityTexts.at(0));
      final dateSize = effectiveFontSize(cityTexts.at(1));
      final hicriSize = effectiveFontSize(cityTexts.at(2));

      expect(citySize, inInclusiveRange(18.0, 22.0),
          reason: 'city name font size out of the requested 18-22px range');
      expect(dateSize, inInclusiveRange(14.0, 16.0),
          reason: 'date line font size out of the requested 14-16px range');
      expect(hicriSize, inInclusiveRange(14.0, 16.0),
          reason: 'hicri line font size out of the requested 14-16px range');

      await tester.pumpWidget(const SizedBox());
    });
  }

  // Landscape phone (e.g. a phone rotated sideways) at enlarged system text
  // size — a distinct code path (Row-based layout, non-compact prayer
  // strip) from the portrait ListView cases below.
  for (final textScale in [1.0, 1.3, 2.0]) {
    testWidgets('home fits landscape phone at textScale $textScale', (tester) async {
      resize(tester, const Size(844, 390));
      final env = await layoutEnvironment(tester);
      await showLayout(tester, env.container, const AppShell(), textScale: textScale);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('home-prayer-strip')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-countdown')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  // Phone widths at normal and enlarged system text size: guards against
  // horizontal/vertical overflow from the phone-readability floors (see
  // core/responsive.dart) while respecting the platform TextScaler.
  for (final size in [
    const Size(320, 640), const Size(360, 780), const Size(390, 844), const Size(430, 932),
  ]) {
    for (final textScale in [1.0, 1.3, 2.0]) {
      testWidgets('home fits at phone size $size with textScale $textScale', (tester) async {
        resize(tester, size);
        final env = await layoutEnvironment(tester);
        await showLayout(tester, env.container, const AppShell(), textScale: textScale);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('home-prayer-strip')), findsOneWidget);
        // The countdown card is further down the phone ListView than the
        // initial viewport/cache-extent reaches — scroll to it like a real
        // user would before asserting it rendered without overflowing.
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('home-countdown')),
          300.0,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('home-countdown')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final size in [const Size(320, 640), const Size(800, 1280)]) {
    testWidgets(
      'preview buttons fit at $size with large text and remain usable',
      (tester) async {
        resize(tester, size);
        final env = await layoutEnvironment(tester);
        await showLayout(
          tester,
          env.container,
          const Scaffold(
            body: SingleChildScrollView(child: PrayerSoundSection()),
          ),
          textScale: 1.5,
        );
        expect(tester.takeException(), isNull);
        final play = find.text('Dinle').first;
        await tester.ensureVisible(play);
        await tester.tap(play);
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
        expect(env.player.isPlaying, isTrue);
        final stop = find.text('Durdur').first;
        await tester.ensureVisible(stop);
        await tester.tap(stop);
        await tester.pumpAndSettle();
        expect(env.player.isPlaying, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

  }
}
