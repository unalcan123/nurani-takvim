import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuranMoshaf {
  final int id;
  final String name;
  final String server;
  final List<int> surahNumbers;

  const QuranMoshaf({
    required this.id,
    required this.name,
    required this.server,
    required this.surahNumbers,
  });

  factory QuranMoshaf.fromJson(Map<String, dynamic> json) => QuranMoshaf(
        id: json['id'] as int,
        name: json['name'] as String,
        server: json['server'] as String,
        surahNumbers: (json['surah_list'] as String)
            .split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => int.parse(s.trim()))
            .toList(),
      );

  /// [sureNo] için oynatılabilir doğrudan mp3 URL'si (2 basamağa değil 3
  /// basamağa sıfırla doldurulmuş sûre numarası ile, mp3quran.net kuralı).
  String surahUrl(int sureNo) =>
      '$server${sureNo.toString().padLeft(3, '0')}.mp3';
}

class QuranReciter {
  final int id;
  final String name;
  final List<QuranMoshaf> moshaflar;

  const QuranReciter({
    required this.id,
    required this.name,
    required this.moshaflar,
  });

  factory QuranReciter.fromJson(Map<String, dynamic> json) => QuranReciter(
        id: json['id'] as int,
        name: json['name'] as String,
        moshaflar: (json['moshaf'] as List)
            .map((m) => QuranMoshaf.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
      );
}

/// mp3quran.net'in genel API'sinden hafız/okuyucu listesini çeker. Sonuç,
/// tekrar tekrar ağ isteği atmamak için `SharedPreferences`'ta ham JSON
/// olarak önbelleğe alınır (TTL: 7 gün). Ağ hatası olursa, varsa son bilinen
/// önbellek döner; hiç önbellek yoksa hata yukarı fırlatılır (UI yeniden
/// deneme göstermeli).
class Mp3QuranReciterService {
  // mp3quran.net Türkçe desteklemiyor (yalnızca "ar"/"eng" kabul ediyor);
  // Arapça yazıyla okunamayacağı için Latin harfli İngilizce çeviri adları
  // kullanılıyor (ör. "Yasser Salamah").
  static const _apiUrl = 'https://www.mp3quran.net/api/v3/reciters?language=eng';
  static const _cacheKey = 'quran_reciters_cache_v2';
  static const _cacheTimeKey = 'quran_reciters_cache_time_v2';
  static const _ttl = Duration(days: 7);

  List<QuranReciter> _parse(String raw) {
    final decoded = json.decode(raw) as Map<String, dynamic>;
    final list = decoded['reciters'] as List;
    return list
        .map((r) => QuranReciter.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<List<QuranReciter>> loadReciters({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedRaw = prefs.getString(_cacheKey);
    final cachedTimeMs = prefs.getInt(_cacheTimeKey);

    if (!forceRefresh && cachedRaw != null && cachedTimeMs != null) {
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(cachedTimeMs),
      );
      if (age < _ttl) return _parse(cachedRaw);
    }

    try {
      final dio = Dio();
      final response = await dio.get<String>(
        _apiUrl,
        options: Options(responseType: ResponseType.plain),
      );
      final raw = response.data!;
      await prefs.setString(_cacheKey, raw);
      await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
      return _parse(raw);
    } catch (e) {
      if (cachedRaw != null) return _parse(cachedRaw);
      rethrow;
    }
  }
}
