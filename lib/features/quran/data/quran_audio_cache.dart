import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/platform_file_ops.dart';

/// Bir hafızın belirli bir sûre kaydını çevrimdışı için önbelleğe alır.
/// Aynı desen: bkz. `HadithAudioCache`/`EzanDownloadCache`. Kayıt kimliği
/// çağıran taraftan gelir (reciter+moshaf+sureNo birleşiminden üretilir),
/// bu sınıf yalnızca baytların indirilmesi/önbelleklenmesinden sorumludur.
class QuranAudioCache {
  static const boxName = 'quran_audio_cache';

  Future<Box> _box() => Hive.openBox(boxName);

  Future<Uint8List?> cachedBytes(String trackId) async {
    final box = await _box();
    final raw = box.get(trackId);
    if (raw == null) return null;
    return Uint8List.fromList(List<int>.from(raw as List));
  }

  Future<bool> isCached(String trackId) async {
    final box = await _box();
    return box.containsKey(trackId);
  }

  Future<Uint8List> ensureDownloaded(
    String trackId,
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final existing = await cachedBytes(trackId);
    if (existing != null) return existing;

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
    await box.put(trackId, bytes);
    return bytes;
  }

  /// Bu kayıt için oynatılabilir bir yerel dosya yolu döner (önbellekte
  /// baytlar varsa ve platformda dosya sistemi varsa), aksi halde `null`.
  Future<String?> cachedFilePath(String trackId) async {
    final bytes = await cachedBytes(trackId);
    if (bytes == null) return null;
    return saveMediaBytes('quran_audio', '$trackId.mp3', bytes);
  }

  Future<void> remove(String trackId) async {
    final box = await _box();
    await box.delete(trackId);
    await deleteMediaBytes('quran_audio', '$trackId.mp3');
  }
}
