import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';

/// Günlük içerik kaynağı için soyut arayüz. İleride bu içerikler bir
/// backend/CMS'ten çekilecekse, aynı arayüzü uygulayan yeni bir sınıf
/// (`RemoteDailyContentSource` gibi) eklemek yeterli olur; UI katmanı
/// değişmez.
abstract class DailyContentSource {
  DailyAyet ayetForDate(DateTime date);
  DailyHadith hadithForDate(DateTime date);
  DailyWord wordForDate(DateTime date);

  /// Bu tarih için kayıtlı, doğrulanmış bir tarihî olay yoksa `null` döner.
  /// Olay asla üretilmez/tahmin edilmez — yalnızca curate edilmiş veri
  /// kümesinden okunur.
  HistoricalEvent? historicalEventForDate(DateTime date);
}

/// `assets/data/*.json` dosyalarından okuyan, bellek içi ve deterministik
/// (tarihe göre sabit, rastgele olmayan) seçim yapan varsayılan kaynak.
class LocalJsonDailyContentSource implements DailyContentSource {
  final String locale;

  List<DailyAyet>? _ayetler;
  List<DailyHadith>? _hadisler;
  List<DailyWord>? _sozler;
  List<HistoricalEvent>? _tarihiOlaylar;

  LocalJsonDailyContentSource({this.locale = 'tr'});

  Future<void> ensureLoaded() async {
    if (_ayetler != null) return;

    final results = await Future.wait([
      _loadJsonList('assets/data/ayetler.json'),
      _loadJsonList('assets/data/hadisler.json'),
      _loadJsonList('assets/data/sozler.json'),
      _loadJsonList('assets/data/tarihte_bugun.json'),
    ]);

    _ayetler = results[0].map((e) => DailyAyet.fromJson(e)).toList();
    _hadisler = results[1].map((e) => DailyHadith.fromJson(e)).toList();
    _sozler = results[2].map((e) => DailyWord.fromJson(e)).toList();
    _tarihiOlaylar = results[3].map((e) => HistoricalEvent.fromJson(e)).toList();
  }

  Future<List<Map<String, dynamic>>> _loadJsonList(String assetPath) async {
    final jsonString = await rootBundle.loadString(assetPath);
    final Map<String, dynamic> decoded = json.decode(jsonString) as Map<String, dynamic>;
    final List<dynamic> list = (decoded[locale] ?? decoded['tr']) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  int _dayOfYear(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    return date.difference(startOfYear).inDays;
  }

  @override
  DailyAyet ayetForDate(DateTime date) {
    final list = _ayetler!;
    return list[_dayOfYear(date) % list.length];
  }

  @override
  DailyHadith hadithForDate(DateTime date) {
    final list = _hadisler!;
    return list[_dayOfYear(date) % list.length];
  }

  @override
  DailyWord wordForDate(DateTime date) {
    final list = _sozler!;
    return list[_dayOfYear(date) % list.length];
  }

  @override
  HistoricalEvent? historicalEventForDate(DateTime date) {
    final matches = _tarihiOlaylar!.where((e) => e.ay == date.month && e.gun == date.day).toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) => a.oncelik.compareTo(b.oncelik));
    return matches.first;
  }

  DailyContentBundle bundleForDate(DateTime date) => DailyContentBundle(
        ayet: ayetForDate(date),
        hadith: hadithForDate(date),
        soz: wordForDate(date),
        tarihiOlay: historicalEventForDate(date),
      );
}

/// Kaynağı bir kez yükleyip hazırlayan provider. UI, veri hazır olana kadar
/// bu `FutureProvider`'ı bekler; sonrasında `dailyContentForDateProvider`
/// senkron olarak bellekten okur.
final dailyContentSourceProvider = FutureProvider<LocalJsonDailyContentSource>((ref) async {
  final source = LocalJsonDailyContentSource();
  await source.ensureLoaded();
  return source;
});

/// Verilen tarih için içerik demetini döner. `dailyContentSourceProvider`
/// henüz yüklenmediyse `null` döner; UI bunu yükleniyor durumu olarak ele alır.
final dailyContentForDateProvider = Provider.family<DailyContentBundle?, DateTime>((ref, date) {
  final sourceAsync = ref.watch(dailyContentSourceProvider);
  return sourceAsync.whenOrNull(data: (source) => source.bundleForDate(date));
});
