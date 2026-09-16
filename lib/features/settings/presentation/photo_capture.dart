import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../../core/image_pipeline.dart';
import '../../../theme.dart';
import 'slide_settings_page.dart' show isSupportedImageFileName;

/// Kamera veya galeriden seçilen tek bir işlenmemiş fotoğraf.
class PickedPhoto {
  final String name;
  final Uint8List bytes;
  const PickedPhoto({required this.name, required this.bytes});
}

/// "Kamera" / "Galeri" seçim sayfası. `null` dönerse kullanıcı vazgeçmiştir.
Future<String?> showPhotoSourceSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Fotoğraf Ekle', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Kamerayla Çek'),
            onTap: () => Navigator.pop(context, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Galeriden Seç'),
            onTap: () => Navigator.pop(context, 'gallery'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Kameradan tek bir fotoğraf çeker. Kullanıcı iptal ederse `null` döner.
Future<PickedPhoto?> capturePhotoFromCamera() async {
  final picker = ImagePicker();
  final XFile? file = await picker.pickImage(
    source: ImageSource.camera,
    // Orijinal çözünürlükte al; boyutlandırma/kaliteyi ImagePipeline yapar.
    maxWidth: null,
    maxHeight: null,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return PickedPhoto(name: file.name, bytes: bytes);
}

/// Galeriden birden çok fotoğraf seçer (mevcut file_picker akışı korunur —
/// web ve masaüstünde de çalışır).
Future<List<PickedPhoto>> pickPhotosFromGallery() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    allowMultiple: true,
    withData: true,
  );
  if (result == null) return [];

  final picked = <PickedPhoto>[];
  for (final f in result.files) {
    final bytes = f.bytes;
    if (bytes == null) continue;
    picked.add(PickedPhoto(name: f.name, bytes: bytes));
  }
  return picked;
}

/// Önizleme ekranından dönen kullanıcı kararı.
class PhotoEditDecision {
  final PhotoFitMode mode;
  final int quarterTurns;
  const PhotoEditDecision({required this.mode, required this.quarterTurns});
}

/// Kaydetmeden önce fotoğrafı slaytta görüneceği haliyle gösterir; sağa/sola
/// 90° döndürme ve "Sığdır / Doldur" seçenekleri sunar.
///
/// `null` dönerse kullanıcı bu fotoğrafı eklemekten vazgeçmiştir (atlandı).
Future<PhotoEditDecision?> showPhotoPreviewDialog(
  BuildContext context, {
  required img.Image oriented,
  required String fileName,
  int index = 1,
  int total = 1,
}) {
  return showDialog<PhotoEditDecision>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _PhotoPreviewDialog(
      oriented: oriented,
      fileName: fileName,
      index: index,
      total: total,
    ),
  );
}

class _PhotoPreviewDialog extends StatefulWidget {
  final img.Image oriented;
  final String fileName;
  final int index;
  final int total;

  const _PhotoPreviewDialog({
    required this.oriented,
    required this.fileName,
    required this.index,
    required this.total,
  });

  @override
  State<_PhotoPreviewDialog> createState() => _PhotoPreviewDialogState();
}

class _PhotoPreviewDialogState extends State<_PhotoPreviewDialog> {
  PhotoFitMode _mode = PhotoFitMode.contain;
  int _quarterTurns = 0;
  Uint8List? _previewBytes;
  bool _rendering = false;

  @override
  void initState() {
    super.initState();
    _renderPreview();
  }

  void _renderPreview() {
    setState(() => _rendering = true);
    // Küçük önizleme görseli hızlı kodlanır; senkron çağrı yeterlidir.
    final bytes = ImagePipeline.renderPreview(
      widget.oriented,
      mode: _mode,
      quarterTurns: _quarterTurns,
    );
    if (!mounted) return;
    setState(() {
      _previewBytes = bytes;
      _rendering = false;
    });
  }

  void _rotate(int delta) {
    setState(() => _quarterTurns = (_quarterTurns + delta) % 4);
    _renderPreview();
  }

  void _setMode(PhotoFitMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    _renderPreview();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.total > 1 ? 'Önizleme (${widget.index}/${widget.total})' : 'Önizleme',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Vazgeç (bu fotoğrafı atla)',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // ✅ Slaytta gösterileceği gibi: sabit oranlı kutu, contain fit,
              // slayt arka plan rengiyle (tvBgDark) doldurulur.
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(
                  color: tvBgDark,
                  child: _previewBytes == null
                      ? const Center(child: CircularProgressIndicator())
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(_previewBytes!, fit: BoxFit.contain),
                            if (_rendering)
                              const Center(child: CircularProgressIndicator(color: Colors.white70)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Sola döndür',
                    icon: const Icon(Icons.rotate_left),
                    onPressed: () => _rotate(3),
                  ),
                  const SizedBox(width: 16),
                  IconButton.filledTonal(
                    tooltip: 'Sağa döndür',
                    icon: const Icon(Icons.rotate_right),
                    onPressed: () => _rotate(1),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<PhotoFitMode>(
                segments: const [
                  ButtonSegment(
                    value: PhotoFitMode.contain,
                    label: Text('Tamamını Göster'),
                    icon: Icon(Icons.fit_screen_outlined),
                  ),
                  ButtonSegment(
                    value: PhotoFitMode.fill,
                    label: Text('Alanı Doldur'),
                    icon: Icon(Icons.crop),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => _setMode(s.first),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Atla'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        PhotoEditDecision(mode: _mode, quarterTurns: _quarterTurns),
                      ),
                      child: const Text('Kaydet'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Toplu işleme sırasında ilerleme gösteren, kapatılamayan diyalog.
class ProcessingProgressDialog extends StatefulWidget {
  final ValueListenable<String> statusText;
  const ProcessingProgressDialog({super.key, required this.statusText});

  static Future<void> show(BuildContext context, ValueListenable<String> statusText) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProcessingProgressDialog(statusText: statusText),
    );
  }

  @override
  State<ProcessingProgressDialog> createState() => _ProcessingProgressDialogState();
}

class _ProcessingProgressDialogState extends State<ProcessingProgressDialog> {
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: widget.statusText,
                builder: (context, value, _) => Text(value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Desteklenmeyen bir dosya adı için hızlı kontrol — HEIC/HEIF dahil.
bool isPickedFileSupported(String fileName) => isSupportedImageFileName(fileName);

/// Sadece platform bilgisini dışa aktarmak için (test/analiz kolaylığı).
bool get isWebPlatform => kIsWeb;

/// Bir [runAddPhotosFlow] çağrısının sonucu.
class PhotoAddSummary {
  final int added;
  final int skipped;
  /// Kaç fotoğraf denendiği (seçildiği). 0 ise kullanıcı hiçbir şey
  /// seçmeden/çekmeden vazgeçmiştir — bu durumda çağıran taraf herhangi bir
  /// bildirim göstermemelidir.
  final int attempted;

  const PhotoAddSummary({required this.added, required this.skipped, required this.attempted});
}

typedef SavePhotoBytes = Future<void> Function(Uint8List jpegBytes);

/// Uygulama genelinde tek seferde tek bir ekleme akışının çalışmasını
/// garanti eder (çift kaydı önler).
bool _photoFlowInProgress = false;

/// Kamera/galeri seçimi → EXIF düzeltme → önizleme (döndürme + sığdır/doldur)
/// → kaydetme akışının tamamını yürütür. Web ve mobilde aynıdır; yalnızca
/// [savePhoto] çağıranın hedefine göre değişir (Hive base64 ya da dosya).
Future<PhotoAddSummary> runAddPhotosFlow({
  required BuildContext context,
  required SavePhotoBytes savePhoto,
}) async {
  if (_photoFlowInProgress) {
    return const PhotoAddSummary(added: 0, skipped: 0, attempted: 0);
  }
  _photoFlowInProgress = true;

  try {
    final source = await showPhotoSourceSheet(context);
    if (source == null || !context.mounted) {
      return const PhotoAddSummary(added: 0, skipped: 0, attempted: 0);
    }

    List<PickedPhoto> picked;
    if (source == 'camera') {
      final p = await capturePhotoFromCamera();
      picked = p == null ? [] : [p];
    } else {
      picked = await pickPhotosFromGallery();
    }
    if (picked.isEmpty) {
      return const PhotoAddSummary(added: 0, skipped: 0, attempted: 0);
    }

    var added = 0;
    var skipped = 0;
    var index = 0;

    for (final photo in picked) {
      index++;

      if (!isPickedFileSupported(photo.name)) {
        skipped++;
        continue;
      }

      img.Image oriented;
      try {
        oriented = await ImagePipeline.decodeAndOrientAsync(photo.bytes);
      } catch (_) {
        skipped++;
        continue;
      }

      if (!context.mounted) break;
      final decision = await showPhotoPreviewDialog(
        context,
        oriented: oriented,
        fileName: photo.name,
        index: index,
        total: picked.length,
      );
      if (decision == null) {
        skipped++;
        continue;
      }

      if (!context.mounted) break;
      final status = ValueNotifier<String>('Fotoğraf işleniyor...');
      unawaited(ProcessingProgressDialog.show(context, status));
      try {
        final processed = await ImagePipeline.finalizeAsync(
          oriented,
          mode: decision.mode,
          quarterTurns: decision.quarterTurns,
        );
        await savePhoto(processed.jpegBytes);
        added++;
      } catch (_) {
        skipped++;
      } finally {
        status.dispose();
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      }
    }

    return PhotoAddSummary(added: added, skipped: skipped, attempted: picked.length);
  } finally {
    _photoFlowInProgress = false;
  }
}
