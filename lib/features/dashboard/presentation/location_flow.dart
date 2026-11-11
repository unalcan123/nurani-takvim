import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../locations/data/auto_location_service.dart';
import '../../locations/data/location_providers.dart';
import '../../locations/data/models.dart';
import '../../../theme.dart';
import '../../locations/presentation/city_page.dart';
import '../../locations/presentation/country_page.dart';
import '../../locations/presentation/district_page.dart';
import '../../settings/data/prefs_repository.dart';
import '../../settings/presentation/mode_controller.dart';
import '../../times/presentation/times_page.dart';
import 'app_shell.dart';

/// GPS ile konumu bulur, kullanıcıya onaylatır ve kaydeder. Şehir veya ilçe
/// kesin eşleşmezse ilgili elle seçim sayfası açılır; hiçbir şey tahmin
/// edilmez. Ana Sayfa'daki geri sayım kartı ve Ayarlar > Konum bunu paylaşır.
Future<void> detectAndSaveLocation(BuildContext context, WidgetRef ref) async {
  try {
    final service = ref.read(autoLocationServiceProvider);
    final result = await service.detect();

    if (!context.mounted) return;

    if (result.sehir == null) {
      // Ülke bulundu ama şehir eşleşmedi — kullanıcı elle devam etsin.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.ulke.ulkeAdi} bulundu, lütfen şehrinizi seçin.',
          ),
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CityPage(ulke: result.ulke)),
      );
      return;
    }

    if (result.ilce == null) {
      // Ülke + şehir bulundu ama ilçe kesin eşleşmedi — asla tahmin edilmez.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.sehir!.sehirAdi} bulundu, lütfen ilçenizi seçin.',
          ),
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DistrictPage(ulke: result.ulke, sehir: result.sehir!),
        ),
      );
      return;
    }

    // Otomatik eşleşme yanlış olabilir (ör. GPS hassasiyeti/idari sınırlar
    // yüzünden komşu bir ilçe seçilebilir) — sessizce kaydetmek yerine
    // kullanıcıya onaylatılır; onaylanmazsa elle seçime yönlendirilir.
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Konumunuz bulundu'),
            content: Text(
              '${result.ilce!.ilceAdi}, ${result.sehir!.sehirAdi}, ${result.ulke.ulkeAdi}\n\nBu doğru mu?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Hayır, elle seçeceğim'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Evet, doğru'),
              ),
            ],
          ),
    );

    if (!context.mounted) return;
    if (confirmed != true) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DistrictPage(ulke: result.ulke, sehir: result.sehir!),
        ),
      );
      return;
    }

    final saved = SavedLocation(
      ulke: result.ulke,
      sehir: result.sehir!,
      ilce: result.ilce!,
    );
    await openSavedLocation(context, ref, saved);
  } on AutoLocationError catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Konum tespit edilemedi: $e')));
  }
}

/// [saved] konumunu en üste alıp kaydeder ve Ana Sayfa'yı o konumla yeniden
/// açar (TV modunda kiosk ekranını). Elle seçim sayfası da aynı akışı izler.
Future<void> openSavedLocation(
  BuildContext context,
  WidgetRef ref,
  SavedLocation saved,
) async {
  await ref.read(prefsRepositoryProvider).addRecentLocation(saved);
  if (!context.mounted) return;
  final isTvMode = ref.read(modeProvider) == AppMode.tv;
  ref.read(dashboardSelectedTabProvider.notifier).state = 0;
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(
      builder:
          (_) =>
              isTvMode
                  ? TimesPage(
                    ulke: saved.ulke,
                    sehir: saved.sehir,
                    ilce: saved.ilce,
                  )
                  : const AppShell(),
    ),
    (route) => false,
  );
}

/// Konum seçenekleri: GPS ile bul, elle seç ya da son kullanılan bir konuma
/// geç. Ana Sayfa'daki şehir başlığına dokununca açılır.
Future<void> showLocationSheet(BuildContext context, WidgetRef ref) {
  final recent = ref.read(prefsRepositoryProvider).getRecentLocations();
  final current = recent.isEmpty ? null : recent.first;
  String label(SavedLocation l) =>
      '${l.ilce.ilceAdi}, ${l.sehir.sehirAdi}, ${l.ulke.ulkeAdi}';

  // Ana sayfadaki gibi: telefon biçimli dikey ekranda (Chrome "masaüstü
  // sitesi" ~980px bildirse bile) pencere tam genişlikte ve orantılı büyük.
  final size = MediaQuery.sizeOf(context);
  final phoneShaped = size.height / size.width >= 1.75;
  final s = phoneShaped ? (size.width / 400).clamp(1.0, 2.6) : 1.2;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(maxWidth: phoneShaped ? double.infinity : 640),
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final muted = dashboardMuted(theme.brightness);
      final ink = dashboardInk(theme.brightness);
      final tileTitle = TextStyle(fontSize: 20 * s, fontWeight: FontWeight.w600, color: ink);
      final tileSub = TextStyle(fontSize: 15 * s, color: muted);
      final tilePad = EdgeInsets.symmetric(horizontal: 16 * s, vertical: 8 * s);
      Widget tile({Key? key, required IconData icon, required String title,
          String? subtitle, required VoidCallback onTap}) => ListTile(
        key: key,
        contentPadding: tilePad,
        minLeadingWidth: 36 * s,
        horizontalTitleGap: 16 * s,
        leading: Icon(icon, size: 32 * s, color: ink),
        title: Text(title, style: tileTitle),
        subtitle: subtitle == null ? null : Padding(
            padding: EdgeInsets.only(top: 4 * s), child: Text(subtitle, style: tileSub)),
        onTap: onTap,
      );
      void run(Future<void> Function() action) {
        Navigator.pop(sheetContext);
        action();
      }

      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(8 * s, 0, 8 * s, 28 * s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16 * s, 0, 16 * s, 6 * s),
              child: Text(
                'Konum',
                style: TextStyle(fontSize: 30 * s, fontWeight: FontWeight.w700, color: ink),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16 * s, 0, 16 * s, 14 * s),
              child: Text(
                current == null
                    ? 'Vakitlerin hesaplanması için bir konum seçin.'
                    : 'Şu an: ${label(current)}',
                style: TextStyle(fontSize: 16 * s, color: muted, fontWeight: FontWeight.w500),
              ),
            ),
            tile(
              key: const ValueKey('sheet-auto-location'),
              icon: Icons.my_location_rounded,
              title: 'Konumumu otomatik bul',
              subtitle: 'GPS ile ilçenizi bulur, kaydetmeden önce sorar',
              onTap: () => run(() => detectAndSaveLocation(context, ref)),
            ),
            tile(
              key: const ValueKey('sheet-manual-location'),
              icon: Icons.travel_explore_rounded,
              title: 'Ülke ve şehri elle seç',
              onTap:
                  () => run(
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CountryPage()),
                    ),
                  ),
            ),
            if (recent.length > 1) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(16 * s, 18 * s, 16 * s, 4 * s),
                child: Text(
                  'Son konumlar',
                  style: TextStyle(fontSize: 16 * s, color: muted, fontWeight: FontWeight.w700),
                ),
              ),
              for (final l in recent.skip(1))
                tile(
                  icon: Icons.history_rounded,
                  title: l.ilce.ilceAdi,
                  subtitle: '${l.sehir.sehirAdi}, ${l.ulke.ulkeAdi}',
                  onTap: () => run(() => openSavedLocation(context, ref, l)),
                ),
            ],
          ],
        ),
      );
    },
  );
}
