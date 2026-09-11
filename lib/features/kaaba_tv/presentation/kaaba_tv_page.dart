import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../media/player/media_player_controller.dart';

const _kaabaTvUrl = 'https://makkahlive.net/';

class KaabaTvPage extends ConsumerStatefulWidget {
  const KaabaTvPage({super.key});

  @override
  ConsumerState<KaabaTvPage> createState() => _KaabaTvPageState();
}

enum _LoadState { loading, ready, error }

class _KaabaTvPageState extends ConsumerState<KaabaTvPage> {
  late final WebViewController _controller;
  _LoadState _state = _LoadState.loading;

  @override
  void initState() {
    super.initState();
    // Kabe TV kendi sesiyle geliyor; aynı anda Kuran/Hadis dinleniyorsa
    // ikisinin sesi çakışmasın diye durdur.
    ref.read(mediaPlayerControllerProvider).stop();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _state = _LoadState.ready);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _state = _LoadState.error);
          },
        ),
      )
      ..loadRequest(Uri.parse(_kaabaTvUrl));

    Future.delayed(const Duration(seconds: 12), () {
      if (mounted && _state == _LoadState.loading) {
        setState(() => _state = _LoadState.error);
      }
    });
  }

  Future<void> _openInBrowser() async {
    await launchUrl(Uri.parse(_kaabaTvUrl), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kabe Canlı TV')),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_state == _LoadState.loading)
            const Center(child: CircularProgressIndicator()),
          if (_state == _LoadState.error)
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.live_tv_outlined, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'Canlı yayın bu ekranda yüklenemedi.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _openInBrowser,
                        icon: const Icon(Icons.open_in_browser),
                        label: const Text('Tarayıcıda Aç'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
