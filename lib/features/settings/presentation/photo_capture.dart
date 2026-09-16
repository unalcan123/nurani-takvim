import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../../core/image_pipeline.dart';
import '../../../core/slide_photo.dart';
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

/// Galeriden TEK bir fotoğraf seçer — mevcut bir fotoğrafı "Değiştir" akışı
/// için.
Future<PickedPhoto?> pickSinglePhotoFromGallery() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    allowMultiple: false,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final f = result.files.first;
  final bytes = f.bytes;
  if (bytes == null) return null;
  return PickedPhoto(name: f.name, bytes: bytes);
}

/// Önizleme ekranından dönen kullanıcı kararı. [mode] yalnızca bir
/// GÖRÜNTÜLEME tercihidir (bkz. [PhotoFitMode]) — kaydedilen piksel
/// verisini etkilemez, ayrı bir alan olarak saklanır.
class PhotoEditDecision {
  final PhotoFitMode mode;
  final int quarterTurns;
  const PhotoEditDecision({required this.mode, required this.quarterTurns});
}

/// Önizleme/düzenleme diyaloglarının paylaştığı, taşmaya karşı dayanıklı
/// yerleşim.
///
/// Önceki sürüm sabit bir `AspectRatio(16:9)` görsel kutusu + sabit
/// yükseklikli kontrol satırları kullanıyordu; kısa yatay telefon
/// ekranlarında (ör. 690×320, sistem çubukları düşüldükten sonra ~290px
/// yükseklik) bu sabit talepler toplamda kullanılabilir yüksekliği aşıp
/// "BOTTOM OVERFLOWED" hatasına yol açıyordu. Bunun yerine: görsel alanı
/// `Expanded` ile kalan (ne kadarsa o kadar) yüksekliğe sığar — kendisi asla
/// taşmaya neden olmaz — ve kontroller gerekirse dikey kaydırılabilir.
/// Ekran çok kısaysa (yatay telefon) tam ekran sunulur; aksi halde mevcut
/// kutulu diyalog görünümü (tablet/masaüstü) korunur.
///
/// Görsel alanı [SlidePhoto] kullanır — slaytta gösterileceği TAM olarak
/// aynı widget, aynı iki-katmanlı (contain / arka-planla-doldur) mantık.
class _PhotoEditorFrame extends StatelessWidget {
  final String title;
  final Uint8List? previewBytes;
  final bool rendering;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final PhotoFitMode mode;
  final ValueChanged<PhotoFitMode> onModeChanged;
  final List<Widget> actionButtons;
  final VoidCallback onClose;

  const _PhotoEditorFrame({
    required this.title,
    required this.previewBytes,
    required this.rendering,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.mode,
    required this.onModeChanged,
    required this.actionButtons,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    // Kısa yatay telefon yüksekliğinde (sistem çubukları dahil) kutulu bir
    // diyalog için yer yok — tam ekrana geç. Eşik, dikey telefonların en
    // kısasını (640) ve tabletleri güvenle "sığar" tarafında bırakacak,
    // yatay telefonları (320-430 yükseklik aralığı) "tam ekran" tarafına
    // alacak şekilde seçildi.
    final screen = MediaQuery.sizeOf(context);
    final compact = screen.height < 480;

    final preview = ClipRect(
      child: previewBytes == null
          ? ColoredBox(color: tvBgDark, child: const Center(child: CircularProgressIndicator()))
          : Stack(
              fit: StackFit.expand,
              children: [
                // Slaytta gösterileceği TAM widget — mod değişince yalnızca
                // arka plan katmanı eklenir/kalkar, ön plandaki fotoğrafın
                // boyutu/konumu bu widget içinde birebir aynı kalır.
                SlidePhoto(image: MemoryImage(previewBytes!), mode: mode, backgroundColor: tvBgDark),
                if (rendering)
                  const Center(child: CircularProgressIndicator(color: Colors.white70)),
              ],
            ),
    );

    final controls = Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                tooltip: 'Sola döndür',
                icon: const Icon(Icons.rotate_left),
                onPressed: onRotateLeft,
              ),
              const SizedBox(width: 16),
              IconButton.filledTonal(
                tooltip: 'Sağa döndür',
                icon: const Icon(Icons.rotate_right),
                onPressed: onRotateRight,
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
                label: Text('Arka Planla Doldur'),
                icon: Icon(Icons.blur_on),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (s) => onModeChanged(s.first),
          ),
          const SizedBox(height: 16),
          Row(children: actionButtons),
        ],
      ),
    );

    final body = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              IconButton(tooltip: 'Kapat', icon: const Icon(Icons.close), onPressed: onClose),
            ],
          ),
          // Görsel alanı kalan yüksekliğe sığar — hiçbir zaman taşmaya
          // sebep olmaz; ne kadar yer varsa fotoğraf o alana BoxFit.contain
          // ile (yakınlaştırma/kırpma olmadan) sığdırılır.
          Expanded(child: preview),
          // Kontroller dar yükseklikte gerekirse kendi içinde kayar; dışa
          // taşmaz.
          Flexible(child: SingleChildScrollView(child: controls)),
        ],
      ),
    );

    if (compact) {
      return Dialog.fullscreen(
        child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), child: body),
      );
    }

    final dialogHeight = math.min(640.0, screen.height * 0.85);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(height: dialogHeight, child: body),
        ),
      ),
    );
  }
}

/// Kaydetmeden önce fotoğrafı slaytta görüneceği haliyle gösterir; sağa/sola
/// 90° döndürme ve "Tamamını Göster / Arka Planla Doldur" seçenekleri sunar.
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
    _renderRotated();
  }

  // Yalnızca döndürme piksel verisini değiştirir; bu yüzden yalnızca bu
  // yeniden kodlamayı tetikler. Sığdır/doldur modu salt görüntüleme
  // katmanında (bkz. build) uygulanır — mod değişimi anında, yeniden
  // kodlama olmadan gerçekleşir.
  void _renderRotated() {
    setState(() => _rendering = true);
    final bytes = ImagePipeline.renderRotatedBytes(widget.oriented, quarterTurns: _quarterTurns);
    if (!mounted) return;
    setState(() {
      _previewBytes = bytes;
      _rendering = false;
    });
  }

  // Döndürme, ekranın kendi yönünden (portrait/landscape) tamamen
  // bağımsızdır — yalnızca bu düğmelerle değişir, cihaz döndürüldüğünde
  // (build yeniden çalıştığında) _quarterTurns değeri aynen korunur.
  void _rotate(int delta) {
    setState(() => _quarterTurns = (_quarterTurns + delta) % 4);
    _renderRotated();
  }

  void _setMode(PhotoFitMode mode) => setState(() => _mode = mode);

  @override
  Widget build(BuildContext context) {
    return _PhotoEditorFrame(
      title: widget.total > 1 ? 'Önizleme (${widget.index}/${widget.total})' : 'Önizleme',
      previewBytes: _previewBytes,
      rendering: _rendering,
      onRotateLeft: () => _rotate(3),
      onRotateRight: () => _rotate(1),
      mode: _mode,
      onModeChanged: _setMode,
      onClose: () => Navigator.pop(context),
      actionButtons: [
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
    );
  }
}

/// [showExistingPhotoEditSheet] kullanıcının seçtiği eylem.
enum ExistingPhotoAction { save, delete, replace }

class ExistingPhotoEditResult {
  final ExistingPhotoAction action;
  final PhotoFitMode mode;
  final int quarterTurns;
  const ExistingPhotoEditResult({
    required this.action,
    required this.mode,
    required this.quarterTurns,
  });
}

/// Silme öncesi onay ister — daha önce hiç onay istenmiyordu.
Future<bool> confirmDeletePhoto(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Fotoğrafı Sil'),
      content: const Text('Bu fotoğrafı silmek istediğinize emin misiniz? Bu işlem geri alınamaz.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Sil'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// "Fotoğraflarımı Düzenle" ızgarasında bir fotoğrafa dokununca açılır:
/// büyük önizleme, sağa/sola döndürme, sığdır/doldur seçimi ve üç eylem
/// (Sil — onaylı, Değiştir — yeniden ekleme akışını başlatır, Kaydet — bu
/// dönüş/mod ayarını yerinde kaydeder). `null` dönerse kullanıcı vazgeçmiştir.
///
/// [initialMode] fotoğrafın hâlihazırda kayıtlı görüntüleme tercihidir.
Future<ExistingPhotoEditResult?> showExistingPhotoEditSheet(
  BuildContext context, {
  required img.Image oriented,
  required PhotoFitMode initialMode,
}) {
  return showDialog<ExistingPhotoEditResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ExistingPhotoEditDialog(oriented: oriented, initialMode: initialMode),
  );
}

class _ExistingPhotoEditDialog extends StatefulWidget {
  final img.Image oriented;
  final PhotoFitMode initialMode;
  const _ExistingPhotoEditDialog({required this.oriented, required this.initialMode});

  @override
  State<_ExistingPhotoEditDialog> createState() => _ExistingPhotoEditDialogState();
}

class _ExistingPhotoEditDialogState extends State<_ExistingPhotoEditDialog> {
  late PhotoFitMode _mode = widget.initialMode;
  int _quarterTurns = 0;
  Uint8List? _previewBytes;
  bool _rendering = false;

  @override
  void initState() {
    super.initState();
    _renderRotated();
  }

  void _renderRotated() {
    setState(() => _rendering = true);
    final bytes = ImagePipeline.renderRotatedBytes(widget.oriented, quarterTurns: _quarterTurns);
    if (!mounted) return;
    setState(() {
      _previewBytes = bytes;
      _rendering = false;
    });
  }

  void _rotate(int delta) {
    setState(() => _quarterTurns = (_quarterTurns + delta) % 4);
    _renderRotated();
  }

  void _setMode(PhotoFitMode mode) => setState(() => _mode = mode);

  Future<void> _delete() async {
    final confirmed = await confirmDeletePhoto(context);
    if (!confirmed || !mounted) return;
    Navigator.pop(context, ExistingPhotoEditResult(
      action: ExistingPhotoAction.delete, mode: _mode, quarterTurns: _quarterTurns));
  }

  @override
  Widget build(BuildContext context) {
    return _PhotoEditorFrame(
      title: 'Fotoğrafı Düzenle',
      previewBytes: _previewBytes,
      rendering: _rendering,
      onRotateLeft: () => _rotate(3),
      onRotateRight: () => _rotate(1),
      mode: _mode,
      onModeChanged: _setMode,
      onClose: () => Navigator.pop(context),
      actionButtons: [
        IconButton(
          tooltip: 'Sil',
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          onPressed: _delete,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context, ExistingPhotoEditResult(
                action: ExistingPhotoAction.replace, mode: _mode, quarterTurns: _quarterTurns)),
            child: const Text('Değiştir'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: () => Navigator.pop(context, ExistingPhotoEditResult(
                action: ExistingPhotoAction.save, mode: _mode, quarterTurns: _quarterTurns)),
            child: const Text('Kaydet'),
          ),
        ),
      ],
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

/// Fotoğraf kaydedilirken çağrılır: işlenmiş JPEG baytları + kullanıcının
/// seçtiği görüntüleme modu (ayrıca metadata olarak saklanmalıdır).
typedef SavePhotoBytes = Future<void> Function(Uint8List jpegBytes, PhotoFitMode mode);

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
          quarterTurns: decision.quarterTurns,
        );
        await savePhoto(processed.jpegBytes, decision.mode);
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

/// [pickAndProcessSinglePhoto] sonucu: işlenmiş JPEG baytları + kullanıcının
/// seçtiği görüntüleme modu.
class ProcessedPhotoPick {
  final Uint8List bytes;
  final PhotoFitMode mode;
  const ProcessedPhotoPick({required this.bytes, required this.mode});
}

/// "Fotoğrafı Değiştir" akışı: kamera/galeriden TEK bir yeni fotoğraf seçtirir,
/// aynı EXIF-düzeltme + önizleme adımlarından geçirir ve işlenmiş JPEG
/// baytları + seçilen modu döner. Kullanıcı vazgeçerse veya dosya
/// desteklenmiyorsa/bozuksa `null` döner (ilgili durumda bir SnackBar ile
/// açıkça bildirilir).
Future<ProcessedPhotoPick?> pickAndProcessSinglePhoto(BuildContext context) async {
  if (_photoFlowInProgress) return null;
  _photoFlowInProgress = true;

  try {
    final source = await showPhotoSourceSheet(context);
    if (source == null || !context.mounted) return null;

    final picked = source == 'camera'
        ? await capturePhotoFromCamera()
        : await pickSinglePhotoFromGallery();
    if (picked == null) return null;

    if (!isPickedFileSupported(picked.name)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Desteklenmeyen dosya formatı (yalnızca JPG, JPEG, PNG, WEBP '
              'desteklenir — HEIC/HEIF desteklenmez).'),
        ));
      }
      return null;
    }

    img.Image oriented;
    try {
      oriented = await ImagePipeline.decodeAndOrientAsync(picked.bytes);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Fotoğraf işlenemedi — dosya bozuk veya desteklenmeyen bir formatta.'),
        ));
      }
      return null;
    }

    if (!context.mounted) return null;
    final decision = await showPhotoPreviewDialog(context, oriented: oriented, fileName: picked.name);
    if (decision == null || !context.mounted) return null;

    final status = ValueNotifier<String>('Fotoğraf işleniyor...');
    unawaited(ProcessingProgressDialog.show(context, status));
    try {
      final processed = await ImagePipeline.finalizeAsync(
        oriented,
        quarterTurns: decision.quarterTurns,
      );
      return ProcessedPhotoPick(bytes: processed.jpegBytes, mode: decision.mode);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotoğraf kaydedilemedi. Lütfen tekrar deneyin.')),
        );
      }
      return null;
    } finally {
      status.dispose();
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  } finally {
    _photoFlowInProgress = false;
  }
}
