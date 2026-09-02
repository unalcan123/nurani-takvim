import '../../locations/data/models.dart';

/// Verilen [date] gününe ait [Vakit] kaydını listeden bulur.
///
/// `Vakit.miladiTarihKisaIso8601` formatı "gg.aa.yyyy" şeklindedir.
/// Eşleşme bulunamazsa `null` döner.
Vakit? findVakitForDate(List<Vakit> list, DateTime date) {
  for (final v in list) {
    final parts = v.miladiTarihKisaIso8601.split('.');
    if (parts.length != 3) continue;

    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) continue;

    if (d == date.day && m == date.month && y == date.year) {
      return v;
    }
  }
  return null;
}

/// Namaz vakitleriyle karşılaştırılacak telefon yerel saatini döner.
DateTime phoneLocalNow({DateTime? systemNow}) => (systemNow ?? DateTime.now()).toLocal();

/// Verilen [today] vaktine göre bir sonraki namazı ve saatini döner.
/// Yatsı da geçmişse, [tomorrow] varsa onun imsak saatine, yoksa bugünün
/// imsak saatine (yaklaşık) düşer.
({String name, DateTime time}) nextPrayerInfo(Vakit today, DateTime now, {Vakit? tomorrow}) {
  DateTime parse(String timeStr, DateTime date) {
    final parts = timeStr.split(':');
    return DateTime(date.year, date.month, date.day, int.parse(parts[0]), int.parse(parts[1]));
  }

  final prayers = [
    (name: 'İmsak', time: parse(today.imsak, now)),
    (name: 'Öğle', time: parse(today.ogle, now)),
    (name: 'İkindi', time: parse(today.ikindi, now)),
    (name: 'Akşam', time: parse(today.aksam, now)),
    (name: 'Yatsı', time: parse(today.yatsi, now)),
  ];

  for (final p in prayers) {
    if (p.time.isAfter(now)) return p;
  }

  final nextDay = now.add(const Duration(days: 1));
  final imsakStr = tomorrow?.imsak ?? today.imsak;
  return (name: 'İmsak', time: parse(imsakStr, nextDay));
}

/// O anki (aktif) namaz vaktinin adını döner — henüz imsak girmediyse
/// 'Yatsı' (bir önceki günün son vakti) kabul edilir.
String currentPrayerName(Vakit today, DateTime now) {
  DateTime parse(String timeStr) {
    final parts = timeStr.split(':');
    return DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
  }

  final prayers = [
    (name: 'İmsak', time: parse(today.imsak)),
    (name: 'Güneş', time: parse(today.gunes)),
    (name: 'Öğle', time: parse(today.ogle)),
    (name: 'İkindi', time: parse(today.ikindi)),
    (name: 'Akşam', time: parse(today.aksam)),
    (name: 'Yatsı', time: parse(today.yatsi)),
  ];

  final passed = prayers.where((p) => p.time.isBefore(now));
  return passed.isNotEmpty ? passed.last.name : 'Yatsı';
}
