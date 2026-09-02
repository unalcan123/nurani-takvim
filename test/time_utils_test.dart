import 'package:flutter_test/flutter_test.dart';
import 'package:tvaap_clean/features/locations/data/models.dart';
import 'package:tvaap_clean/features/times/presentation/time_utils.dart';

void main() {
  group('nextPrayerInfo', () {
    test('skips sunrise and counts down to the next prayer', () {
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

      expect(next.name, 'Öğle');
      expect(next.time, DateTime(2026, 9, 2, 13, 10));
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

  test('phoneLocalNow keeps the local clock used by displayed prayer times', () {
    final deviceNow = DateTime(2026, 9, 2, 19, 5);

    final now = phoneLocalNow(systemNow: deviceNow);

    expect(now, deviceNow);
  });

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
