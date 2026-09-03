import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../theme.dart';
import '../../locations/data/auto_location_service.dart';
import '../../locations/data/location_providers.dart';
import '../../locations/data/models.dart';
import '../../locations/presentation/city_page.dart';
import '../../locations/presentation/country_page.dart';
import '../../locations/presentation/district_page.dart';
import '../../locations/presentation/recent_locations_page.dart';
import '../../settings/data/prefs_repository.dart';
import '../../settings/presentation/bg_music_settings_page.dart';
import '../../settings/presentation/content_visibility_controller.dart';
import '../../settings/presentation/mode_controller.dart';
import '../../settings/presentation/qibla_page.dart';
import '../../settings/presentation/settings_page.dart';
import '../../settings/presentation/slide_settings_page.dart';
import '../../settings/presentation/theme_controller.dart';
import '../../times/presentation/times_page.dart';
import 'app_shell.dart';

/// Tüm uygulama ayarları burada, kategorilere ayrılmış olarak toplanır.
/// Ana ekranda (Dashboard) ayrı ayrı tema/bildirim/hesaplama ikonu
/// bulunmaz — tek giriş noktası budur.
class SettingsHubPage extends ConsumerWidget {
  const SettingsHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Container(
      color: dashboardBg(brightness),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (isLandscape) ...[
            const _HomeBackButton(),
            const SizedBox(height: 10),
          ],
          const _SlideSettingsQuickCard(),
          if (!isLandscape) ...[
            const SizedBox(height: 10),
            const _QiblaQuickCard(),
          ],
          const SizedBox(height: 10),
          const _GeneralSection(),
          const SizedBox(height: 10),
          const _LocationSection(),
          const SizedBox(height: 10),
          const _NotificationsSection(),
          const SizedBox(height: 10),
          const _ContentSection(),
          const SizedBox(height: 10),
          const _PrivacySection(),
        ],
      ),
    );
  }
}

class _HomeBackButton extends ConsumerWidget {
  const _HomeBackButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: () => ref.read(dashboardSelectedTabProvider.notifier).state = 0,
        icon: const Icon(Icons.arrow_back),
        label: const Text('Ana Sayfa'),
      ),
    );
  }
}

class _QiblaQuickCard extends StatelessWidget {
  const _QiblaQuickCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.navigation_outlined),
        title: const Text('Kıble Yönü', style: TextStyle(fontWeight: FontWeight.bold)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QiblaPage())),
      ),
    );
  }
}

/// Slayt/fotoğraf ekleme, sık kullanılan bir işlem olduğu için kategorilerin
/// içine gömülmeden, Ayarlar sayfasının en üstünde tek dokunuşla erişilir.
class _SlideSettingsQuickCard extends StatelessWidget {
  const _SlideSettingsQuickCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.add_photo_alternate_outlined),
        title: const Text('Slayt ve Foto Ayarları', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Fotoğraf ekle/düzenle, kategori ve gösterim süresi seç'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SlideSettingsPage())),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _CategoryCard({required this.icon, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: children,
      ),
    );
  }
}

class _ComingSoonTile extends StatelessWidget {
  final IconData icon;
  final String title;

  const _ComingSoonTile({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: false,
      leading: Icon(icon),
      title: Text(title),
      trailing: const Text('Yakında', style: TextStyle(fontSize: 12)),
    );
  }
}

class _GeneralSection extends ConsumerWidget {
  const _GeneralSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final themeController = ref.read(themeProvider.notifier);
    final appMode = ref.watch(modeProvider);

    return _CategoryCard(
      icon: Icons.tune,
      title: 'Genel',
      children: [
        RadioListTile<ThemeMode>(
          title: const Text('Sistem Varsayılanı'),
          value: ThemeMode.system,
          groupValue: themeMode,
          onChanged: (v) => v != null ? themeController.setThemeMode(v) : null,
        ),
        RadioListTile<ThemeMode>(
          title: const Text('Açık Tema'),
          value: ThemeMode.light,
          groupValue: themeMode,
          onChanged: (v) => v != null ? themeController.setThemeMode(v) : null,
        ),
        RadioListTile<ThemeMode>(
          title: const Text('Koyu Tema'),
          value: ThemeMode.dark,
          groupValue: themeMode,
          onChanged: (v) => v != null ? themeController.setThemeMode(v) : null,
        ),
        const Divider(height: 1),
        const _ComingSoonTile(icon: Icons.language_outlined, title: 'Dil (Türkçe)'),
        const _ComingSoonTile(icon: Icons.format_size_outlined, title: 'Yazı Boyutu'),
        const Divider(height: 1),
        SwitchListTile(
          secondary: const Icon(Icons.tv_outlined),
          title: const Text('TV Modu'),
          subtitle: const Text('Cami/salon ekranı için büyük, uzaktan okunabilir kiosk görünümü'),
          value: appMode == AppMode.tv,
          onChanged: (_) => ref.read(modeProvider.notifier).toggleMode(),
        ),
        ListTile(
          leading: const Icon(Icons.music_note_outlined),
          title: const Text('Arka Plan Müziği'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BgMusicSettingsPage())),
        ),
      ],
    );
  }
}

class _LocationSection extends ConsumerStatefulWidget {
  const _LocationSection();

  @override
  ConsumerState<_LocationSection> createState() => _LocationSectionState();
}

class _LocationSectionState extends ConsumerState<_LocationSection> {
  bool _detecting = false;

  Future<void> _detectLocation() async {
    setState(() => _detecting = true);
    try {
      final service = ref.read(autoLocationServiceProvider);
      final result = await service.detect();

      if (!mounted) return;

      if (result.sehir == null) {
        // Ülke bulundu ama şehir eşleşmedi — kullanıcı elle devam etsin.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result.ulke.ulkeAdi} bulundu, lütfen şehrinizi seçin.')),
        );
        Navigator.push(context, MaterialPageRoute(builder: (_) => CityPage(ulke: result.ulke)));
        return;
      }

      if (result.ilce == null) {
        // Ülke + şehir bulundu ama ilçe kesin eşleşmedi — asla tahmin edilmez.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result.sehir!.sehirAdi} bulundu, lütfen ilçenizi seçin.')),
        );
        Navigator.push(context, MaterialPageRoute(builder: (_) => DistrictPage(ulke: result.ulke, sehir: result.sehir!)));
        return;
      }

      // Otomatik eşleşme yanlış olabilir (ör. GPS hassasiyeti/idari sınırlar
      // yüzünden komşu bir ilçe seçilebilir) — sessizce kaydetmek yerine
      // kullanıcıya onaylatılır; onaylanmazsa elle seçime yönlendirilir.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Konumunuz bulundu'),
          content: Text('${result.ilce!.ilceAdi}, ${result.sehir!.sehirAdi}, ${result.ulke.ulkeAdi}\n\nBu doğru mu?'),
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

      if (!mounted) return;
      if (confirmed != true) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => DistrictPage(ulke: result.ulke, sehir: result.sehir!)));
        return;
      }

      final saved = SavedLocation(ulke: result.ulke, sehir: result.sehir!, ilce: result.ilce!);
      await ref.read(prefsRepositoryProvider).addRecentLocation(saved);
      if (!mounted) return;

      final isTvMode = ref.read(modeProvider) == AppMode.tv;
      // Yeni AppShell Ana Sayfa'da açılsın, Ayarlar'da kalmaya devam etmesin.
      ref.read(dashboardSelectedTabProvider.notifier).state = 0;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => isTvMode
              ? TimesPage(ulke: result.ulke, sehir: result.sehir!, ilce: result.ilce!)
              : const AppShell(),
        ),
        (route) => false,
      );
    } on AutoLocationError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Konum tespit edilemedi: $e')));
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recentLocations = ref.watch(prefsRepositoryProvider).getRecentLocations();
    final current = recentLocations.isNotEmpty ? recentLocations.first : null;

    return _CategoryCard(
      icon: Icons.location_on_outlined,
      title: 'Konum',
      children: [
        ListTile(
          leading: const Icon(Icons.pin_drop_outlined),
          title: const Text('Varsayılan Konum'),
          subtitle: Text(current == null ? 'Seçilmedi' : '${current.ilce.ilceAdi}, ${current.sehir.sehirAdi}, ${current.ulke.ulkeAdi}'),
        ),
        ListTile(
          leading: _detecting
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location_outlined),
          title: const Text('Otomatik Konum (GPS)'),
          subtitle: const Text('Konumunuzu bulup en yakın ilçeyle eşleştirir'),
          enabled: !_detecting,
          onTap: _detectLocation,
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.history_outlined),
          title: const Text('Son Konumlarım'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecentLocationsPage())),
        ),
        ListTile(
          leading: const Icon(Icons.travel_explore_outlined),
          title: const Text('Ülke / Şehir Seç'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CountryPage())),
        ),
      ],
    );
  }
}

class _NotificationsSection extends StatelessWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context) {
    return _CategoryCard(
      icon: Icons.notifications_outlined,
      title: 'Bildirimler',
      children: [
        ListTile(
          leading: const Icon(Icons.alarm_outlined),
          title: const Text('Namaz Bildirimleri, Ezan Sesi ve Hatırlatmalar'),
          subtitle: const Text('Vakit alarmları, önceden hatırlatma süresi, özel ezan sesi seçimi'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
        ),
      ],
    );
  }
}

class _ContentSection extends ConsumerWidget {
  const _ContentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibility = ref.watch(contentVisibilityProvider);
    final controller = ref.read(contentVisibilityProvider.notifier);

    return _CategoryCard(
      icon: Icons.auto_stories_outlined,
      title: 'İçerik',
      children: [
        SwitchListTile(
          title: const Text('Günün Âyeti Göster'),
          value: visibility.showAyet,
          onChanged: controller.setShowAyet,
        ),
        SwitchListTile(
          title: const Text('Günün Hadisi Göster'),
          value: visibility.showHadith,
          onChanged: controller.setShowHadith,
        ),
        SwitchListTile(
          title: const Text('Tarihte Bugün Göster'),
          value: visibility.showEvent,
          onChanged: controller.setShowEvent,
        ),
        SwitchListTile(
          title: const Text('Günün Sözü Göster'),
          value: visibility.showSoz,
          onChanged: controller.setShowSoz,
        ),
        const Divider(height: 1),
        const _ComingSoonTile(icon: Icons.source_outlined, title: 'İçerik Kaynağı Tercihleri'),
      ],
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection();

  @override
  Widget build(BuildContext context) {
    return _CategoryCard(
      icon: Icons.privacy_tip_outlined,
      title: 'Gizlilik ve Uygulama',
      children: [
        ListTile(
          leading: const Icon(Icons.location_on_outlined),
          title: const Text('Konum İzni'),
          subtitle: const Text('Cihaz ayarlarında yönetin'),
          trailing: const Icon(Icons.chevron_right),
          onTap: openAppSettings,
        ),
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: const Text('Bildirim İzni'),
          subtitle: const Text('Cihaz ayarlarında yönetin'),
          trailing: const Icon(Icons.chevron_right),
          onTap: openAppSettings,
        ),
        const Divider(height: 1),
        const _ComingSoonTile(icon: Icons.description_outlined, title: 'Gizlilik Politikası'),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Hakkında'),
          onTap: () => showAboutDialog(
            context: context,
            applicationName: 'Nurani Takvim',
            applicationVersion: '1.0.0',
            applicationLegalese: 'Unal S. tarafından geliştirilmiştir.',
          ),
        ),
        const ListTile(
          leading: Icon(Icons.numbers_outlined),
          title: Text('Sürüm'),
          subtitle: Text('1.0.0'),
        ),
      ],
    );
  }
}
