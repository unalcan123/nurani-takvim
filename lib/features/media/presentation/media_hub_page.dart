import 'package:flutter/material.dart';

import '../../hadith/presentation/hadith_library_page.dart';
import '../../kaaba_tv/presentation/kaaba_tv_page.dart';
import '../../quran/presentation/reciter_list_page.dart';
import '../player/now_playing_bar.dart';

class MediaHubPage extends StatelessWidget {
  const MediaHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dinle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _MediaCard(
            icon: Icons.menu_book_outlined,
            title: 'Kuran Dinle',
            subtitle: '100+ hafız, tüm sûreler',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReciterListPage()),
            ),
          ),
          const SizedBox(height: 12),
          _MediaCard(
            icon: Icons.eco_outlined,
            title: 'Hadis Dinle',
            subtitle: 'Riyazüs Salihin (İmam Nevevî)',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HadithLibraryPage()),
            ),
          ),
          const SizedBox(height: 12),
          _MediaCard(
            icon: Icons.live_tv_outlined,
            title: 'Kabe Canlı TV',
            subtitle: 'Mescid-i Haram canlı yayın',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const KaabaTvPage()),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const NowPlayingBar(),
    );
  }
}

class _MediaCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MediaCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
