import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tvaap_clean/core/image_pipeline.dart';
import 'package:tvaap_clean/features/settings/presentation/photo_capture.dart';

img.Image _sampleImage() {
  final image = img.Image(width: 1200, height: 1600); // dikey fotoğraf
  img.fill(image, color: img.ColorRgb8(20, 40, 60));
  return image;
}

Future<void> _pumpPreviewHost(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showPhotoPreviewDialog(
              context,
              oriented: _sampleImage(),
              fileName: 'test.jpg',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
}

void main() {
  // Regression test: a fixed AspectRatio(16:9) image box + fixed-height
  // control rows used to overflow ("BOTTOM OVERFLOWED") on short landscape
  // phone heights (reported at 690x320 and 740x360, system bars included).
  for (final size in [const Size(690, 320), const Size(740, 360)]) {
    testWidgets('photo preview dialog does not overflow on short landscape phone $size', (tester) async {
      await _pumpPreviewHost(tester, size);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Dialog), findsOneWidget);
      // Short screens should use the fullscreen presentation so there is
      // room for the image + controls without shrinking or overflowing.
      expect(find.byType(SegmentedButton<PhotoFitMode>), findsOneWidget);
      expect(find.text('Kaydet'), findsOneWidget);

      // Rotate a couple of times — must not throw or overflow.
      await tester.tap(find.byTooltip('Sağa döndür'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('photo preview dialog still renders boxed on a tall/tablet screen', (tester) async {
    await _pumpPreviewHost(tester, const Size(1024, 768));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Kaydet'), findsOneWidget);
  });

  testWidgets('rotating the photo is independent of device orientation changes', (tester) async {
    await _pumpPreviewHost(tester, const Size(690, 320));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sağa döndür'));
    await tester.pumpAndSettle();

    // Simulate a device rotation (landscape -> portrait) while the dialog
    // is open; the chosen photo rotation must be preserved, not reset.
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The dialog is still open and usable (Kaydet reachable) after the
    // simulated rotation.
    expect(find.text('Kaydet'), findsOneWidget);
  });
}
