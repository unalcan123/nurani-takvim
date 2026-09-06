import 'dart:convert';

import 'package:flutter/services.dart';

import 'adhan_settings.dart';

class WorldAdhan {
  final String assetPath;
  final String title;

  const WorldAdhan({required this.assetPath, required this.title});
}

class AdhanLibraryService {
  static const String worldAdhanPrefix = 'assets/audio/adhan/dunya_ezan/';

  Future<List<WorldAdhan>> loadWorldAdhans() async {
    final manifestRaw = await rootBundle.loadString('AssetManifest.json');
    final manifest = json.decode(manifestRaw) as Map<String, dynamic>;
    final items = manifest.keys
        .where((path) => path.startsWith(worldAdhanPrefix))
        .where((path) => path.toLowerCase().endsWith('.mp3'))
        .map((path) => WorldAdhan(assetPath: path, title: cleanAdhanTitle(path)))
        .toList();
    items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return items;
  }
}
