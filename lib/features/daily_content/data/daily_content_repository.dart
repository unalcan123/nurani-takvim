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

  static const DailyHadith _hadithFallback = DailyHadith(
    metin: 'Bugün için hadis içeriği henüz eklenmemiş.',
    kaynak: '-',
    verified: false,
    isSampleData: true,
  );

  static const DailyWord _wordFallback = DailyWord(
    soz: 'Bugün için söz içeriği henüz eklenmemiş.',
    yazar: '-',
    kaynak: '-',
    verified: false,
    isSampleData: true,
  );

  @override
  DailyAyet ayetForDate(DateTime date) {
    final list = _ayetler!;
    return list[_dayOfYear(date) % list.length];
  }

  @override
  DailyHadith hadithForDate(DateTime date) {
    // `verified == false` kayıtlar günlük rotasyonda varsayılan olarak
    // gösterilmez (yalnızca doğrulanmış hadisler arasından seçim yapılır);
    // veri setinde hiç doğrulanmış kayıt kalmazsa (olmaması gereken bir
    // durum) tüm listeye geri dönülür ki uygulama boş kalmasın.
    final verified = _hadisler!.where((h) => h.verified).toList();
    final list = verified.isNotEmpty ? verified : _hadisler!;
    if (list.isEmpty) return _hadithFallback;
    return list[_dayOfYear(date) % list.length];
  }

  @override
  DailyWord wordForDate(DateTime date) {
    final verified = _sozler!.where((s) => s.verified).toList();
    final list = verified.isNotEmpty ? verified : _sozler!;
    if (list.isEmpty) return _wordFallback;
    return list[_dayOfYear(date) % list.length];
  }

  @override
  HistoricalEvent? historicalEventForDate(DateTime date) {
    final matches = historicalEventsForDate(date);
    return matches.isEmpty ? null : matches.first;
  }

  /// O tarihe ait kayıtlı TÜM tarihî olaylar (öncelik sırasına göre: İslam >
  /// Osmanlı > Türkiye > Dünya). Tarihte Bugün detay sayfasında yalnızca en
  /// öncelikli olanı değil, o güne ait bütün olaylar gösterilir.
  List<HistoricalEvent> historicalEventsForDate(DateTime date) {
    final matches = _tarihiOlaylar!.where((e) => e.ay == date.month && e.gun == date.day).toList();
    matches.sort((a, b) => a.oncelik.compareTo(b.oncelik));
    return matches;
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

/// O tarihe ait TÜM tarihî olaylar (Tarihte Bugün detay sayfası için).
/// Kaynak henüz yüklenmediyse boş liste döner.
final historicalEventsForDateProvider = Provider.family<List<HistoricalEvent>, DateTime>((ref, date) {
  final sourceAsync = ref.watch(dailyContentSourceProvider);
  return sourceAsync.whenOrNull(data: (source) => source.historicalEventsForDate(date)) ?? const [];
});
