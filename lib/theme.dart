import 'package:flutter/material.dart';

// --- Light Theme --- //
const Color lightPrimaryColor = Color(0xFF6C8D7D);
const Color lightAccentColor = Color(0xFFC89B7B);
const Color lightBackgroundColor = Color(0xFFF0F2F5);
const Color lightCardColor = Colors.white;
const Color lightTextColor = Color(0xFF1A1A1A);

final lightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  scaffoldBackgroundColor: lightBackgroundColor,
  primaryColor: lightPrimaryColor,
  colorScheme: const ColorScheme.light(
    primary: lightPrimaryColor,
    secondary: lightAccentColor,
    surface: lightCardColor,
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: lightTextColor,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: lightBackgroundColor,
    foregroundColor: lightTextColor, 
    elevation: 0,
    centerTitle: true,
  ),
  cardTheme: CardThemeData(
    color: lightCardColor,
    elevation: 1,
    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: Colors.grey.shade200, width: 1),
    ),
  ),
  listTileTheme: ListTileThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: lightCardColor,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
  ),
);


// --- Dark Theme --- //
const Color darkPrimaryColor = Color(0xFF4A90E2);
const Color darkAccentColor = Color(0xFFF5A623);
const Color darkBackgroundColor = Color(0xFF121212);
const Color darkCardColor = Color(0xFF1E1E1E);

final darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: darkBackgroundColor,
  primaryColor: darkPrimaryColor,
  colorScheme: const ColorScheme.dark(
    primary: darkPrimaryColor,
    secondary: darkAccentColor,
    surface: darkCardColor,
    onPrimary: Colors.white,
    onSecondary: Colors.black,
    onSurface: Colors.white,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: darkBackgroundColor,
    elevation: 0,
    centerTitle: true,
  ),
  cardTheme: CardThemeData(
    color: darkCardColor,
    elevation: 2,
    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
  listTileTheme: ListTileThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: darkCardColor,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  ),
);

// Default to appTheme being the light one
final appTheme = lightTheme;

// --- "Nurani Takvim" Dashboard Palette --- //
// Açık mod: krem/taş zemin + koyu yeşil + altın detaylar.
const Color dashboardBgLight = Color(0xFFF6F1E9);
const Color dashboardSidebarLight = Color(0xFFFFFFFF);
const Color dashboardCardGreenLight = Color(0xFFE7EFE8);
const Color dashboardCardGoldLight = Color(0xFFF3E8D2);

// Koyu mod: lacivert zemin + koyu yeşil kartlar + altın detaylar.
const Color dashboardBgDark = Color(0xFF0B1220);
const Color dashboardSidebarDark = Color(0xFF10192B);
const Color dashboardCardGreenDark = Color(0xFF16261F);
const Color dashboardCardGoldDark = Color(0xFF241C10);

// İki modda da sabit kalan vurgu renkleri.
const Color dashboardAccentGreen = Color(0xFF2F4B3C);
const Color dashboardAccentGold = Color(0xFFC9A15A);

// TV Modu (kiosk ekranı) zemini — koyu lacivert, mevcut beyaz metinlerle
// yeterli kontrast sağlar.
const Color tvBgDark = Color(0xFF0B1220);

Color dashboardBg(Brightness b) => b == Brightness.dark ? dashboardBgDark : dashboardBgLight;
Color dashboardSidebarBg(Brightness b) => b == Brightness.dark ? dashboardSidebarDark : dashboardSidebarLight;
Color dashboardCardGreen(Brightness b) => b == Brightness.dark ? dashboardCardGreenDark : dashboardCardGreenLight;
Color dashboardCardGold(Brightness b) => b == Brightness.dark ? dashboardCardGoldDark : dashboardCardGoldLight;

// Ana Sayfa'daki "takvim kartı" yüzeyleri (şehir kartı krem, geri sayım
// kartı beyaz) — koyu modda lacivert kart tonlarına döner.
const Color dashboardSurfaceCreamLight = Color(0xFFF7F0E1);
const Color dashboardSurfaceCreamDark = Color(0xFF16213A);
const Color dashboardSurfaceWhiteLight = Colors.white;
const Color dashboardSurfaceWhiteDark = Color(0xFF10192B);
const Color dashboardBorderLight = Color(0xFFE0DDD5);
const Color dashboardBorderDark = Color(0xFF283552);
const Color dashboardInkLight = Color(0xFF242B30);
const Color dashboardInkDark = Color(0xFFE8EAED);
const Color dashboardMutedLight = Color(0xFF62635E);
const Color dashboardMutedDark = Color(0xFF9AA3AE);
const Color dashboardActiveCellLight = Color(0xFFF4E6C5);
const Color dashboardActiveCellDark = Color(0xFF3A2E12);

Color dashboardSurfaceCream(Brightness b) =>
    b == Brightness.dark ? dashboardSurfaceCreamDark : dashboardSurfaceCreamLight;
Color dashboardSurfaceWhite(Brightness b) =>
    b == Brightness.dark ? dashboardSurfaceWhiteDark : dashboardSurfaceWhiteLight;
Color dashboardBorder(Brightness b) =>
    b == Brightness.dark ? dashboardBorderDark : dashboardBorderLight;
Color dashboardInk(Brightness b) => b == Brightness.dark ? dashboardInkDark : dashboardInkLight;
Color dashboardMuted(Brightness b) => b == Brightness.dark ? dashboardMutedDark : dashboardMutedLight;
Color dashboardActiveCell(Brightness b) =>
    b == Brightness.dark ? dashboardActiveCellDark : dashboardActiveCellLight;
