import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// İndirilebilir ezan kütüphanesindeki bir kaydın hangi vakit grubuna ait
/// olduğu: sabah (fecr) ya da diğer dört vakit (normal).
enum EzanLibraryCategory {
  fajr,
  normal;

  static EzanLibraryCategory fromStorage(String value) =>
      value == 'fajr' ? EzanLibraryCategory.fajr : EzanLibraryCategory.normal;
}

/// [EzanLibraryEntry.source] — kayıt uygulamayla birlikte gelen bir asset mi
/// (indirme gerekmez), yoksa GitHub Release üzerinden indirilmesi gereken
/// uzak bir dosya mı.
enum EzanLibrarySource { asset, remote }

class EzanLibraryEntry {
  final String id;
  final String title;
  final EzanLibraryCategory category;
  final EzanLibrarySource source;

  /// Yalnızca [source] asset ise doludur (bundled Flutter asset yolu).
  final String? assetPath;

  /// Yalnızca [source] remote ise doludur (Release asset dosya adı; indirme
  /// URL'si [EzanLibraryManifest.baseUrl] ile birleştirilerek kurulur).
  final String? fileName;

  const EzanLibraryEntry({
    required this.id,
    required this.title,
    required this.category,
    required this.source,
    this.assetPath,
    this.fileName,
  });

  factory EzanLibraryEntry.fromJson(Map<String, dynamic> json) {
    final source =
        json['source'] == 'asset' ? EzanLibrarySource.asset : EzanLibrarySource.remote;
    return EzanLibraryEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      category: EzanLibraryCategory.fromStorage(json['category'] as String),
      source: source,
      assetPath: json['assetPath'] as String?,
      fileName: json['fileName'] as String?,
    );
  }

  bool get isFajr => category == EzanLibraryCategory.fajr;
}

class EzanLibraryManifest {
  final String baseUrl;
  final List<EzanLibraryEntry> entries;

  const EzanLibraryManifest({required this.baseUrl, required this.entries});

  EzanLibraryEntry? byId(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  List<EzanLibraryEntry> get fajrEntries =>
      entries.where((e) => e.category == EzanLibraryCategory.fajr).toList();

  List<EzanLibraryEntry> get normalEntries =>
      entries.where((e) => e.category == EzanLibraryCategory.normal).toList();
}

/// `assets/data/ezan_library_manifest.json` dosyasını okuyup ayrıştırır.
/// Sonuç süreç boyunca değişmediği için bellekte önbelleğe alınır.
class EzanLibraryService {
  static EzanLibraryManifest? _cached;

  Future<EzanLibraryManifest> loadManifest() async {
    final cached = _cached;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(
      'assets/data/ezan_library_manifest.json',
    );
    final decoded = json.decode(raw) as Map<String, dynamic>;
    final manifest = EzanLibraryManifest(
      baseUrl: decoded['baseUrl'] as String,
      entries: (decoded['entries'] as List)
          .map((e) => EzanLibraryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
    _cached = manifest;
    return manifest;
  }

  Future<EzanLibraryEntry?> findById(String id) async {
    final manifest = await loadManifest();
    return manifest.byId(id);
  }
}

/// Uzak (remote) ezan kütüphanesi dosyalarının baytlarını cihaza indirip
/// Hive'da (mobil/masaüstünde yerel kutu, Web'de IndexedDB) önbelleğe alır —
/// bkz. [CustomAudioStore] ile aynı desen, Web dahil tüm platformlarda çalışır.
/// Bir kez indirilen dosya tekrar indirilmez; ağ olmadan da çalınabilir.
class EzanDownloadCache {
  static const boxName = 'ezan_library_cache';

  Future<Box> _box() => Hive.openBox(boxName);

  Future<Uint8List?> cachedBytes(EzanLibraryEntry entry) async {
    final box = await _box();
    final raw = box.get(entry.id);
    if (raw == null) return null;
    return Uint8List.fromList(List<int>.from(raw as List));
  }

  Future<bool> isCached(EzanLibraryEntry entry) async {
    if (entry.source != EzanLibrarySource.remote) return true;
    final box = await _box();
    return box.containsKey(entry.id);
  }

  /// Baytları indirir (zaten önbellekteyse doğrudan onları döner) ve
  /// önbelleğe kaydeder. [onProgress] 0.0-1.0 arası ilerleme bildirir.
  Future<Uint8List> ensureDownloaded(
    EzanLibraryEntry entry, {
    String baseUrl = '',
    void Function(double progress)? onProgress,
  }) async {
    if (entry.source != EzanLibrarySource.remote) {
      throw StateError('ensureDownloaded yalnızca remote kayıtlar içindir: ${entry.id}');
    }
    final existing = await cachedBytes(entry);
    if (existing != null) return existing;

    final url = Uri.encodeFull('$baseUrl${entry.fileName}');
    final dio = Dio();
    final response = await dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      },
    );
    final bytes = Uint8List.fromList(response.data ?? const []);
    final box = await _box();
    await box.put(entry.id, bytes);
    return bytes;
  }

  Future<void> remove(EzanLibraryEntry entry) async {
    final box = await _box();
    await box.delete(entry.id);
  }
}
