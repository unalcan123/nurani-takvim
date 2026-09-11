import 'dart:convert';

import 'package:flutter/services.dart';

class SurahInfo {
  final int sureNo;
  final String arabicName;
  final String turkishName;
  final int ayahCount;

  const SurahInfo({
    required this.sureNo,
    required this.arabicName,
    required this.turkishName,
    required this.ayahCount,
  });

  factory SurahInfo.fromJson(Map<String, dynamic> json) => SurahInfo(
        sureNo: json['sureNo'] as int,
        arabicName: json['arabicName'] as String,
        turkishName: json['turkishName'] as String,
        ayahCount: json['ayahCount'] as int,
      );
}

/// `assets/data/surah_list.json` içindeki sabit 114 sûrelik listeyi okur
/// (Arapça + Türkçe adlar, âyet sayıları). Değişmeyen sabit veri olduğu için
/// bellekte önbelleğe alınır.
class SurahListService {
  static List<SurahInfo>? _cached;

  Future<List<SurahInfo>> loadSurahs() async {
    final cached = _cached;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/data/surah_list.json');
    final decoded = json.decode(raw) as Map<String, dynamic>;
    final list = (decoded['entries'] as List)
        .map((e) => SurahInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    _cached = list;
    return list;
  }
}
