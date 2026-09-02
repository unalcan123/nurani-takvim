import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/daily_content/presentation/daily_content_page.dart';
import '../features/locations/presentation/country_page.dart';
import '../features/locations/presentation/recent_locations_page.dart';
import '../features/settings/presentation/mode_controller.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/settings/presentation/slide_settings_page.dart';
import '../features/settings/presentation/qibla_page.dart';
import '../features/settings/presentation/bg_music_settings_page.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final appMode = ref.watch(modeProvider);

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.8),
            ),
            child: Text(
              'Ezan Vakti',
              style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('Namaz Vakitleri'),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.history_outlined),
            title: const Text('Son Konumlarım'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RecentLocationsPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Yeni Konum Seç'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CountryPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('Günlük İçerik'),
            subtitle: const Text('Âyet, hadis, tarihte bugün, söz'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DailyContentPage()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.navigation_outlined),
            title: const Text('Kıble Yönü'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const QiblaPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Slayt ve Foto Ayarları'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SlideSettingsPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: const Text('Müzik Ayarları'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BgMusicSettingsPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Uygulama Ayarları'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
          const Divider(),
          SwitchListTile(
            secondary: const Icon(Icons.tv_outlined),
            title: const Text('TV Modu'),
            value: appMode == AppMode.tv,
            onChanged: (bool value) {
              ref.read(modeProvider.notifier).toggleMode();
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Hakkında'),
            onTap: () {
              Navigator.pop(context);
              showAboutDialog(
                context: context,
                applicationName: 'Ezan Vakti',
                applicationVersion: '1.0.0',
                applicationLegalese: 'Unal S. tarafından geliştirilmiştir.',
              );
            },
          ),
        ],
      ),
    );
  }
}
