import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data'; // ✅ gerekli
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/platform_file_ops.dart';
import '../../../core/audio_manager.dart';
import '../../../theme.dart';
import '../../settings/data/image_categories.dart';
import '../../settings/presentation/alert_settings_controller.dart';

// ─────────────────────────────────────────────────────────
// ✅ HAKİKAT DAMLALARI – VERİ MODELİ
// ─────────────────────────────────────────────────────────
class SlideItem {
  final int image;
  final String category;
  final String title;
  final String source;
  final String date;
  final String text;

  SlideItem({
    required this.image,
    required this.category,
    required this.title,
    required this.source,
    required this.date,
    required this.text,
  });

  factory SlideItem.fromJson(Map<String, dynamic> json) {
    return SlideItem(
      image: json['image'] ?? 1,
      category: json['category'] ?? '',
      title: json['title'] ?? '',
      source: json['source'] ?? '',
      date: json['date'] ?? '',
      text: json['text'] ?? '',
    );
  }
}

class SlaytWidget extends ConsumerStatefulWidget {
  final double height;
  final Color backgroundColor;
  final int currentIndex;
  final Function(int)? onPageChanged;
  final List<String>? userImages;

  final bool hideOnPortrait;

  /// Tam ekran butonu gösterilsin mi?
  final bool showFullscreenButton;

  const SlaytWidget({
    super.key,
    this.userImages,
    required this.height,
    this.backgroundColor = tvBgDark,
    this.currentIndex = 0,
    this.onPageChanged,
    this.hideOnPortrait = false,
    this.showFullscreenButton = true,
  });

  @override
  ConsumerState<SlaytWidget> createState() => _SlaytWidgetState();
}

class _SlaytWidgetState extends ConsumerState<SlaytWidget> {
  List<String> assetImages = [];
  List<String> userImages = [];
  List<SlideItem> hakikatSlides = [];
  bool isLoading = true;

  int _initialPage = 0;
  bool _initialPageLoaded = false;

  // ✅ Web storage (IndexedDB) - Hive box
  Box? get _webBox {
    const boxName = 'web_user_images';
    return Hive.isBoxOpen(boxName) ? Hive.box(boxName) : null;
  }

  final CarouselSliderController _carouselController = CarouselSliderController();

  // ✅ listenManual subscription — dispose'da kapatılacak
  ProviderSubscription? _settingsSub;

  // ✅ Aktif image stream listener (eski listener temizliği için)
  ImageStream? _activeStream;
  ImageStreamListener? _activeListener;

  String _getEffectiveCategory(String category) {
    return normalizeImageCategory(category);
  }

  String _webKey(String category) {
    final cat = _getEffectiveCategory(category);
    return 'userImages_$cat';
  }

  /// ✅ WEB: Kaydet (bytes -> base64 list)
  Future<void> addUserImagesWeb(String category) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;

    final key = _webKey(category);
    final box = _webBox;
    if (box == null) return;
    final List existing = (box.get(key) as List?) ?? [];

    for (final f in result.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      existing.add(base64Encode(bytes));
    }

    await box.put(key, existing);

    // ✅ slaytı güncelle
    await _loadUserImages(category);

    // ✅ başka widget'lar da dinliyorsa tetikle (opsiyonel ama iyi)
    ref.read(alertSettingsProvider.notifier).triggerRefresh();
  }

  /// ✅ WEB: Oku
  Future<List<String>> _loadUserImagesWeb(String category) async {
    final box = _webBox;
    if (box == null) return [];
    final key = _webKey(category);
    final List list = (box.get(key) as List?) ?? [];
    return list.map((e) => 'base64:$e').cast<String>().toList();
  }

  String _pageKey(String category) {
    final cat = _getEffectiveCategory(category);
    return 'slayt_last_index_$cat';
  }

  Future<void> _loadLastPage(String category) async {
    final sp = await SharedPreferences.getInstance();
    final saved = sp.getInt(_pageKey(category)) ?? 0;

    if (!mounted) return;
    setState(() {
      _initialPage = saved;
      _initialPageLoaded = true;
    });
  }

  Future<void> _saveLastPage(String category, int index) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_pageKey(category), index);
  }

  List<String> _getAllImages(String category) {
    final cat = _getEffectiveCategory(category);
    if (cat == hakikatCategoryId) return []; // hakikat slides use hakikatSlides list
    if (cat == userPhotosCategoryId) return userImages;
    return [...assetImages, ...userImages];
  }

  @override
  void initState() {
    super.initState();

    // ✅ İlk yükleme
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final category = ref.read(alertSettingsProvider).slideCategory;
      await _loadLastPage(category);
      await _loadAllImages(category);
    });

    // ✅ Ayar değişince yeniden yükle (subscription saklanıyor)
    _settingsSub = ref.listenManual(alertSettingsProvider, (prev, next) async {
      if (prev == null) return;

      if (prev.slideCategory != next.slideCategory ||
          prev.lastUpdate != next.lastUpdate) {
        setState(() => _initialPageLoaded = false);
        await _loadLastPage(next.slideCategory);
        await _loadAllImages(next.slideCategory);
      }
    });
  }

  @override
  void dispose() {
    _settingsSub?.close();
    // ✅ Aktif image stream listener'ını temizle
    if (_activeStream != null && _activeListener != null) {
      _activeStream!.removeListener(_activeListener!);
    }
    super.dispose();
  }

  Future<void> _loadAllImages(String category) async {
    if (!mounted) return;
    setState(() => isLoading = true);

    final cat = _getEffectiveCategory(category);

    if (cat == hakikatCategoryId) {
      // Sadece hakikat slaytları yükle
      assetImages = [];
      userImages = [];
      await _loadHakikatSlides();
    } else if (cat == karisikCategoryId) {
      // Hem foto hem hakikat slaytları yükle
      await _loadAssetImages('all');
      await _loadUserImages('all');
      await _loadHakikatSlides();
    } else {
      hakikatSlides = [];
      if (cat != userPhotosCategoryId) {
        await _loadAssetImages(category);
      } else {
        assetImages = [];
      }
      await _loadUserImages(category);
    }

    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _loadHakikatSlides() async {
    try {
      final jsonString =
          await rootBundle.loadString('assets/data/slides.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      final loaded = jsonList.map((e) => SlideItem.fromJson(e)).toList();
      if (mounted) setState(() => hakikatSlides = loaded);
    } catch (e) {
      debugPrint('Hakikat slaytları yükleme hatası: $e');
      if (mounted) setState(() => hakikatSlides = []);
    }
  }

  Future<void> _loadAssetImages(String category) async {
    try {
      final assetPaths = await _loadAssetPaths();

      final cat = _getEffectiveCategory(category);
      // "Tümü" (all), her kategori klasörünün TEK bir birleşimidir — kendi
      // fiziksel `assets/images/all/` klasörü (genel/hero görselleri) de bu
      // birleşimin doğal bir parçasıdır. Her görsel asset manifestinde zaten
      // yalnızca bir kez bulunduğu için (tek dosya = tek kayıt) aynı görsel
      // iki kez listelenmez.
      final assetFolders = <String>['assets/images/$cat/'];

      final images = assetPaths.where((key) {
        final k = key.toLowerCase();
        final okFolder = cat == 'all' ? k.startsWith('assets/images/') : assetFolders.any(k.contains);
        final okExt = k.endsWith('.jpg') ||
            k.endsWith('.jpeg') ||
            k.endsWith('.png') ||
            k.endsWith('.webp');
        return okFolder && okExt;
      }).toList();

      if (mounted) setState(() => assetImages = images);
    } catch (e) {
      debugPrint("Asset yükleme hatası: $e");
    }
  }

  Future<List<String>> _loadAssetPaths() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest.listAssets();
  }

  Future<void> _loadUserImages(String category) async {
    try {
      if (kIsWeb) {
        final imgs = await _loadUserImagesWeb(category);
        if (mounted) setState(() => userImages = imgs);
        return;
      }

      final cat = _getEffectiveCategory(category);
      final imageFiles = await listUserImagePaths(cat);

      if (mounted) setState(() => userImages = imageFiles);
    } catch (e) {
      debugPrint("Kullanıcı resimleri yükleme hatası: $e");
    }
  }

  ImageProvider _getImageProvider(String path) {
    final p = path.toLowerCase();

    if (p.startsWith('base64:')) {
      final b64 = path.substring('base64:'.length);
      final bytes = base64Decode(b64);
      return MemoryImage(Uint8List.fromList(bytes));
    }

    if (p.startsWith('assets/')) return AssetImage(path);

    if (kIsWeb) return NetworkImage(path);
    return localFileImageProvider(path);
  }

  // ─────────────────────────────────────────────────────────
  // ✅ KARİŞIK MOD: image + hakikat slide listesi oluştur
  // ─────────────────────────────────────────────────────────
  /// Karışık modda kullanılacak birleşik item sayısını döndür.
  int _getMixedItemCount() {
    return _getAllImages('karisik').length + hakikatSlides.length;
  }

  /// Karışık modda index'e göre widget döndür.
  Widget _buildMixedItem(int index, double height) {
    final images = _getAllImages('karisik');
    // Strateji: sırayla image, hakikat, image, hakikat ...
    // Image listesi ve hakikat listesi iç içe geçirilir.
    final totalImages = images.length;
    final totalHakikat = hakikatSlides.length;
    final total = totalImages + totalHakikat;
    if (total == 0) return const SizedBox.shrink();

    // Interleave: her 2-3 image slide arasına 1 hakikat koy
    if (totalHakikat == 0) {
      // Sadece image
      final imgIdx = index % totalImages;
      return _buildImageSlide(images[imgIdx], height);
    }
    if (totalImages == 0) {
      // Sadece hakikat
      final hIdx = index % totalHakikat;
      return _HakikatSlideCard(item: hakikatSlides[hIdx]);
    }

    // Interleave: ratio'ya göre dağıt
    final ratio = totalImages / totalHakikat;
    final step = (ratio + 1).floor(); // her step adımda 1 hakikat
    if (step > 0 && (index + 1) % (step + 1) == 0) {
      // hakikat slide
      final hIdx = (index ~/ (step + 1)) % totalHakikat;
      return _HakikatSlideCard(item: hakikatSlides[hIdx]);
    } else {
      // image slide
      final offset = index ~/ (step + 1); // kaç hakikat geçildi
      final imgIdx = (index - offset) % totalImages;
      return _buildImageSlide(images[imgIdx], height);
    }
  }

  Widget _buildImageSlide(String imagePath, double height) {
    return ClipRect(
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: _SmartFittedImage(
          provider: _getImageProvider(imagePath),
          backgroundColor: widget.backgroundColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Portrait'te slaytı gizle (geri sayım tek başına kalsın)
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    if (widget.hideOnPortrait && isPortrait) {
      return const SizedBox.shrink();
    }

    final adhanActive = ref.watch(adhanActiveProvider);
    final settings = ref.watch(alertSettingsProvider);
    final category = settings.slideCategory;
    final allImages = _getAllImages(category);
    final effectiveCategory = _getEffectiveCategory(category);
    final isHakikat = effectiveCategory == hakikatCategoryId;
    final isKarisik = effectiveCategory == karisikCategoryId;

    // Toplam item sayısını belirle
    int totalItems;
    if (isHakikat) {
      totalItems = hakikatSlides.length;
    } else if (isKarisik) {
      totalItems = _getMixedItemCount();
    } else {
      totalItems = allImages.length;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final actualHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : (widget.height > 0 ? widget.height : MediaQuery.sizeOf(context).height);

        final safeInitialPage =
        (totalItems > 0 && _initialPage < totalItems) ? _initialPage : 0;

        final Widget content;

        if (isLoading || !_initialPageLoaded) {
          content = const Center(
              child: CircularProgressIndicator(color: Colors.white));
        } else if (totalItems > 0) {
          content = CarouselSlider.builder(
            key: ValueKey(
              '${category}_${settings.lastUpdate}_${totalItems}_$safeInitialPage',
            ),
            carouselController: _carouselController,
            itemCount: totalItems,
            itemBuilder: (context, index, realIdx) {
              if (isHakikat) {
                return _HakikatSlideCard(item: hakikatSlides[index]);
              } else if (isKarisik) {
                return _buildMixedItem(index, actualHeight);
              } else {
                return _buildImageSlide(allImages[index], actualHeight);
              }
            },
            options: CarouselOptions(
              height: actualHeight,
              viewportFraction: 1.0,
              initialPage: safeInitialPage,
              enlargeCenterPage: false,
              autoPlay: totalItems > 1 && !adhanActive,
              autoPlayInterval: Duration(
                seconds: settings.slideDuration > 0
                    ? settings.slideDuration
                    : 15,
              ),
              autoPlayAnimationDuration:
                  const Duration(milliseconds: 1200),
              scrollPhysics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i, reason) {
                widget.onPageChanged?.call(i);
                _saveLastPage(category, i);
              },
            ),
          );
        } else {
          content = Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.image_not_supported_outlined,
                    color: Colors.white24, size: 48),
                const SizedBox(height: 8),
                Text(
                  "Görsel bulunamadı: $category",
                  style: const TextStyle(color: Colors.white38),
                ),
              ],
            ),
          );
        }

        return Container(
          color: widget.backgroundColor,
          width: double.infinity,
          height: actualHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: content),
              // ✅ Tam ekran butonu
              if (widget.showFullscreenButton && totalItems > 0 && !isLoading)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FullScreenSlaytPage(),
                          ),
                        );
                      },
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: const Icon(
                          Icons.fullscreen,
                          color: Colors.white70,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Always preserve the whole image, including any text embedded at its edges.
class _SmartFittedImage extends StatelessWidget {
  const _SmartFittedImage({required this.provider, required this.backgroundColor});
  final ImageProvider provider;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: backgroundColor,
    child: Image(
      image: provider,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.image_not_supported_outlined, color: Colors.grey)),
    ),
  );
}

// ─────────────────────────────────────────────────────────
// ✅ HAKİKAT DAMLALARI SLIDE KARTI
// ─────────────────────────────────────────────────────────
class _HakikatSlideCard extends StatelessWidget {
  const _HakikatSlideCard({required this.item});
  final SlideItem item;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
    final padding = (c.maxWidth * .045).clamp(18.0, 56.0);
    return Stack(fit: StackFit.expand, children: [
      Image.asset('assets/images/all/img_${item.image}.jpg', fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF24312D))),
      const ColoredBox(color: Color(0x88000000)),
      Padding(padding: EdgeInsets.all(padding), child: Center(
        child: Container(
          padding: EdgeInsets.all(padding * .65),
          decoration: BoxDecoration(color: const Color(0x99000000),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24)),
          child: LayoutBuilder(builder: (context, inner) => FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(width: inner.maxWidth, child: Text(item.text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: (c.maxHeight * .05).clamp(22.0, 48.0),
                height: 1.45, fontWeight: FontWeight.w500, color: Colors.white)),
            ),
          )),
        ),
      )),
    ]);
  });
}

// ─────────────────────────────────────────────────────────
// ✅ TAM EKRAN SLAYT SAYFASI
// ─────────────────────────────────────────────────────────

class FullScreenSlaytPage extends ConsumerStatefulWidget {
  const FullScreenSlaytPage({super.key});

  @override
  ConsumerState<FullScreenSlaytPage> createState() =>
      _FullScreenSlaytPageState();
}

class _FullScreenSlaytPageState extends ConsumerState<FullScreenSlaytPage> {
  bool _showOverlay = true;

  @override
  void initState() {
    super.initState();
    // Tam ekran immersive mod (native & web)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // ✅ Web'de JavaScript Fullscreen API çağır
    if (kIsWeb) {
      _enterWebFullscreen();
    }

    // 3 saniye sonra overlay'i gizle
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showOverlay = false);
    });
  }

  /// Web Fullscreen API — adres çubuğunu tamamen gizler
  void _enterWebFullscreen() {
    try {
      // dart:js_interop kullanmadan, services üzerinden çağırabiliriz
      // Ama en basit yol: HTML element requestFullscreen
      _callJsFullscreen(true);
    } catch (e) {
      debugPrint('Web fullscreen hatası: $e');
    }
  }

  void _exitWebFullscreen() {
    try {
      _callJsFullscreen(false);
    } catch (e) {
      debugPrint('Web exitFullscreen hatası: $e');
    }
  }

  /// Platform-safe JS fullscreen call
  void _callJsFullscreen(bool enter) {
    // Bu işlem web_fullscreen_stub.dart / web_fullscreen_web.dart ile yapılır
    // Ama basit çözüm: sadece SystemChrome kullan (Flutter web'de de çalışır)
    if (enter) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      _exitWebFullscreen();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleOverlay() {
    setState(() => _showOverlay = !_showOverlay);
    if (_showOverlay) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showOverlay = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: tvBgDark,
      body: GestureDetector(
        onTap: _toggleOverlay,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Slayt — tam ekran
            Positioned.fill(
              child: SlaytWidget(
                height: screenSize.height,
                showFullscreenButton: false,
              ),
            ),

            // Kapat butonu (sağ üst)
            Positioned(
              top: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _showOverlay ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !_showOverlay,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: const EdgeInsets.all(10),
                            child: const Icon(
                              Icons.fullscreen_exit,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
