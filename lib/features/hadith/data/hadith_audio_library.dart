import 'dart:convert';

import 'package:flutter/services.dart';

/// Riyazüs Salihin (Hayri Küçükdeniz okuyuşu) kütüphanesindeki tek bir ses
/// kaydı. Tüm kayıtlar archive.org üzerinden yayınlanır (uygulamayla
/// gömülmez), bkz. [HadithAudioManifest.baseUrl].
class HadithAudioEntry {
  final String id;
  final int order;
  final String title;
  final String fileName;
  final int sizeBytes;

  const HadithAudioEntry({
    required this.id,
    required this.order,
    required this.title,
    required this.fileName,
    required this.sizeBytes,
  });

  factory HadithAudioEntry.fromJson(Map<String, dynamic> json) =>
      HadithAudioEntry(
        id: json['id'] as String,
        order: json['order'] as int,
        title: json['title'] as String,
        fileName: json['fileName'] as String,
        sizeBytes: json['sizeBytes'] as int,
      );

  double get sizeMb => sizeBytes / (1024 * 1024);
}

class HadithAudioManifest {
  final String source;
  final String narrator;
  final String baseUrl;
  final List<HadithAudioEntry> entries;

  const HadithAudioManifest({
    required this.source,
    required this.narrator,
    required this.baseUrl,
    required this.entries,
  });

  HadithAudioEntry? byId(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }
}

/// `assets/data/hadith_library_manifest.json` dosyasını okuyup ayrıştırır.
/// Sonuç süreç boyunca değişmediği için bellekte önbelleğe alınır.
class HadithAudioLibraryService {
  static HadithAudioManifest? _cached;

  Future<HadithAudioManifest> loadManifest() async {
    final cached = _cached;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(
      'assets/data/hadith_library_manifest.json',
    );
    final decoded = json.decode(raw) as Map<String, dynamic>;
    final manifest = HadithAudioManifest(
      source: decoded['source'] as String,
      narrator: decoded['narrator'] as String,
      baseUrl: decoded['baseUrl'] as String,
      entries: (decoded['entries'] as List)
          .map((e) => HadithAudioEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
    _cached = manifest;
    return manifest;
  }

  Future<HadithAudioEntry?> findById(String id) async {
    final manifest = await loadManifest();
    return manifest.byId(id);
  }
}
