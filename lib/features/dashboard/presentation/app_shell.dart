import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme.dart';
import '../../daily_content/presentation/daily_content_page.dart';
import '../../favorites/presentation/favorites_page.dart';
import '../../media/presentation/media_hub_page.dart';
import '../../settings/presentation/qibla_page.dart';
import 'dashboard_home_page.dart';
import 'nav_items.dart';
import 'settings_hub_page.dart';

/// Seçili sekme. `AppShell` yeniden oluşturulsa bile (ör. konum seçimi
/// sonrası `pushAndRemoveUntil`) bu state global olarak kalıcıdır — bu
/// yüzden Ayarlar içinde bir işlem tamamlandığında sekme açıkça Ana
/// Sayfa'ya (0) resetlenmelidir, aksi halde kullanıcı Ayarlar'da kalmaya
/// devam eder.
final dashboardSelectedTabProvider = StateProvider<int>((ref) => 0);

/// Navigation stays in a drawer at every screen size.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});
  static const _pages = [
    DashboardHomePage(),
    DailyContentPage(),
    FavoritesPage(),
    SettingsHubPage(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(dashboardSelectedTabProvider);
    final brightness = Theme.of(context).brightness;
    return Scaffold(
      backgroundColor: dashboardBg(brightness),
      drawer: _NavDrawer(
        selectedIndex: selectedIndex,
        onSelect: (i) => ref.read(dashboardSelectedTabProvider.notifier).state = i,
      ),
      floatingActionButton: selectedIndex == 0 ? null : Builder(
        builder: (context) => FloatingActionButton.extended(
          tooltip: 'Menüyü aç',
          backgroundColor: dashboardAccentGreen,
          foregroundColor: Colors.white,
          onPressed: () => Scaffold.of(context).openDrawer(),
          icon: const Icon(Icons.menu),
          label: const Text('Menü'),
        ),
      ),
      body: SafeArea(
        child: IndexedStack(index: selectedIndex, children: _pages),
      ),
    );
  }
}

class _NavDrawer extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _NavDrawer({required this.selectedIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Drawer(
      backgroundColor: dashboardSidebarBg(brightness),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              child: Row(
                children: [
                  Icon(
                    Icons.mosque_outlined,
                    color: dashboardAccentGreen,
                    size: 32,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: Text(
                    'Nuranî Takvim',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  )),
                ],
              ),
            ),
            ...List.generate(dashboardNavItems.length, (i) {
              final item = dashboardNavItems[i];
              final selected = i == selectedIndex;
              return ListTile(
                leading: Icon(
                  selected ? item.selectedIcon : item.icon,
                  color: selected ? dashboardAccentGreen : null,
                ),
                title: Text(
                  item.label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: selected,
                onTap: () {
                  onSelect(i);
                  Navigator.pop(context);
                },
              );
            }),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.headphones_outlined),
              title: const Text('Dinle'),
              subtitle: const Text('Kuran, Hadis, Kabe Canlı TV'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MediaHubPage()),
                );
              },
            ),
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
          ],
        ),
      ),
    );
  }
}
