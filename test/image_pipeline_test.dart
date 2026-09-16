import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tvaap_clean/core/image_pipeline.dart';

Uint8List _jpegWithOrientation(int width, int height, int orientation) {
  final image = img.Image(width: width, height: height);
  // Sol-üstü kırmızı, geri kalanı mavi yap — döndürme sonrası hangi köşenin
  // nereye taşındığını doğrulamak için.
  img.fill(image, color: img.ColorRgb8(0, 0, 255));
  img.fillRect(image, x1: 0, y1: 0, x2: (width * 0.2).round(), y2: (height * 0.2).round(),
      color: img.ColorRgb8(255, 0, 0));
  image.exif.imageIfd.orientation = orientation;
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  group('ImagePipeline.decodeAndOrient', () {
    test('EXIF orientation 6 (90° CW) physically rotates and clears the tag', () {
      // 6: kamera 90° saat yönünde tutulmuş demektir, görüntü dosyada
      // yatay (landscape) saklanır ama dikey (portrait) gösterilmelidir.
      final bytes = _jpegWithOrientation(200, 100, 6);
      final oriented = ImagePipeline.decodeAndOrient(bytes);

      // Kaynak 200x100 (landscape) idi; 90° dönünce 100x200 (portrait) olmalı.
      expect(oriented.width, 100);
      expect(oriented.height, 200);

      // Yeniden kodlanıp okunduğunda tarayıcının ikinci kez döndürmemesi
      // için orientation etiketi temizlenmiş/varsayılan olmalı.
      final reEncoded = img.encodeJpg(oriented);
      final reDecoded = img.decodeImage(reEncoded)!;
      expect(
        reDecoded.exif.imageIfd.hasOrientation && reDecoded.exif.imageIfd.orientation != 1,
        isFalse,
      );
    });

    test('EXIF orientation 1 (normal) leaves pixels untouched', () {
      final bytes = _jpegWithOrientation(200, 100, 1);
      final oriented = ImagePipeline.decodeAndOrient(bytes);
      expect(oriented.width, 200);
      expect(oriented.height, 100);
    });

    test('throws PhotoProcessingException for undecodable bytes', () {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(
        () => ImagePipeline.decodeAndOrient(garbage),
        throwsA(isA<PhotoProcessingException>()),
      );
    });
  });

  group('ImagePipeline.finalizeAsync — never crops, regardless of aspect', () {
    // `mode` (contain/"arka planla doldur") is purely a display-time
    // preference now (see SlidePhoto) — finalizeAsync has no mode
    // parameter at all and must never crop a single pixel out of the
    // photo, for any aspect ratio.
    test('preserves full aspect ratio and never upscales small photos', () async {
      final small = img.Image(width: 400, height: 300);
      img.fill(small, color: img.ColorRgb8(10, 20, 30));
      final processed = await ImagePipeline.finalizeAsync(small);
      expect(processed.width, 400);
      expect(processed.height, 300);
    });

    test('downscales oversized photos without cropping (aspect preserved)', () async {
      final big = img.Image(width: 4000, height: 2000); // 2:1
      img.fill(big, color: img.ColorRgb8(10, 20, 30));
      final processed = await ImagePipeline.finalizeAsync(big);
      expect(processed.width <= ImagePipeline.maxDimension, isTrue);
      expect(processed.height <= ImagePipeline.maxDimension, isTrue);
      // En boy oranı korunmalı (2:1)
      expect((processed.width / processed.height - 2.0).abs() < 0.02, isTrue);
    });

    test('fully preserves a portrait (vertical) photo — no crop to a 16:9 box', () async {
      final portrait = img.Image(width: 1200, height: 3000); // dikey, dar
      img.fill(portrait, color: img.ColorRgb8(10, 20, 30));
      final processed = await ImagePipeline.finalizeAsync(portrait);
      // Uzun kenar (height) maxDimension'a inmeli, oran korunmalı — kırpılmamalı.
      expect(processed.height, ImagePipeline.maxDimension);
      expect((processed.width / processed.height - 1200 / 3000).abs() < 0.01, isTrue);
    });

    test('a very wide panorama is preserved uncropped too', () async {
      final wide = img.Image(width: 3000, height: 800); // ~3.75:1
      img.fill(wide, color: img.ColorRgb8(10, 20, 30));
      final processed = await ImagePipeline.finalizeAsync(wide);
      expect(processed.width, ImagePipeline.maxDimension);
      expect((processed.width / processed.height - 3000 / 800).abs() < 0.01, isTrue);
    });

    test('manual quarter-turn rotation is applied on top of EXIF orientation', () async {
      final image = img.Image(width: 300, height: 150);
      img.fill(image, color: img.ColorRgb8(10, 20, 30));
      final processed = await ImagePipeline.finalizeAsync(image, quarterTurns: 1);
      // 300x150 saat yönünde 90° dönünce 150x300 olmalı.
      expect(processed.width, 150);
      expect(processed.height, 300);
    });
  });

  group('web photo entry encode/decode (per-photo display mode metadata)', () {
    test('round-trips bytes and mode through encode/decode', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final entry = encodeWebPhotoEntry(bytes, PhotoFitMode.fill);
      final decoded = decodeWebPhotoEntry(entry);
      expect(decoded.bytes, bytes);
      expect(decoded.mode, PhotoFitMode.fill);
    });

    test('a legacy plain-base64-string entry decodes as contain (no destructive crop to recover)', () {
      final bytes = Uint8List.fromList([9, 8, 7]);
      final legacy = base64Encode(bytes);
      final decoded = decodeWebPhotoEntry(legacy);
      expect(decoded.bytes, bytes);
      expect(decoded.mode, PhotoFitMode.contain);
    });

    test('an entry with an unrecognized mode string falls back to contain', () {
      final bytes = Uint8List.fromList([1, 1, 1]);
      final decoded = decodeWebPhotoEntry({'data': base64Encode(bytes), 'mode': 'nonsense'});
      expect(decoded.mode, PhotoFitMode.contain);
    });
  });
}
