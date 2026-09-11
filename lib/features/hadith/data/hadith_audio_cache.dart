import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/platform_file_ops.dart';
import 'hadith_audio_library.dart';

/// [HadithAudioEntry] ses baytlarını cihaza indirip Hive'da (mobil/masaüstü:
/// yerel kutu, Web: IndexedDB) önbelleğe alır — bkz. `EzanDownloadCache` ile
/// aynı desen. Ek olarak, dosya sistemi olan platformlarda indirilen baytları
/// bir kez diske yazıp oynatma için dosya yolu döner: bu dosyalar (birkaç
/// MB - onlarca MB) `data:` URI'ye çevrilip bellekte tutulamayacak kadar
/// büyük olabilir (ezan klipleri gibi küçük değil).
class HadithAudioCache {
  static const boxName = 'hadith_audio_cache';

  Future<Box> _box() => Hive.openBox(boxName);

  Future<Uint8List?> cachedBytes(HadithAudioEntry entry) async {
    final box = await _box();
    final raw = box.get(entry.id);
    if (raw == null) return null;
    return Uint8List.fromList(List<int>.from(raw as List));
  }

  Future<bool> isCached(HadithAudioEntry entry) async {
    final box = await _box();
    return box.containsKey(entry.id);
  }

  /// Baytları indirir (zaten önbellekteyse doğrudan onları döner) ve
  /// önbelleğe kaydeder. [onProgress] 0.0-1.0 arası ilerleme bildirir.
  Future<Uint8List> ensureDownloaded(
    HadithAudioEntry entry, {
    required String baseUrl,
    void Function(double progress)? onProgress,
  }) async {
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

  /// Bu kayıt için oynatılabilir bir yerel dosya yolu döner (önbellekte
  /// baytlar varsa ve platformda dosya sistemi varsa), aksi halde `null`.
  /// `null` dönerse çağıran taraf akıştan (network) doğrudan çalmalıdır.
  Future<String?> cachedFilePath(HadithAudioEntry entry) async {
    final bytes = await cachedBytes(entry);
    if (bytes == null) return null;
    return saveMediaBytes('hadith_audio', '${entry.id}.mp3', bytes);
  }

  Future<void> remove(HadithAudioEntry entry) async {
    final box = await _box();
    await box.delete(entry.id);
    await deleteMediaBytes('hadith_audio', '${entry.id}.mp3');
  }
}
