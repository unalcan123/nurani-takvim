import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tvaap_clean/core/image_pipeline.dart';
import 'package:tvaap_clean/core/slide_photo.dart';

ImageProvider _portraitProvider() {
  final image = img.Image(width: 400, height: 800);
  img.fill(image, color: img.ColorRgb8(30, 60, 90));
  return MemoryImage(Uint8List.fromList(img.encodePng(image)));
}

void main() {
  testWidgets('contain mode: no blur/background layer, single Image, foreground unclipped', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 400,
        height: 300,
        child: SlidePhoto(image: _portraitProvider(), mode: PhotoFitMode.contain, backgroundColor: Colors.black),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(Image), findsOneWidget);

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);
  });

  testWidgets('fill mode ("Arka Planla Doldur"): blurred cover background + contain foreground', (tester) async {
    final provider = _portraitProvider();
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 400,
        height: 300,
        child: SlidePhoto(image: provider, mode: PhotoFitMode.fill, backgroundColor: Colors.black),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Arka plan: bulanıklaştırma katmanı var.
    expect(find.byType(ImageFiltered), findsOneWidget);
    // İki katman: arka plan (cover, düşük çözünürlük) + ön plan (contain, tam çözünürlük).
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images.length, 2);
    expect(images.where((i) => i.fit == BoxFit.cover).length, 1);
    expect(images.where((i) => i.fit == BoxFit.contain).length, 1);
  });

  testWidgets('foreground image box is identical in both modes — only the background layer differs', (tester) async {
    final provider = _portraitProvider();

    Future<Rect> foregroundRect(PhotoFitMode mode) async {
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: SlidePhoto(image: provider, mode: mode, backgroundColor: Colors.black),
        ),
      ));
      await tester.pumpAndSettle();
      // The contain-fit Image is always the last Image in the tree (foreground painted on top).
      final containImages = find.byWidgetPredicate((w) => w is Image && w.fit == BoxFit.contain);
      return tester.getRect(containImages.first);
    }

    final containRect = await foregroundRect(PhotoFitMode.contain);
    final fillRect = await foregroundRect(PhotoFitMode.fill);

    expect(containRect, fillRect);
  });
}
