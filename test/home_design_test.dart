import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvaap_clean/features/dashboard/presentation/app_shell.dart';
import 'package:tvaap_clean/theme.dart';
import 'responsive_layout_test.dart' show layoutEnvironment, resize, showLayout;

Future<void> loadScreenshotFonts() async {
  final dir = Platform.environment['NURANI_FONT_DIR'];
  if (dir == null) return;
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  for (final entry in {'Roboto': ['arial.ttf', 'arialbd.ttf'],
      'monospace': ['consola.ttf', 'consolab.ttf']}.entries) {
    final loader = FontLoader(entry.key);
    for (final file in entry.value) {
      loader.addFont(File('$dir/$file').readAsBytes().then((b) => ByteData.sublistView(b)));
    }
    await loader.load();
  }
}

void main() {
  for (final size in [const Size(1280, 800), const Size(1920, 1080)]) {
    testWidgets('home visual bounds and stable digits at $size', (tester) async {
      resize(tester, size);
      await tester.runAsync(loadScreenshotFonts);
      var now = DateTime(2026, 9, 11, 14, 17, 42);
      final env = await layoutEnvironment(tester, nowSource: () => now);
      final boundaryKey = GlobalKey();
      await showLayout(tester, env.container,
        RepaintBoundary(key: boundaryKey, child: const AppShell()));
      await tester.runAsync(() async {
        for (final element in find.descendant(
            of: find.byKey(const ValueKey('home-slideshow')),
            matching: find.byType(Image)).evaluate()) {
          await precacheImage((element.widget as Image).image, element);
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('İkindi Vaktine'), findsOneWidget);
      final active = tester.widget<Container>(find.byKey(const ValueKey('prayer-cell-Öğle')));
      expect((active.decoration as BoxDecoration).border, Border.all(color: dashboardAccentGold, width: 3));
      final positions = [for (var i = 0; i < 8; i++)
        tester.getCenter(find.byKey(ValueKey('countdown-digit-$i')))];
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      for (var i = 0; i < 8; i++) {
        expect(tester.getCenter(find.byKey(ValueKey('countdown-digit-$i'))), positions[i]);
      }
      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.byKey(const ValueKey('countdown-digit-0')));
      expect(text.style!.fontSize, greaterThan(size.width == 1920 ? 80 : 52));
      if (Platform.environment['NURANI_SCREENSHOTS'] == '1') {
        await tester.runAsync(() async {
          final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('docs/screenshots/home-${size.width.toInt()}x${size.height.toInt()}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
