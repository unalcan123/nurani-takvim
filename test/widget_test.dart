import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tvaap_clean/app.dart';
import 'package:tvaap_clean/features/settings/data/prefs_repository.dart';

void main() {
  testWidgets('app opens on the home shell', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
        ],
        child: const EzanApp(),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
