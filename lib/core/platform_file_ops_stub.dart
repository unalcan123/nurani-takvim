import 'dart:typed_data';

import 'package:flutter/widgets.dart';

Future<Uint8List> readLocalFileBytes(String path) {
  throw UnsupportedError('Local files are not available on this platform.');
}

Future<String> saveUserImageBytes(String category, Uint8List bytes) {
  throw UnsupportedError('Local files are not available on this platform.');
}

Future<void> overwriteUserImageBytes(String path, Uint8List bytes) {
  throw UnsupportedError('Local files are not available on this platform.');
}

Future<List<String>> listUserImagePaths(String category) async => [];

Future<void> deleteLocalFile(String path) async {}

ImageProvider localFileImageProvider(String path) {
  throw UnsupportedError('Local files are not available on this platform.');
}

/// Web'de dosya sistemi yoktur; çağıran taraf bu durumda başka bir oynatma
/// yoluna (ör. bellekteki baytlardan `data:` URI) düşmelidir.
Future<String?> saveMediaBytes(
  String category,
  String fileName,
  Uint8List bytes,
) async =>
    null;

Future<void> deleteMediaBytes(String category, String fileName) async {}
