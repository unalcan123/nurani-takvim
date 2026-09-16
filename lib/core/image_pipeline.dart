import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'platform_file_ops.dart';

/// Slaytta gösterim için fotoğrafın hedef yerleşim biçimi — SAF BİR
/// GÖRÜNTÜLEME TERCİHİDİR, kaydedilen piksel verisini asla etkilemez.
///
/// [contain] fotoğrafın tamamını sade bir arka planla gösterir. [fill] da
/// fotoğrafın tamamını gösterir (kırpma YOK) — yalnızca arkaya aynı
/// fotoğrafın bulanıklaştırılmış, alanı kaplayan bir kopyası eklenir, ki
/// yan/üst-alt boşluklar düz renk yerine bu bulanık kopyayla dolsun. Bkz.
/// `core/slide_photo.dart` → `SlidePhoto`, bu iki modu tek bir ortak
/// widget'ta uygular; önizleme ve gerçek slayt aynı widget'ı kullanır.
enum PhotoFitMode { contain, fill }

/// Bir kullanıcı fotoğrafına slaytta/önizlemede nasıl gösterileceğini
/// (hangi [PhotoFitMode] ile) söyleyen, veriye eşlik eden referans.
/// [ref] platforma göre bir dosya yolu ya da `'base64:...'` / `'assets/...'`
/// önekli bir anahtardır — mevcut `_getImageProvider` sözleşmesiyle aynıdır.
class SlideImageRef {
  final String ref;
  final PhotoFitMode mode;
  const SlideImageRef(this.ref, this.mode);
}

/// Web'de bir kullanıcı fotoğrafı Hive listesinde ya eski biçimde (düz
/// base64 `String` — hiç mod bilgisi yok, [PhotoFitMode.contain] varsayılır)
/// ya da yeni biçimde (`{'data': base64, 'mode': 'contain'|'fill'}` haritası)
/// saklanır. Mod artık salt bir görüntüleme tercihi olduğundan piksel
/// verisinden AYRI saklanır — bkz. `SlidePhoto`.
({Uint8List bytes, PhotoFitMode mode}) decodeWebPhotoEntry(dynamic raw) {
  if (raw is String) {
    return (bytes: base64Decode(raw), mode: PhotoFitMode.contain);
  }
  final map = Map<String, dynamic>.from(raw as Map);
  final bytes = base64Decode(map['data'] as String);
  final mode = PhotoFitMode.values.firstWhere(
    (m) => m.name == map['mode'],
    orElse: () => PhotoFitMode.contain,
  );
  return (bytes: bytes, mode: mode);
}

Map<String, dynamic> encodeWebPhotoEntry(Uint8List bytes, PhotoFitMode mode) =>
    {'data': base64Encode(bytes), 'mode': mode.name};

/// Mobilde kaydedilmiş bir fotoğrafın görüntüleme tercihini okur (bkz.
/// `core/platform_file_ops.dart` → `readPhotoModeSidecar`). Sidecar dosyası
/// yoksa (eski fotoğraflar) [PhotoFitMode.contain] varsayılır.
Future<PhotoFitMode> readMobilePhotoMode(String path) async {
  final raw = await readPhotoModeSidecar(path);
  return PhotoFitMode.values.firstWhere((m) => m.name == raw, orElse: () => PhotoFitMode.contain);
}

/// Kullanıcının slayta eklediği bir fotoğraf desteklenmeyen bir biçimdeyse
/// (ör. HEIC/HEIF) veya bozuksa fırlatılır. Mesaj kullanıcıya doğrudan
/// gösterilebilecek şekilde Türkçe yazılmıştır.
class PhotoProcessingException implements Exception {
  final String message;
  const PhotoProcessingException(this.message);

  @override
  String toString() => message;
}

class ProcessedPhoto {
  final Uint8List jpegBytes;
  final int width;
  final int height;

  const ProcessedPhoto({
    required this.jpegBytes,
    required this.width,
    required this.height,
  });
}

/// Kamera ve galeriden eklenen fotoğrafların ortak işleme hattı.
///
/// Adımlar: EXIF yönünü fiziksel olarak uygula (ve EXIF orientation
/// etiketini temizle, böylece tarayıcı/OS ikinci kez döndürmez) → isteğe
/// bağlı manuel döndürme → gerekiyorsa büyük kenarı indir (KIRPMA YOK) →
/// JPEG olarak kodla. Hem web hem mobil aynı (saf Dart) kodu kullanır.
/// [PhotoFitMode.fill] burada HİÇBİR ETKİ YAPMAZ — o saf bir görüntüleme
/// tercihidir ve ayrıca (metadata olarak) kaydedilir; bkz. [SlideImageRef].
class ImagePipeline {
  ImagePipeline._();

  /// Slaytta gösterim için yeterli olan azami uzun kenar. Bunun üzerindeki
  /// fotoğraflar bu boyuta indirilir; küçük fotoğraflar büyütülmez.
  static const int maxDimension = 1920;
  static const int jpegQuality = 85;

  /// Önizleme için düşük çözünürlüklü, hızlı kodlanan bir sınır.
  static const int previewMaxDimension = 900;

  /// Ham dosya baytlarını çözer ve EXIF yönünü fiziksel olarak uygular.
  /// Web'de de mobilde de aynı senkron `package:image` kodunu çalıştırır.
  /// Desteklenmeyen/bozuk bir dosyada [PhotoProcessingException] fırlatır.
  static img.Image decodeAndOrient(Uint8List bytes) {
    // `image` paketinin format-algılama adımı, bozuk/tanınmayan baytlarda
    // `null` dönmek yerine ham bir istisna (ör. RangeError) fırlatabilir —
    // bunu kullanıcıya gösterilebilir tek bir mesaja çeviriyoruz.
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      throw const PhotoProcessingException(
        'Bu dosya desteklenmeyen bir formatta veya bozuk (yalnızca JPG, '
        'JPEG, PNG, WEBP desteklenir — HEIC/HEIF desteklenmez).',
      );
    }
    return img.bakeOrientation(decoded);
  }

  /// Ağır decode+bake işini mobilde ayrı bir isolate'te çalıştırır (UI'ı
  /// kilitlememek için). Web'de isolate desteklenmediğinden aynı işlevi
  /// doğrudan (senkron) çağırır — çağıran taraf bundan önce bir
  /// mikro-görev arası vererek yükleniyor göstergesinin çizilmesine izin
  /// vermelidir.
  static Future<img.Image> decodeAndOrientAsync(Uint8List bytes) async {
    if (kIsWeb) {
      await Future<void>.delayed(Duration.zero);
      return decodeAndOrient(bytes);
    }
    return compute(decodeAndOrient, bytes);
  }

  /// [oriented] üzerine isteğe bağlı manuel döndürme uygulayıp gerekirse
  /// büyük kenarı [maxDimension]'a indirir (KIRPMA YOK — fotoğrafın tamamı
  /// her zaman korunur) ve JPEG olarak kodlar. CPU-yoğun olduğundan
  /// mobilde isolate'e taşınır.
  static Future<ProcessedPhoto> finalizeAsync(
    img.Image oriented, {
    int quarterTurns = 0,
  }) async {
    final args = _FinalizeArgs(oriented, quarterTurns);
    if (kIsWeb) {
      await Future<void>.delayed(Duration.zero);
      return _finalize(args);
    }
    return compute(_finalize, args);
  }

  static ProcessedPhoto _finalize(_FinalizeArgs args) {
    var image = args.image;
    final turns = args.quarterTurns % 4;
    if (turns != 0) {
      image = img.copyRotate(image, angle: 90 * turns);
    }
    final resized = _resizeContain(image, maxDimension);
    final jpg = img.encodeJpg(resized, quality: jpegQuality);
    return ProcessedPhoto(
      jpegBytes: Uint8List.fromList(jpg),
      width: resized.width,
      height: resized.height,
    );
  }

  /// Önizleme için döndürülmüş, küçük/hızlı kodlanan bir PNG üretir.
  /// Sığdır/doldur seçimi artık salt görüntüleme katmanında
  /// (`SlidePhoto`) uygulandığından burada YOKTUR — bu sayede mod
  /// değiştirmek yeniden kodlama gerektirmez, sadece anında yeniden çizim.
  static Uint8List renderRotatedBytes(img.Image oriented, {int quarterTurns = 0}) {
    var image = oriented;
    final turns = quarterTurns % 4;
    if (turns != 0) {
      image = img.copyRotate(image, angle: 90 * turns);
    }
    final small = _resizeContain(image, previewMaxDimension);
    return Uint8List.fromList(img.encodePng(small));
  }

  static img.Image _resizeContain(img.Image src, int maxDimension) {
    if (src.width <= maxDimension && src.height <= maxDimension) return src;
    if (src.width >= src.height) {
      return img.copyResize(src, width: maxDimension, interpolation: img.Interpolation.linear);
    }
    return img.copyResize(src, height: maxDimension, interpolation: img.Interpolation.linear);
  }
}

class _FinalizeArgs {
  final img.Image image;
  final int quarterTurns;
  const _FinalizeArgs(this.image, this.quarterTurns);
}
