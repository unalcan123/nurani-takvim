import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme.dart';
import '../../daily_content/presentation/daily_content_page.dart';
import '../../favorites/presentation/favorites_page.dart';
import '../../settings/presentation/qibla_page.dart';
import 'dashboard_home_page.dart';
import 'nav_items.dart';
import 'prayer_times_page.dart';
import 'settings_hub_page.dart';

/// Seçili sekme. `AppShell` yeniden oluşturulsa bile (ör. konum seçimi
/// sonrası `pushAndRemoveUntil`) bu state global olarak kalıcıdır — bu
/// yüzden Ayarlar içinde bir işlem tamamlandığında sekme açıkça Ana
/// Sayfa'ya (0) resetlenmelidir, aksi halde kullanıcı Ayarlar'da kalmaya
/// devam eder.
final dashboardSelectedTabProvider = StateProvider<int>((ref) => 0);

// 1000px üstü "masaüstü sınıfı" kabul edilir — tipik telefon yatay
// genişlikleri (~700-950px) bunun altında kalır ve mobil (hamburger +
// alt hızlı menü) kabuğu kullanır, kalıcı bir sidebar rail'e sıkışmaz.
const _railBreakpoint = 1000.0;
const _extendedRailBreakpoint = 1300.0;

/// Uygulamanın tek navigasyon kabuğu: Scaffold/AppBar/Drawer/BottomNav
/// yalnızca burada tanımlanır. `_pages` içindeki her sayfa saf içeriktir
/// (kendi Scaffold/AppBar'ını içermez) — çift üst bar oluşmasını önler.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _pages = [
    DashboardHomePage(),
    DailyContentPage(),
    PrayerTimesPage(),
    FavoritesPage(),
    SettingsHubPage(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(dashboardSelectedTabProvider);
    final brightness = Theme.of(context).brightness;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _railBreakpoint;
        final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

        void onSelect(int i) => ref.read(dashboardSelectedTabProvider.notifier).state = i;

        if (!wide) {
          return Scaffold(
            drawer: _NavDrawer(selectedIndex: selectedIndex, onSelect: onSelect),
            floatingActionButton: isLandscape
                ? Builder(
                    builder: (fabContext) => FloatingActionButton.small(
                      backgroundColor: dashboardSidebarBg(brightness),
                      foregroundColor: dashboardAccentGold,
                      onPressed: () => Scaffold.of(fabContext).openDrawer(),
                      child: const Icon(Icons.menu),
                    ),
                  )
                : null,
            bottomNavigationBar: isLandscape
                ? null
                : NavigationBar(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: onSelect,
                    destinations: dashboardNavItems
                        .map(
                          (item) => NavigationDestination(
                            icon: Icon(item.icon),
                            selectedIcon: Icon(item.selectedIcon),
                            label: item.label,
                          ),
                        )
                        .toList(),
                  ),
            body: SafeArea(child: IndexedStack(index: selectedIndex, children: _pages)),
          );
        }

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                _SideRail(
                  extended: constraints.maxWidth >= _extendedRailBreakpoint,
                  selectedIndex: selectedIndex,
                  onSelect: onSelect,
                ),
                Expanded(child: IndexedStack(index: selectedIndex, children: _pages)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SideRail extends StatelessWidget {
  final bool extended;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _SideRail({required this.extended, required this.selectedIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Container(
      color: dashboardSidebarBg(brightness),
      child: NavigationRail(
        extended: extended,
        minExtendedWidth: 220,
        backgroundColor: dashboardSidebarBg(brightness),
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelect,
        leading: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: extended
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mosque_outlined, color: dashboardAccentGreen),
                    const SizedBox(width: 8),
                    Text('Nurani Takvim', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                )
              : Icon(Icons.mosque_outlined, color: dashboardAccentGreen),
        ),
        destinations: dashboardNavItems
            .map((item) => NavigationRailDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: Text(item.label),
                ))
            .toList(),
        trailing: Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: IconButton(
                tooltip: 'Kıble Yönü',
                icon: const Icon(Icons.navigation_outlined),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QiblaPage())),
              ),
            ),
          ),
        ),
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
                  Icon(Icons.mosque_outlined, color: dashboardAccentGreen, size: 32),
                  const SizedBox(width: 10),
                  const Text('Nurani Takvim', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            ...List.generate(dashboardNavItems.length, (i) {
              final item = dashboardNavItems[i];
              final selected = i == selectedIndex;
              return ListTile(
                leading: Icon(selected ? item.selectedIcon : item.icon, color: selected ? dashboardAccentGreen : null),
                title: Text(item.label, style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                selected: selected,
                onTap: () {
                  onSelect(i);
                  Navigator.pop(context);
                },
              );
            }),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.navigation_outlined),
              title: const Text('Kıble Yönü'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const QiblaPage()));
              },
            ),
          ],
        ),
      ),
    );
  }
}
