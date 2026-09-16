import 'dart:ui';

import 'package:flutter/material.dart';

import 'image_pipeline.dart';

/// Bir kullanıcı/asset fotoğrafını, seçilen [PhotoFitMode]'a göre gösteren
/// TEK ortak widget. Hem fotoğraf önizleme/düzenleme diyaloğu
/// (`photo_capture.dart`) hem de gerçek slayt (`SlaytWidget`) bunu
/// kullanır — böylece "önizlemede göründüğü gibi kaydedilir" garantisi
/// koddan gelir, iki ayrı yerde tutarsız yeniden uygulamadan değil.
///
/// [PhotoFitMode.contain]: fotoğrafın tamamı, düz [backgroundColor] üstünde.
/// [PhotoFitMode.fill]: "Arka Planla Doldur" — iki katman: arkada aynı
/// fotoğrafın alanı BoxFit.cover ile kaplayan, bulanıklaştırılmış ve hafif
/// karartılmış düşük-çözünürlüklü bir kopyası; önde fotoğrafın TAMAMI
/// BoxFit.contain ile (kırpma/zoom/esnetme YOK) — iki mod arasında
/// öndeki görüntünün boyutu/konumu değişmez, yalnızca arka plan katmanı
/// eklenir/kaldırılır.
class SlidePhoto extends StatelessWidget {
  const SlidePhoto({
    super.key,
    required this.image,
    required this.mode,
    this.backgroundColor = Colors.black,
  });

  final ImageProvider image;
  final PhotoFitMode mode;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final foreground = Image(
      image: image,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) =>
          const Center(child: Icon(Icons.image_not_supported_outlined, color: Colors.grey)),
    );

    if (mode == PhotoFitMode.contain) {
      return ColoredBox(color: backgroundColor, child: foreground);
    }

    return ColoredBox(
      color: backgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Arka plan: aynı fotoğrafın alanı kaplayan (cover), bulanık ve
          // hafif karartılmış düşük-çözünürlüklü kopyası. `ResizeImage`
          // büyük fotoğraflarda bulanıklaştırmadan önce küçük bir kopya
          // decode eder — hem hızlı hem de blur zaten ayrıntıyı gizlediği
          // için görsel kayıp yaratmaz. Bu katman salt görüntüleme
          // sırasında üretilir; kaydedilen dosyaya asla yazılmaz.
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28, tileMode: TileMode.decal),
              child: Image(
                image: ResizeImage(image, width: 160),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Container(color: Colors.black.withValues(alpha: 0.32)),
          // Ön plan: fotoğrafın tamamı, contain modundakiyle birebir aynı
          // widget — boyut/konum yalnızca bu Stack'in kendi boyutuna bağlı,
          // moddan bağımsızdır.
          foreground,
        ],
      ),
    );
  }
}
