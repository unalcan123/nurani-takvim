import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Slaytta gösterime hazırlanmış fotoğrafın hedef görüntüleme biçimi.
///
/// [contain] fotoğrafın tamamını korur (varsayılan) — hiçbir kırpma
/// yapılmaz, sadece gerekiyorsa büyük kenarı [ImagePipeline.maxDimension]
/// değerine indirir. [fill] ise 16:9 bir kutuyu doldurmak için merkezden
/// kırpar (kullanıcı açıkça seçtiğinde kullanılır).
enum PhotoFitMode { contain, fill }

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
/// bağlı manuel döndürme → seçilen moda göre boyutlandır → JPEG olarak
/// kodla. Hem web hem mobil aynı (saf Dart) kodu kullanır.
class ImagePipeline {
  ImagePipeline._();

  /// Slaytta gösterim için yeterli olan azami uzun kenar. Bunun üzerindeki
  /// fotoğraflar bu boyuta indirilir; küçük fotoğraflar büyütülmez.
  static const int maxDimension = 1920;
  static const int fillTargetWidth = 1920;
  static const int fillTargetHeight = 1080;
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

  /// [oriented] üzerine isteğe bağlı manuel döndürme ve seçilen fit modunu
  /// uygulayıp JPEG olarak kodlar. Bu adım da CPU-yoğun olduğundan mobilde
  /// isolate'e taşınır.
  static Future<ProcessedPhoto> finalizeAsync(
    img.Image oriented, {
    required PhotoFitMode mode,
    int quarterTurns = 0,
  }) async {
    final args = _FinalizeArgs(oriented, mode, quarterTurns);
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
    final resized = args.mode == PhotoFitMode.fill
        ? _resizeCoverAndCrop(image, targetW: fillTargetWidth, targetH: fillTargetHeight)
        : _resizeContain(image, maxDimension);
    final jpg = img.encodeJpg(resized, quality: jpegQuality);
    return ProcessedPhoto(
      jpegBytes: Uint8List.fromList(jpg),
      width: resized.width,
      height: resized.height,
    );
  }

  /// Önizleme için küçük, hızlı bir PNG üretir (kalite kaybı önemsiz,
  /// önizleme her ayar değişikliğinde yeniden çizilir).
  static Uint8List renderPreview(
    img.Image oriented, {
    required PhotoFitMode mode,
    int quarterTurns = 0,
  }) {
    var image = oriented;
    final turns = quarterTurns % 4;
    if (turns != 0) {
      image = img.copyRotate(image, angle: 90 * turns);
    }
    final small = _resizeContain(image, previewMaxDimension);
    final resized = mode == PhotoFitMode.fill
        ? _resizeCoverAndCrop(
            small,
            targetW: fillTargetWidth * previewMaxDimension ~/ fillTargetWidth,
            targetH: fillTargetHeight * previewMaxDimension ~/ fillTargetWidth,
          )
        : small;
    return Uint8List.fromList(img.encodePng(resized));
  }

  static img.Image _resizeContain(img.Image src, int maxDimension) {
    if (src.width <= maxDimension && src.height <= maxDimension) return src;
    if (src.width >= src.height) {
      return img.copyResize(src, width: maxDimension, interpolation: img.Interpolation.linear);
    }
    return img.copyResize(src, height: maxDimension, interpolation: img.Interpolation.linear);
  }

  static img.Image _resizeCoverAndCrop(
    img.Image src, {
    required int targetW,
    required int targetH,
  }) {
    final double srcAspect = src.width / src.height;
    final double targetAspect = targetW / targetH;

    img.Image resized;
    if (srcAspect > targetAspect) {
      resized = img.copyResize(src, height: targetH, interpolation: img.Interpolation.linear);
    } else {
      resized = img.copyResize(src, width: targetW, interpolation: img.Interpolation.linear);
    }

    final x = ((resized.width - targetW) ~/ 2).clamp(0, (resized.width - targetW).clamp(0, resized.width));
    final y = ((resized.height - targetH) ~/ 2).clamp(0, (resized.height - targetH).clamp(0, resized.height));

    return img.copyCrop(
      resized,
      x: x,
      y: y,
      width: targetW.clamp(1, resized.width),
      height: targetH.clamp(1, resized.height),
    );
  }
}

class _FinalizeArgs {
  final img.Image image;
  final PhotoFitMode mode;
  final int quarterTurns;
  const _FinalizeArgs(this.image, this.mode, this.quarterTurns);
}
