import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvaap_clean/core/live_clock.dart';
import 'package:tvaap_clean/features/locations/data/location_providers.dart';
import 'package:tvaap_clean/features/locations/data/location_repository.dart';
import 'package:tvaap_clean/features/locations/data/models.dart';
import 'package:tvaap_clean/features/times/presentation/time_utils.dart';
import 'package:tvaap_clean/features/times/presentation/times_page.dart';

class TestPrayerDay extends Fake implements Vakit {
  TestPrayerDay(this.date);
  final DateTime date;
  @override
  String get miladiTarihKisaIso8601 => '${date.day}.${date.month}.${date.year}';
  @override
  String get imsak => '04:58';
  @override
  String get gunes => '06:55';
  @override
  String get ogle => '13:46';
  @override
  String get ikindi => '17:00';
  @override
  String get aksam => '20:00';
  @override
  String get yatsi => '21:00';
}

class Repository extends Fake implements LocationRepository {
  Repository(this.now);
  final DateTime Function() now;
  int calls = 0;
  bool expired = false;
  @override
  Future<List<Vakit>> vakitler(String id) async {
    calls++;
    return [TestPrayerDay(expired ? DateTime(2026, 8, 1) : now())];
  }
}

void main() {
  testWidgets('seconds, resume jump, midnight refresh and offline recovery', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 11, 4, 57, 58);
    final repo = Repository(() => now);
    final container = ProviderContainer(
      overrides: [
        clockSourceProvider.overrideWithValue(() => now),
        locationRepoProvider.overrideWithValue(repo),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              final clock = ref.watch(liveClockProvider);
              final data =
                  ref.watch(timesProvider('existing-city')).valueOrNull;
              final day = data == null ? null : findVakitForDate(data, clock);
              if (day == null) return const Text('Loading');
              final next = nextPrayerInfo(day, clock);
              return Text(
                '${next.name}:${next.time.difference(clock).inSeconds}',
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('İmsak:2'), findsOneWidget);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('İmsak:1'), findsOneWidget);
    now = DateTime(2026, 9, 11, 4, 58);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Güneş:7020'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = DateTime(2026, 9, 11, 6, 55);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Öğle:24660'), findsOneWidget);
    expect(repo.calls, 1);
    now = DateTime(2026, 9, 12);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(repo.calls, 2);
    expect(find.text('İmsak:17880'), findsOneWidget);
    repo.expired = true;
    now = DateTime(2026, 9, 13);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Loading'), findsOneWidget);
    final before = repo.calls;
    await tester.pump(const Duration(seconds: 10));
    expect(repo.calls, before);
    repo.expired = false;
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();
    expect(find.text('İmsak:17880'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}
