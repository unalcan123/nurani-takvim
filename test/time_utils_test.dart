import 'package:flutter_test/flutter_test.dart';
import 'package:tvaap_clean/features/locations/data/models.dart';
import 'package:tvaap_clean/features/times/presentation/time_utils.dart';

void main() {
  test('exact imsak, delayed adhan and sunrise boundaries are independent', () {
    final day = _vakit(imsak: '04:58', gunes: '06:55', ogle: '13:46');
    for (final entry in [
      (4, 57, 'İmsak'),
      (4, 58, 'Güneş'),
      (5, 28, 'Güneş'),
      (6, 54, 'Güneş'),
      (6, 55, 'Öğle'),
      (13, 46, 'İkindi'),
      (17, 0, 'Akşam'),
      (20, 20, 'Yatsı'),
      (21, 50, 'İmsak'),
    ]) {
      expect(
        nextPrayerInfo(day, DateTime(2026, 9, 2, entry.$1, entry.$2)).name,
        entry.$3,
      );
    }
    expect(
      adhanTime(day, DateTime(2026, 9, 2), 'İmsak', 30),
      DateTime(2026, 9, 2, 5, 28),
    );
    expect(
      adhanTime(day, DateTime(2026, 9, 2), 'İmsak', 0),
      DateTime(2026, 9, 2, 4, 58),
    );
    for (final delay in [-1, 117, 118]) {
      expect(adhanTime(day, DateTime(2026, 9, 2), 'İmsak', delay), isNull);
    }
    expect(adhanTime(day, DateTime(2026, 9, 2), 'Güneş', 0), isNull);
    expect(currentPrayerName(day, DateTime(2026, 9, 2, 6, 55)), 'Güneş');
  });

  group('nextPrayerInfo', () {
    test('counts down to sunrise after imsak', () {
      final vakit = _vakit(
        imsak: '05:00',
        gunes: '06:30',
        ogle: '13:10',
        ikindi: '17:00',
        aksam: '20:20',
        yatsi: '21:50',
      );
      final now = DateTime(2026, 9, 2, 5, 30);

      final next = nextPrayerInfo(vakit, now);

      expect(next.name, 'Güneş');
      expect(next.time, DateTime(2026, 9, 2, 6, 30));
    });

    test('uses tomorrow imsak after yatsi has passed', () {
      final today = _vakit(
        imsak: '05:00',
        gunes: '06:30',
        ogle: '13:10',
        ikindi: '17:00',
        aksam: '20:20',
        yatsi: '21:50',
      );
      final tomorrow = _vakit(
        date: '03.09.2026',
        imsak: '05:02',
        gunes: '06:32',
        ogle: '13:09',
        ikindi: '16:58',
        aksam: '20:18',
        yatsi: '21:48',
      );
      final now = DateTime(2026, 9, 2, 22, 15);

      final next = nextPrayerInfo(today, now, tomorrow: tomorrow);

      expect(next.name, 'İmsak');
      expect(next.time, DateTime(2026, 9, 3, 5, 2));
    });
  });

  test(
    'phoneLocalNow keeps the local clock used by displayed prayer times',
    () {
      final deviceNow = DateTime(2026, 9, 2, 19, 5);

      final now = phoneLocalNow(systemNow: deviceNow);

      expect(now, deviceNow);
    },
  );

  test('does not skip aksam when local time is before aksam', () {
    final vakit = _vakit(
      greenwichOrtalamaZamani: 3,
      imsak: '04:49',
      gunes: '06:40',
      ogle: '13:45',
      ikindi: '17:39',
      aksam: '20:10',
      yatsi: '21:55',
    );
    final now = phoneLocalNow(systemNow: DateTime(2026, 9, 2, 19, 5));

    final next = nextPrayerInfo(vakit, now);

    expect(next.name, 'Akşam');
    expect(next.time, DateTime(2026, 9, 2, 20, 10));
  });
}

Vakit _vakit({
  String date = '02.09.2026',
  num greenwichOrtalamaZamani = 3,
  String imsak = '05:00',
  String gunes = '06:30',
  String ogle = '13:10',
  String ikindi = '17:00',
  String aksam = '20:20',
  String yatsi = '21:50',
}) {
  return Vakit(
    miladiTarihKisa: date,
    miladiTarihKisaIso8601: date,
    miladiTarihUzun: date,
    miladiTarihUzunIso8601: date,
    hicriTarihKisa: '',
    hicriTarihUzun: '',
    ayinSekliURL: '',
    greenwichOrtalamaZamani: greenwichOrtalamaZamani,
    imsak: imsak,
    gunes: gunes,
    ogle: ogle,
    ikindi: ikindi,
    aksam: aksam,
    yatsi: yatsi,
    kibleSaati: '',
  );
}
