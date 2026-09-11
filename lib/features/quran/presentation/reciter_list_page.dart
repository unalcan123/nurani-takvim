import 'package:flutter/material.dart';

import '../../media/player/now_playing_bar.dart';
import '../data/mp3quran_reciter_service.dart';
import 'reciter_surah_list_page.dart';

class ReciterListPage extends StatefulWidget {
  const ReciterListPage({super.key});

  @override
  State<ReciterListPage> createState() => _ReciterListPageState();
}

class _ReciterListPageState extends State<ReciterListPage> {
  final _service = Mp3QuranReciterService();
  final _searchController = TextEditingController();
  late Future<List<QuranReciter>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _service.loadReciters();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    setState(() => _future = _service.loadReciters(forceRefresh: true));
  }

  void _openReciter(QuranReciter reciter) {
    final moshaflar = reciter.moshaflar;
    if (moshaflar.isEmpty) return;
    if (moshaflar.length == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReciterSurahListPage(
            reciter: reciter,
            moshaf: moshaflar.first,
          ),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in moshaflar)
              ListTile(
                title: Text(m.name),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReciterSurahListPage(
                        reciter: reciter,
                        moshaf: m,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kuran Dinle')),
      body: FutureBuilder<List<QuranReciter>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off, size: 40),
                  const SizedBox(height: 12),
                  const Text('Hafız listesi alınamadı.'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _retry, child: const Text('Tekrar Dene')),
                ],
              ),
            );
          }
          final all = snapshot.data ?? const <QuranReciter>[];
          final query = _query.trim().toLowerCase();
          final items = query.isEmpty
              ? all
              : all.where((r) => r.name.toLowerCase().contains(query)).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Hafız ara',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final reciter = items[index];
                    return ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(reciter.name),
                      subtitle: reciter.moshaflar.length > 1
                          ? Text('${reciter.moshaflar.length} rivayet')
                          : null,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openReciter(reciter),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: const NowPlayingBar(),
    );
  }
}
