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

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final muted = dashboardMuted(theme.brightness);
      void run(Future<void> Function() action) {
        Navigator.pop(sheetContext);
        action();
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'Konum',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                current == null
                    ? 'Vakitlerin hesaplanması için bir konum seçin.'
                    : 'Şu an: ${label(current)}',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ),
            ListTile(
              key: const ValueKey('sheet-auto-location'),
              leading: const Icon(Icons.my_location_rounded),
              title: const Text('Konumumu otomatik bul'),
              subtitle: const Text(
                'GPS ile ilçenizi bulur, kaydetmeden önce sorar',
              ),
              onTap: () => run(() => detectAndSaveLocation(context, ref)),
            ),
            ListTile(
              key: const ValueKey('sheet-manual-location'),
              leading: const Icon(Icons.travel_explore_rounded),
              title: const Text('Ülke ve şehri elle seç'),
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'Son konumlar',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final l in recent.skip(1))
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: Text(l.ilce.ilceAdi),
                  subtitle: Text('${l.sehir.sehirAdi}, ${l.ulke.ulkeAdi}'),
                  onTap: () => run(() => openSavedLocation(context, ref, l)),
                ),
            ],
          ],
        ),
      );
    },
  );
}
