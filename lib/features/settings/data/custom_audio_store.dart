import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

/// Kullanıcının cihazından seçtiği, bir namaz vaktine atanabilecek özel bir
/// ses dosyası. Baytlar doğrudan saklanır (localStorage'da base64 metin
/// olarak DEĞİL) — bkz. [CustomAudioStore].
class CustomAudioFile {
  final String id;
  final String fileName;
  final Uint8List bytes;
  final DateTime addedAt;

  const CustomAudioFile({
    required this.id,
    required this.fileName,
    required this.bytes,
    required this.addedAt,
  });

  int get sizeBytes => bytes.length;

  String get extension {
    final dot = fileName.lastIndexOf('.');
    return dot == -1 ? '' : fileName.substring(dot + 1).toLowerCase();
  }

  String get mimeType => switch (extension) {
        'mp3' => 'audio/mpeg',
        'm4a' => 'audio/mp4',
        'wav' => 'audio/wav',
        'ogg' => 'audio/ogg',
        _ => 'audio/mpeg',
      };

  Map<String, dynamic> _toMap() => {
        'id': id,
        'fileName': fileName,
        'bytes': bytes,
        'addedAt': addedAt.millisecondsSinceEpoch,
      };

  static CustomAudioFile _fromMap(Map map) => CustomAudioFile(
        id: map['id'] as String,
        fileName: map['fileName'] as String,
        bytes: Uint8List.fromList(List<int>.from(map['bytes'] as List)),
        addedAt: DateTime.fromMillisecondsSinceEpoch(map['addedAt'] as int),
      );
}

/// Kullanıcının namaz vakitleri için seçtiği özel ses dosyalarını saklar.
///
/// Hive kullanılır: Flutter Web'de Hive otomatik olarak IndexedDB'yi arka uç
/// olarak kullanır (localStorage'a büyük base64 metin yazılmaz); mobil/masaüstünde
/// ise yerel bir kutu (box) dosyasında saklanır. Bu sayede tek bir kod yolu
/// tüm platformlarda kalıcılığı (sayfa yenilense/uygulama kapansa bile) sağlar.
class CustomAudioStore {
  static const boxName = 'custom_prayer_audio';

  /// Tek bir dosya için makul bir üst sınır: hem Hive/IndexedDB'de hem de
  /// oynatma sırasında data URI olarak belleğe alınacağı için çok büyük
  /// dosyalar (onlarca MB) performans sorunu yaratabilir.
  static const int maxBytes = 20 * 1024 * 1024; // 20 MB

  Future<Box> _box() => Hive.openBox(boxName);

  Future<List<CustomAudioFile>> all() async {
    final box = await _box();
    return box.values.map((v) => CustomAudioFile._fromMap(Map.from(v as Map))).toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  }

  Future<CustomAudioFile?> get(String id) async {
    final box = await _box();
    final raw = box.get(id);
    if (raw == null) return null;
    return CustomAudioFile._fromMap(Map.from(raw as Map));
  }

  Future<CustomAudioFile> add(String fileName, Uint8List bytes) async {
    if (bytes.length > maxBytes) {
      throw ArgumentError('Ses dosyası çok büyük (${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB). En fazla ${maxBytes ~/ (1024 * 1024)} MB desteklenir.');
    }
    final box = await _box();
    final id = '${DateTime.now().millisecondsSinceEpoch}_${fileName.hashCode}';
    final file = CustomAudioFile(id: id, fileName: fileName, bytes: bytes, addedAt: DateTime.now());
    await box.put(id, file._toMap());
    return file;
  }

  Future<void> remove(String id) async {
    final box = await _box();
    await box.delete(id);
  }
}
