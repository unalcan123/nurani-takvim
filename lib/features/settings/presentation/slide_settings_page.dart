import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../../core/image_pipeline.dart';
import '../../../core/platform_file_ops.dart';
import '../../../core/responsive.dart';
import '../data/alert_settings.dart';
import '../data/image_categories.dart';
import 'alert_settings_controller.dart';
import 'photo_capture.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Desteklenen kullanıcı fotoğrafı uzantıları. HEIC/HEIF (bazı iPhone
/// kameralarının varsayılan galeri formatı) kasıtlı olarak DAHİL EDİLMEZ —
/// `package:image` bu formatı çözümleyemez; sessizce atlamak yerine
/// kullanıcıya açıkça bildirilir (bkz. [runAddPhotosFlow]).
const List<String> supportedImageExtensions = ['jpg', 'jpeg', 'png', 'webp'];

bool isSupportedImageFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot == -1) return false;
  final ext = fileName.substring(dot + 1).toLowerCase();
  return supportedImageExtensions.contains(ext);
}


class SlideSettingsPage extends ConsumerWidget {
  const SlideSettingsPage({super.key});
  Box get _webBox => Hive.box('web_user_images');

  String _getEffectiveCategory(String category) {
    return normalizeImageCategory(category);
  }

  String _webKey(String category) {
    final cat = _getEffectiveCategory(category);
    return 'userImages_$cat';
  }

  /// Kategori seçtirir, ardından kamera/galeriden fotoğraf ekleme akışını
  /// çalıştırır (EXIF düzeltme + önizleme + kaydetme). Web ve mobil aynı
  /// [runAddPhotosFlow] hattını kullanır; yalnızca kaydetme hedefi farklıdır
  /// (web: Hive/IndexedDB base64, mobil: uygulama belgeleri klasörü).
  Future<void> addUserImages(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(alertSettingsProvider);
    final fullMap = _getUserPhotoCategoryMap(settings);

    final String? selectedKey = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kategori Seçin'),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.sizeOf(context).height * 0.55,
          child: ListView(
            shrinkWrap: true,
            children: fullMap.entries
                .map((e) => ListTile(
                      title: Text(e.value),
                      onTap: () => Navigator.pop(context, e.key),
                    ))
                .toList(),
          ),
        ),
      ),
    );
    if (selectedKey == null || !context.mounted) return;

    final summary = await runAddPhotosFlow(
      context: context,
      savePhoto: kIsWeb
          ? (bytes, mode) async {
              final key = _webKey(selectedKey);
              final List existing = (_webBox.get(key) as List?) ?? [];
              existing.add(encodeWebPhotoEntry(bytes, mode));
              await _webBox.put(key, existing);
            }
          : (bytes, mode) async {
              final path = await saveUserImageBytes(_getInternalDir(selectedKey), bytes);
              await writePhotoModeSidecar(path, mode.name);
            },
    );

    if (summary.attempted == 0) return;

    if (kIsWeb) {
      ref.read(alertSettingsProvider.notifier).touchLastUpdate();
    } else {
      ref.read(alertSettingsProvider.notifier).triggerRefresh();
    }

    if (context.mounted) _showAddResultSnackBar(context, summary.added, summary.skipped);
  }

  /// Eklenen/atlanan fotoğraf sayısını kullanıcıya bildirir — desteklenmeyen
  /// bir format (ör. HEIC/HEIF) sessizce atlanmaz, açıkça belirtilir.
  void _showAddResultSnackBar(BuildContext context, int added, int skipped) {
    final parts = <String>[];
    if (added > 0) parts.add('$added fotoğraf eklendi.');
    if (skipped > 0) {
      parts.add('$skipped dosya desteklenmeyen formatta olduğu için eklenemedi (yalnızca JPG, JPEG, PNG, WEBP desteklenir — HEIC/HEIF desteklenmez).');
    }
    if (parts.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(parts.join(' ')),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// Hazır (asset) kategoriler [imageCategories]'den (merkezi liste) gelir;
  /// buraya ayrıca özel, asset-klasörü OLMAYAN kategoriler eklenir.
  static Map<String, String> get defaultCategoryMap => {
        for (final c in imageCategories) c.id: c.label,
        hakikatCategoryId: 'Hakikat Damlaları',
        karisikCategoryId: 'Karışık (Foto + Hakikat)',
        userPhotosCategoryId: 'Benim Fotoğraflarım',
      };

  Map<String, String> _getFullCategoryMap(AlertSettings settings) {
    return {...defaultCategoryMap, ...settings.userCategories};
  }

  /// Kullanıcının fotoğraf yükleyebileceği kategoriler: "Tümü" (fiziksel bir
  /// yükleme hedefi değil, salt bir görünüm filtresidir) ve Hakikat
  /// Damlaları / Karışık (kendi ses/görsel kaynağı olan özel modlar) hariç
  /// tüm kategoriler + kullanıcının kendi oluşturduğu kategoriler.
  Map<String, String> _getUserPhotoCategoryMap(AlertSettings settings) {
    final excluded = {'all', hakikatCategoryId, karisikCategoryId};
    return Map.fromEntries(
      _getFullCategoryMap(settings).entries.where((entry) => !excluded.contains(entry.key)),
    );
  }

  String _getInternalDir(String key) => key == userPhotosCategoryId ? 'user' : key;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(alertSettingsProvider);
    final alertController = ref.read(alertSettingsProvider.notifier);
    final fullCategoryMap = _getFullCategoryMap(settings);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Modern renk paleti
    final cardColor = isDark ? const Color(0xFF1E1E2C) : Colors.white;
    final surfaceColor = isDark ? const Color(0xFF16162A) : const Color(0xFFF5F5FA);
    final accentColor = const Color(0xFF6C63FF);
    final accentLight = accentColor.withValues(alpha: 0.1);

    return Scaffold(
      backgroundColor: surfaceColor,
      appBar: AppBar(
        title: const Text('Slayt Ayarları'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          // --- Kategori Seçimi ---
          _SectionHeader(icon: Icons.palette_outlined, title: 'Görüntülenecek Kategori'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: fullCategoryMap.entries.map((entry) {
                // `entry.key` normalize edilmiş (kanonik) kimliklerdir;
                // `settings.slideCategory` eski bir sürümden kalma normalize
                // edilmemiş bir değer olabilir (ör. eski 'Kullanıcı Foto'
                // etiketi) — karşılaştırma her ikisini de normalize ederek
                // yapılır ki radio seçili görünsün.
                final isSelected = _getEffectiveCategory(settings.slideCategory) == entry.key;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? accentLight : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: RadioListTile<String>(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    activeColor: accentColor,
                    title: Text(
                      entry.value,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? accentColor : null,
                      ),
                    ),
                    value: entry.key,
                    groupValue: _getEffectiveCategory(settings.slideCategory),
                    onChanged: (value) {
                      if (value != null) alertController.setSlideCategory(value);
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          // --- Değişim Süresi ---
          _SectionHeader(icon: Icons.timer_outlined, title: 'Fotoğraf Değişim Süresi'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.speed, color: accentColor, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [5, 10, 15, 20, 30, 45, 60].map((seconds) {
                      final isSelected = settings.slideDuration == seconds;
                      return ChoiceChip(
                        label: Text('$seconds sn'),
                        selected: isSelected,
                        selectedColor: accentColor,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : null,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (_) => alertController.setSlideDuration(seconds),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // --- Aksiyon Butonları ---
          _SectionHeader(icon: Icons.photo_camera_outlined, title: 'Fotoğraf İşlemleri'),
          const SizedBox(height: 8),

          // Yeni Fotoğraf Ekle
          _ActionCard(
            icon: Icons.add_photo_alternate_outlined,
            iconColor: Colors.green,
            title: 'Yeni Fotoğraf Ekle',
            subtitle: 'TV formatına uygun olarak ekler',
            onTap: () async {
              await addUserImages(context, ref);
              if (context.mounted) Navigator.pop(context);
            },
            cardColor: cardColor,
          ),

          const SizedBox(height: 10),

          // Kullanıcı Fotoğraflarını Düzenle
          _ActionCard(
            icon: Icons.photo_library_outlined,
            iconColor: Colors.blue,
            title: 'Fotoğraflarımı Düzenle',
            subtitle: 'Eklediğiniz fotoğrafları görüntüleyip silebilirsiniz',
            onTap: () => _manageUserImages(context, ref),
            cardColor: cardColor,
          ),

          const SizedBox(height: 10),

          // Yeni Kategori Oluştur
          _ActionCard(
            icon: Icons.create_new_folder_outlined,
            iconColor: Colors.orange,
            title: 'Yeni Kategori Oluştur',
            subtitle: 'Kendi özel kategorinizi ekleyin',
            onTap: () => _addNewCategory(context, ref),
            cardColor: cardColor,
          ),

          // --- Kullanıcı Kategorileri ---
          if (settings.userCategories.isNotEmpty) ...[
            const SizedBox(height: 24),
            _SectionHeader(icon: Icons.folder_special_outlined, title: 'Kategorilerim'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: settings.userCategories.entries.map((e) {
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.folder_open, color: Colors.orange, size: 22),
                    ),
                    title: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w500)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => _confirmDeleteCategory(context, e.key, e.value, alertController),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _addNewCategory(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Yeni Kategori"),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: "Kategori adı girin",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal")),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text("Ekle"),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      await ref.read(alertSettingsProvider.notifier).addUserCategory(name);
    }
  }

  Future<void> _manageUserImages(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(alertSettingsProvider);
    final fullMap = _getUserPhotoCategoryMap(settings);

    final String? selectedKey = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Düzenlenecek Kategori"),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.sizeOf(context).height * 0.55,
          child: ListView(
            shrinkWrap: true,
            children: fullMap.entries
                .map((e) => ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      title: Text(e.value),
                      onTap: () => Navigator.pop(context, e.key),
                    ))
                .toList(),
          ),
        ),
      ),
    );

    if (selectedKey == null || !context.mounted) return;
    final categoryName = fullMap[selectedKey] ?? selectedKey;

    if (kIsWeb) {
      await _manageUserImagesWeb(context, ref, selectedKey, categoryName);
    } else {
      await _manageUserImagesMobile(context, ref, selectedKey, categoryName);
    }
  }

  Future<void> _manageUserImagesWeb(
    BuildContext context,
    WidgetRef ref,
    String category,
    String categoryName,
  ) async {
    final key = _webKey(category);
    final images = List<dynamic>.from((_webBox.get(key) as List?) ?? []);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> addImages() async {
            final summary = await runAddPhotosFlow(
              context: context,
              savePhoto: (bytes, mode) async {
                images.add(encodeWebPhotoEntry(bytes, mode));
                await _webBox.put(key, images);
              },
            );
            if (summary.attempted == 0) return;

            ref.read(alertSettingsProvider.notifier).triggerRefresh();
            setSheetState(() {});
            if (context.mounted) _showAddResultSnackBar(context, summary.added, summary.skipped);
          }

          Future<void> deleteAt(int index, {bool skipConfirm = false}) async {
            if (!skipConfirm) {
              final confirmed = await confirmDeletePhoto(context);
              if (!confirmed) return;
            }
            images.removeAt(index);
            await _webBox.put(key, images);
            ref.read(alertSettingsProvider.notifier).triggerRefresh();
            setSheetState(() {});
          }

          Future<void> editAt(int index) async {
            final entry = decodeWebPhotoEntry(images[index]);
            img.Image oriented;
            try {
              oriented = await ImagePipeline.decodeAndOrientAsync(entry.bytes);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Fotoğraf açılamadı — bozuk olabilir. Silip tekrar ekleyebilirsiniz.'),
                ));
              }
              return;
            }
            if (!context.mounted) return;

            final result = await showExistingPhotoEditSheet(
              context, oriented: oriented, initialMode: entry.mode);
            if (result == null) return;

            switch (result.action) {
              case ExistingPhotoAction.delete:
                await deleteAt(index, skipConfirm: true);
                return;
              case ExistingPhotoAction.replace:
                final pick = await pickAndProcessSinglePhoto(context);
                if (pick == null) return;
                images[index] = encodeWebPhotoEntry(pick.bytes, pick.mode);
                await _webBox.put(key, images);
              case ExistingPhotoAction.save:
                final status = ValueNotifier<String>('Kaydediliyor...');
                if (context.mounted) unawaited(ProcessingProgressDialog.show(context, status));
                try {
                  final processed = await ImagePipeline.finalizeAsync(
                    oriented, quarterTurns: result.quarterTurns);
                  images[index] = encodeWebPhotoEntry(processed.jpegBytes, result.mode);
                  await _webBox.put(key, images);
                } finally {
                  status.dispose();
                  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
                }
            }

            ref.read(alertSettingsProvider.notifier).triggerRefresh();
            setSheetState(() {});
          }

          return _UserImageManagerSheet(
            title: categoryName,
            imageCount: images.length,
            itemBuilder: (context, index) => Image.memory(
              decodeWebPhotoEntry(images[index]).bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
            ),
            onAdd: addImages,
            onEdit: editAt,
            onDelete: (index) => deleteAt(index),
          );
        },
      ),
    );
  }

  Future<void> _manageUserImagesMobile(
    BuildContext context,
    WidgetRef ref,
    String category,
    String categoryName,
  ) async {
    final internalDir = _getInternalDir(category);
    List<String> images;
    try {
      images = await listUserImagePaths(internalDir);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Fotoğraflar yüklenemedi. Lütfen tekrar deneyin.'),
          action: SnackBarAction(
            label: 'Yeniden Dene',
            onPressed: () => _manageUserImagesMobile(context, ref, category, categoryName),
          ),
        ));
      }
      return;
    }

    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> addImages() async {
            final summary = await runAddPhotosFlow(
              context: context,
              savePhoto: (bytes, mode) async {
                final savedPath = await saveUserImageBytes(internalDir, bytes);
                await writePhotoModeSidecar(savedPath, mode.name);
                images.add(savedPath);
              },
            );
            if (summary.attempted == 0) return;

            ref.read(alertSettingsProvider.notifier).triggerRefresh();
            setSheetState(() {});
            if (context.mounted) _showAddResultSnackBar(context, summary.added, summary.skipped);
          }

          Future<void> deleteAt(int index, {bool skipConfirm = false}) async {
            if (!skipConfirm) {
              final confirmed = await confirmDeletePhoto(context);
              if (!confirmed) return;
            }
            final path = images.removeAt(index);
            await deleteLocalFile(path);
            ref.read(alertSettingsProvider.notifier).triggerRefresh();
            setSheetState(() {});
          }

          Future<void> editAt(int index) async {
            final path = images[index];
            img.Image oriented;
            try {
              oriented = await ImagePipeline.decodeAndOrientAsync(await readLocalFileBytes(path));
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Fotoğraf açılamadı — bozuk olabilir. Silip tekrar ekleyebilirsiniz.'),
                ));
              }
              return;
            }
            final initialMode = await readMobilePhotoMode(path);
            if (!context.mounted) return;

            final result = await showExistingPhotoEditSheet(
              context, oriented: oriented, initialMode: initialMode);
            if (result == null) return;

            switch (result.action) {
              case ExistingPhotoAction.delete:
                await deleteAt(index, skipConfirm: true);
                return;
              case ExistingPhotoAction.replace:
                final pick = await pickAndProcessSinglePhoto(context);
                if (pick == null) return;
                await overwriteUserImageBytes(path, pick.bytes);
                await writePhotoModeSidecar(path, pick.mode.name);
                await localFileImageProvider(path).evict();
              case ExistingPhotoAction.save:
                final status = ValueNotifier<String>('Kaydediliyor...');
                if (context.mounted) unawaited(ProcessingProgressDialog.show(context, status));
                try {
                  final processed = await ImagePipeline.finalizeAsync(
                    oriented, quarterTurns: result.quarterTurns);
                  await overwriteUserImageBytes(path, processed.jpegBytes);
                  await writePhotoModeSidecar(path, result.mode.name);
                  await localFileImageProvider(path).evict();
                } finally {
                  status.dispose();
                  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
                }
            }

            ref.read(alertSettingsProvider.notifier).triggerRefresh();
            setSheetState(() {});
          }

          return _UserImageManagerSheet(
            title: categoryName,
            imageCount: images.length,
            itemBuilder: (context, index) => Image(
              image: localFileImageProvider(images[index]),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
            ),
            onAdd: addImages,
            onEdit: editAt,
            onDelete: (index) => deleteAt(index),
          );
        },
      ),
    );
  }

  void _confirmDeleteCategory(
    BuildContext context,
    String key,
    String name,
    AlertSettingsNotifier controller,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Kategoriyi Sil"),
        content: Text("$name kategorisini ve içindeki tüm fotoğrafları silmek istiyor musunuz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("İptal")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Sil"),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await controller.removeUserCategory(key);
    }
  }
}

// --- Modern UI Bileşenleri ---

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
          ),
        ],
      ),
    );
  }
}

class _UserImageManagerSheet extends StatelessWidget {
  final String title;
  final int imageCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final Future<void> Function() onAdd;
  final Future<void> Function(int index) onEdit;
  final Future<void> Function(int index) onDelete;

  const _UserImageManagerSheet({
    required this.title,
    required this.imageCount,
    required this.itemBuilder,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            AppBar(
              title: Text(title),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  tooltip: 'Fotoğraf ekle',
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  onPressed: onAdd,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  imageCount == 0 ? 'Bu kategoride eklenmiş fotoğraf yok' : '$imageCount fotoğraf',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
            Expanded(
              child: imageCount == 0
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.photo_library_outlined, size: 56, color: Colors.grey),
                          const SizedBox(height: 12),
                          Text('Fotoğraf eklemek için sağ üstteki + simgesine dokunun',
                              style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    )
                  : GridView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 16 / 9,
                      ),
                      itemCount: imageCount,
                      itemBuilder: (context, index) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Material(
                                color: Colors.black12,
                                child: InkWell(
                                  onTap: () => onEdit(index),
                                  child: itemBuilder(context, index),
                                ),
                              ),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Material(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(20),
                                  child: IconButton(
                                    tooltip: 'Sil',
                                    icon: const Icon(Icons.delete_outline, color: Colors.white),
                                    onPressed: () => onDelete(index),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color cardColor;

  const _ActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.cardColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: phoneFont(context, 15, 16))),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: phoneFont(context, 13, 14))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
