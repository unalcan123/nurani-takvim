import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../locations/data/auto_location_service.dart';
import '../../locations/data/location_providers.dart';
import '../../locations/data/models.dart';
import '../../locations/presentation/city_page.dart';
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
    await ref.read(prefsRepositoryProvider).addRecentLocation(saved);
    if (!context.mounted) return;

    final isTvMode = ref.read(modeProvider) == AppMode.tv;
    // Yeni AppShell Ana Sayfa'da açılsın, Ayarlar'da kalmaya devam etmesin.
    ref.read(dashboardSelectedTabProvider.notifier).state = 0;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder:
            (_) =>
                isTvMode
                    ? TimesPage(
                      ulke: result.ulke,
                      sehir: result.sehir!,
                      ilce: result.ilce!,
                    )
                    : const AppShell(),
      ),
      (route) => false,
    );
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
