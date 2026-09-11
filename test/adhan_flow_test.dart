import 'package:tvaap_clean/core/prayer_alarm_watcher.dart';
import 'package:tvaap_clean/features/times/presentation/times_page.dart';
import 'prayer_lifecycle_test.dart' show TestPrayerDay;
import 'package:tvaap_clean/core/live_clock.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:tvaap_clean/features/locations/data/models.dart';
import 'package:tvaap_clean/features/settings/data/alert_settings.dart';
import 'package:tvaap_clean/features/times/presentation/slayt_widget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tvaap_clean/core/audio_manager.dart';
import 'package:tvaap_clean/core/bg_music_service.dart';
import 'package:tvaap_clean/core/notification_service.dart';
import 'package:tvaap_clean/core/prayer_alarm_coordinator.dart';
import 'package:tvaap_clean/core/prayer_event_store.dart';
import 'package:tvaap_clean/features/settings/data/adhan_settings.dart';
import 'package:tvaap_clean/features/settings/data/prefs_repository.dart';
import 'package:tvaap_clean/features/settings/presentation/alert_settings_controller.dart';
import 'package:tvaap_clean/features/times/presentation/alarm_page.dart';

class TestPlayer extends Fake implements AudioPlayer {
  final states = StreamController<ProcessingState>.broadcast(sync: true);
  final List<String> played = [];
  String source = '';
  bool staleCompletion = false;
  Completer<void>? loading;
  bool isPlaying = false;
  AudioSource? loadedSource;
  @override
  Stream<ProcessingState> get processingStateStream =>
      staleCompletion
          ? (Stream<ProcessingState>.multi((sink) {
            sink.add(ProcessingState.completed);
            final subscription = states.stream.listen(sink.add);
            sink.onCancel = subscription.cancel;
          }))
          : states.stream;
  @override
  AudioSource? get audioSource => loadedSource;
  @override
  Future<Duration?> setAsset(
    String asset, {
    bool preload = true,
    Duration? initialPosition,
    dynamic tag,
    String? package,
  }) async {
    source = asset;
    await loading?.future;
    return const Duration(minutes: 2);
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    loadedSource = source;
    return const Duration(minutes: 2);
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {}
  @override
  Future<void> setVolume(double value) async {}
  @override
  Future<void> play() async {
    isPlaying = true;
    played.add(source);
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
  }

  @override
  Future<void> stop() async {
    isPlaying = false;
  }

  @override
  Future<void> dispose() async {
    await states.close();
  }
}

class TestNotifications extends Fake implements NotificationService {
  final events = StreamController<String>.broadcast();
  @override
  bool adhanActive = false;
  bool foreground = false;
  int transientStops = 0;
  int schedules = 0;
  @override
  Future<void> scheduleAlarms(List<Vakit> times, AlertSettings settings) async {
    schedules++;
  }

  @override
  Stream<String> get prayerNotificationStream => events.stream;
  @override
  Future<void> stopTransientAudio() async {
    transientStops++;
  }

  @override
  Future<void> cancelPrayerNotification(
    DateTime date,
    String prayerName,
  ) async {}
  @override
  Future<void> setAdhanPlaybackActive(bool active) async {
    foreground = active;
  }
}

Future<
  ({
    ProviderContainer container,
    TestPlayer player,
    TestPlayer music,
    TestNotifications notifications,
  })
>
setup({
  bool? musicEnabled,
  DateTime Function()? now,
  List<Vakit>? times,
}) async {
  SharedPreferences.setMockInitialValues({
    if (musicEnabled != null) 'bg_music_enabled': musicEnabled,
    'prayer_alarms_Öğle': true,
  });
  final prefs = await SharedPreferences.getInstance();
  final player = TestPlayer();
  final music = TestPlayer();
  final notifications = TestNotifications();
  final container = ProviderContainer(
    overrides: [
      if (now != null) clockSourceProvider.overrideWithValue(now),
      if (times != null)
        timesProvider('test').overrideWith((ref) async => times),
      sharedPrefsProvider.overrideWithValue(prefs),
      notificationServiceProvider.overrideWithValue(notifications),
      bgMusicServiceProvider.overrideWith((ref) {
        final bg = BgMusicService(ref, audioPlayer: music);
        ref.onDispose(bg.dispose);
        return bg;
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
  return (
    container: container,
    player: player,
    music: music,
    notifications: notifications,
  );
}

const previewA = AdhanSource.asset(title: 'A', path: 'assets/a.mp3');
const previewB = AdhanSource.asset(title: 'B', path: 'assets/b.mp3');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'daily scheduling keeps 10-minute reminders separate and stable after restart',
    () async {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.UTC);
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final scheduled = <Map<dynamic, dynamic>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'cancelAll') scheduled.clear();
            if (call.method == 'pendingNotificationRequests') {
              return scheduled
                  .map(
                    (e) => {
                      'id': e['id'],
                      'title': '',
                      'body': '',
                      'payload': e['payload'],
                    },
                  )
                  .toList();
            }
            if (call.method == 'cancel') {
              scheduled.removeWhere(
                (e) => e['id'] == (call.arguments as Map)['id'],
              );
            }
            if (call.method == 'zonedSchedule') {
              scheduled.add(call.arguments as Map);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = NotificationService(
        FlutterLocalNotificationsPlugin(),
        audioPlayer: TestPlayer(),
      );
      addTearDown(service.dispose);
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final days = [tomorrow, tomorrow.add(const Duration(days: 1))];
      final times =
          days
              .map(
                (d) => Vakit(
                  miladiTarihKisa: '',
                  miladiTarihKisaIso8601: '${d.day}.${d.month}.${d.year}',
                  miladiTarihUzun: '',
                  miladiTarihUzunIso8601: '',
                  hicriTarihKisa: '',
                  hicriTarihUzun: '',
                  ayinSekliURL: '',
                  greenwichOrtalamaZamani: 0,
                  imsak: '05:00',
                  gunes: '06:30',
                  ogle: '13:00',
                  ikindi: '16:00',
                  aksam: '19:00',
                  yatsi: '21:00',
                  kibleSaati: '',
                ),
              )
              .toList();
      final settings = AlertSettings(
        prayerAlarms: {for (final p in prayerNames) p: true},
        preNotifications: {10: true},
      );
      await service.scheduleAlarms(times, settings);
      final fajr = scheduled.firstWhere(
        (e) => e['id'] == prayerNotificationId(tomorrow, 0),
      );
      expect(DateTime.parse(fajr['scheduledDateTime']).minute, 30);
      expect(
        DateTime.parse(fajr['scheduledDateTime']),
        DateTime.parse(
          tz.TZDateTime.from(
            DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 5, 30),
            tz.local,
          ).toIso8601String().replaceAll('Z', ''),
        ),
      );
      final env = await setup();
      final controller = env.container.read(alertSettingsProvider.notifier);
      expect(env.container.read(alertSettingsProvider).fajrDelayMinutes, 30);
      await controller.setFajrDelayMinutes(0, times);
      env.container.invalidate(alertSettingsProvider);
      expect(env.container.read(alertSettingsProvider).fajrDelayMinutes, 0);
      await expectLater(
        env.container
            .read(alertSettingsProvider.notifier)
            .setFajrDelayMinutes(90, times),
        throwsArgumentError,
      );
      expect(env.container.read(alertSettingsProvider).fajrDelayMinutes, 0);
      expect(scheduled.length, 18);
      final ids = scheduled.map((e) => e['id']).toSet();
      expect(ids.length, 18);
      final adhan = scheduled.firstWhere(
        (e) => e['id'] == prayerNotificationId(tomorrow, 1),
      );
      final pre = scheduled.firstWhere(
        (e) => e['id'] == preNotificationId(tomorrow, 1, 2),
      );
      expect(adhan['payload'], startsWith('prayer:Öğle|'));
      expect(pre['payload'], anyOf(isNull, isEmpty));
      expect(
        DateTime.parse(
          adhan['scheduledDateTime'],
        ).difference(DateTime.parse(pre['scheduledDateTime'])),
        const Duration(minutes: 10),
      );
      await service.scheduleAlarms(times, settings);
      expect(scheduled.map((e) => e['id']).toSet(), ids);
      await service.setAdhanPlaybackActive(true);
      expect(scheduled.length, 10); // only the five adhans per day remain
      await service.scheduleAlarms(times, settings);
      expect(
        scheduled.length,
        10,
      ); // settings refresh cannot reintroduce reminders
      await service.showPrePrayerNotification(
        'Öğle',
        10,
        'assets/reminder.mp3',
      );
      await service.setAdhanPlaybackActive(false);
      expect(scheduled.map((e) => e['id']).toSet(), ids);
    },
  );

  testWidgets(
    'slideshow pauses on its current slide and continues from that slide',
    (tester) async {
      final env = await setup();
      await env.container
          .read(alertSettingsProvider.notifier)
          .setSlideCategory('kabe');
      var index = 0;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: env.container,
            child: MaterialApp(
              home: Scaffold(
                body: SlaytWidget(height: 500, onPageChanged: (i) => index = i),
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.byType(CarouselSlider), findsOneWidget);
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(index, 1);
      final carouselState = tester.state(find.byType(CarouselSlider));
      env.container.read(adhanActiveProvider.notifier).state = true;
      await tester.pump();
      await tester.pump(const Duration(minutes: 3));
      expect(index, 1);
      expect(tester.state(find.byType(CarouselSlider)), same(carouselState));
      env.container.read(adhanActiveProvider.notifier).state = false;
      await tester.pump();
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(index, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'fresh install disables music; saved true and false survive loading',
    () async {
      for (final enabled in [null, true, false]) {
        final env = await setup(musicEnabled: enabled);
        expect(
          env.container.read(alertSettingsProvider).bgMusicEnabled,
          enabled ?? false,
        );
      }
    },
  );

  test(
    'saved adhan selection is used after settings reload, including fajr',
    () async {
      final env = await setup();
      await env.container
          .read(alertSettingsProvider.notifier)
          .selectMadinahAdhan();
      env.container.invalidate(alertSettingsProvider);
      expect(
        env.container.read(alertSettingsProvider).adhanSettings.type,
        AdhanType.madinah,
      );
      final audio = env.container.read(audioManagerProvider);
      await audio.stopAllForAdhan();
      await audio.playAdhan('İmsak', onError: (e) => fail('$e'));
      expect(env.player.played.last, madinahFajrAdhanAsset);
      await audio.stopAdhan();
      await audio.resumeAfterAdhan();
    },
  );

  test('daily claim survives a new store and allows the next day', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final day = DateTime(2026, 9, 6);
    expect(await PrayerEventStore(prefs).claim(day, 'Öğle'), isTrue);
    expect(await PrayerEventStore(prefs).claim(day, 'Öğle'), isFalse);
    expect(await PrayerEventStore(prefs).claim(day, 'İkindi'), isTrue);
    expect(
      await PrayerEventStore(
        prefs,
      ).claim(day.add(const Duration(days: 1)), 'Öğle'),
      isTrue,
    );
  });

  for (final enabled in [true, false]) {
    test(
      'adhan suspends music=$enabled, blocks preview, restores preference',
      () async {
        final env = await setup(musicEnabled: enabled);
        final bg = env.container.read(bgMusicServiceProvider);
        await bg.init();
        expect(env.music.isPlaying, enabled);
        final audio = env.container.read(audioManagerProvider);
        await audio.playPreview('settings', 'a', previewA);
        expect(env.music.isPlaying, isFalse);
        await audio.stopAllForAdhan();
        expect(env.player.isPlaying, isFalse);
        expect(env.container.read(adhanActiveProvider), isTrue);
        await audio.playAdhan('Öğle', onError: (e) => fail('$e'));
        expect(env.player.played.last, makkahNormalAdhanAsset);
        await audio.playPreview('settings', 'b', previewB);
        expect(env.player.played.last, makkahNormalAdhanAsset);
        expect(env.music.isPlaying, isFalse);
        expect(env.notifications.foreground, isTrue);
        await audio.stopAdhan();
        await audio.resumeAfterAdhan();
        expect(env.player.isPlaying, isFalse);
        expect(env.notifications.foreground, isFalse);
        expect(env.container.read(adhanActiveProvider), isFalse);
        expect(env.music.isPlaying, enabled);
      },
    );
  }

  test(
    'STOP during source loading prevents delayed preview playback',
    () async {
      final env = await setup();
      final audio = env.container.read(audioManagerProvider);
      env.player.loading = Completer<void>();
      final pending = audio.playPreview('settings', 'a', previewA);
      await Future<void>.delayed(Duration.zero);
      await audio.stopPreview('settings');
      env.player.loading!.complete();
      await pending;
      expect(env.player.played, isEmpty);
      expect(audio.previewKey.value, isNull);
    },
  );

  test('rapid preview selection only starts the latest source', () async {
    final env = await setup();
    final audio = env.container.read(audioManagerProvider);
    env.player.loading = Completer<void>();
    final first = audio.playPreview('settings', 'a', previewA);
    await Future<void>.delayed(Duration.zero);
    final second = audio.playPreview('settings', 'b', previewB);
    env.player.loading!.complete();
    await Future.wait([first, second]);
    expect(env.player.played, ['assets/b.mp3']);
    audio.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await Future<void>.delayed(Duration.zero);
    expect(env.player.isPlaying, isFalse);
    expect(audio.previewKey.value, isNull);
  });

  testWidgets('watcher delays fajr, resumes and triggers again next day', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 11, 4, 58);
    final env = await setup(
      now: () => now,
      times: [TestPrayerDay(now), TestPrayerDay(DateTime(2026, 9, 12))],
    );
    await env.container
        .read(prefsRepositoryProvider)
        .addRecentLocation(
          SavedLocation(
            ulke: Ulke(ulkeAdi: 'Test', ulkeAdiEn: 'Test', ulkeId: 'test'),
            sehir: Sehir(sehirAdi: 'Test', sehirAdiEn: 'Test', sehirId: 'test'),
            ilce: Ilce(ilceAdi: 'Test', ilceAdiEn: 'Test', ilceId: 'test'),
          ),
        );
    await env.container
        .read(alertSettingsProvider.notifier)
        .togglePrayerAlarm('İmsak', true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: env.container,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: const PrayerAlarmWatcher(child: Scaffold(body: Text('Home'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AlarmPage), findsNothing);
    for (var day = 11; day <= 12; day++) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = DateTime(2026, 9, day, 5, 28);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(AlarmPage), findsOneWidget);
      expect(env.player.played.length, day - 10);
      env.player.states.add(ProcessingState.completed);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(AlarmPage), findsNothing);
      now = DateTime(2026, 9, day, 6, 55);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(AlarmPage), findsNothing);
    }
    await env.container.read(alertSettingsProvider.notifier)
        .setFajrDelayMinutes(116, [TestPrayerDay(now)]);
    await env.container.read(sharedPrefsProvider).remove(PrayerEventStore.key);
    now = DateTime(2026, 9, 12, 6, 55);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(AlarmPage), findsNothing);
    expect(env.player.played.length, 2);
    expect(env.notifications.schedules, greaterThan(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'two consecutive days play despite stale completed player state',
    (tester) async {
      var now = DateTime(2026, 9, 11, 13);
      final env = await setup(now: () => now);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: env.container,
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      final coordinator = env.container.read(prayerAlarmCoordinatorProvider);
      for (var day = 11; day <= 12; day++) {
        now = DateTime(2026, 9, day, 13);
        env.player.staleCompletion = day == 12;
        final finished = coordinator.triggerPrayerTime(prayerName: 'Öğle');
        await tester.pumpAndSettle();
        expect(find.byType(AlarmPage), findsOneWidget);
        await coordinator.triggerPrayerTime(prayerName: 'Öğle');
        expect(env.player.played.length, day - 10);
        env.player.states.add(ProcessingState.completed);
        await tester.pumpAndSettle();
        await finished;
        await coordinator.triggerPrayerTime(prayerName: 'Öğle');
        await tester.pumpAndSettle();
        expect(find.byType(AlarmPage), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final complete in [false, true]) {
    testWidgets(
      'alarm closes on ${complete ? 'completion' : 'STOP'} and cannot replay from a notification',
      (tester) async {
        final env = await setup();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: env.container,
            child: MaterialApp(
              navigatorKey: rootNavigatorKey,
              navigatorObservers: [previewRouteObserver],
              home: const Scaffold(body: Text('Önceki sayfa')),
            ),
          ),
        );
        final coordinator = env.container.read(prayerAlarmCoordinatorProvider);
        final finished = coordinator.triggerPrayerTime(prayerName: 'Öğle');
        await tester.pumpAndSettle();
        expect(find.byType(AlarmPage), findsOneWidget);
        expect(find.text('Öğle Vakti Girdi'), findsOneWidget);
        expect(env.container.read(adhanActiveProvider), isTrue);
        if (complete) {
          env.player.states.add(ProcessingState.completed);
        } else {
          await tester.tap(find.text('DURDUR'));
        }
        await tester.pumpAndSettle();
        await finished;
        expect(find.byType(AlarmPage), findsNothing);
        expect(find.text('Önceki sayfa'), findsOneWidget);
        expect(env.container.read(adhanActiveProvider), isFalse);
        env.notifications.events.add(
          'Öğle|${DateTime.now().toIso8601String()}',
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlarmPage), findsNothing);
        expect(env.player.played.length, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
