import 'package:flutter/material.dart';

class NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const NavItem({required this.icon, required this.selectedIcon, required this.label});
}

const dashboardNavItems = [
  NavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Ana Sayfa'),
  NavItem(icon: Icons.auto_stories_outlined, selectedIcon: Icons.auto_stories, label: 'Günlük İçerik'),
  NavItem(icon: Icons.access_time_outlined, selectedIcon: Icons.access_time_filled, label: 'Namaz Vakitleri'),
  NavItem(icon: Icons.favorite_border, selectedIcon: Icons.favorite, label: 'Favoriler'),
  NavItem(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: 'Ayarlar'),
];
