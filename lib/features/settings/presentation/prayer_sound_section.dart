import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio_manager.dart';
import '../../../core/notification_service.dart';
import '../../../core/prayer_alarm_coordinator.dart';
import '../data/adhan_library.dart';
import '../data/adhan_settings.dart';
import '../data/notification_capabilities.dart';
import 'alert_settings_controller.dart';

class PrayerSoundSection extends ConsumerStatefulWidget {
  const PrayerSoundSection({super.key});

  @override
  ConsumerState<PrayerSoundSection> createState() => _PrayerSoundSectionState();
}

class _PrayerSoundSectionState extends ConsumerState<PrayerSoundSection>
    with _PreviewRoute<PrayerSoundSection> {
  bool? _notificationsGranted;
  bool? _exactAlarmsGranted;
  bool? _fullScreenIntentGranted;
  String? get _playingKey => audio.previewKey.value;
  String? _selectedTitle;

  @override
  void initState() {
    super.initState();
    _refreshPermissionStatus();
    _refreshSelectedTitle();
  }

  Future<void> _refreshPermissionStatus() async {
    final service = ref.read(notificationServiceProvider);
    final granted = await service.areNotificationsEnabled();
    final fullScreenGranted = await service.canUseFullScreenIntent();
    if (!mounted) return;
    setState(() {
      _notificationsGranted = granted;
      _fullScreenIntentGranted = fullScreenGranted;
    });
  }

  Future<void> _requestPermissions() async {
    final result =
        await ref.read(notificationServiceProvider).requestPermissions();
    if (!mounted) return;
    setState(() {
      _notificationsGranted = result.notificationsGranted;
      _exactAlarmsGranted = result.exactAlarmsGranted;
      _fullScreenIntentGranted = result.fullScreenIntentGranted;
    });
    if (result.fullScreenIntentGranted == false) {
      await ref
          .read(notificationServiceProvider)
          .openFullScreenIntentSettings();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.notificationsGranted
              ? 'Bildirim izni verildi.'
              : 'Bildirim izni verilmedi.',
        ),
      ),
    );
  }

  Future<void> _refreshSelectedTitle() async {
    final settings = ref.read(alertSettingsProvider);
    final source = await resolveSelectedAdhan(
      prayer: PrayerType.dhuhr,
      settings: settings.adhanSettings,
      customAudioStore: ref.read(customAudioStoreProvider),
    );
    if (mounted) setState(() => _selectedTitle = source.title);
  }

  Future<void> _stopPreview() => audio.stopPreview(this);

  Future<void> _previewSource(String key, FutureOr<AdhanSource> source) async {
    if (!mounted) return;
    try {
      await audio.playPreview(this, key, source);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ezan önizlemesi başlatılamadı.')),
        );
      }
    }
  }

  Future<void> _previewCurrent() async {
    final settings = ref.read(alertSettingsProvider);
    await _previewSource(
      'current',
      resolveSelectedAdhan(
        prayer: PrayerType.dhuhr,
        settings: settings.adhanSettings,
        customAudioStore: ref.read(customAudioStoreProvider),
      ),
    );
  }

  Future<void> _selectMakkah() async {
    await ref.read(alertSettingsProvider.notifier).selectMakkahAdhan();
    await _refreshSelectedTitle();
  }

  Future<void> _selectMadinah() async {
    await ref.read(alertSettingsProvider.notifier).selectMadinahAdhan();
    await _refreshSelectedTitle();
  }

  Future<void> _pickCustomAdhan() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    if (picked.bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dosya okunamadı.')));
      return;
    }
    try {
      await ref
          .read(alertSettingsProvider.notifier)
          .addAndSelectCustomAdhan(picked.name, picked.bytes!);
      await _refreshSelectedTitle();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _openWorldAdhans() async {
    await _stopPreview();
    if (!mounted) return;
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const WorldAdhanPickerPage()),
    );
    if (selected == null) return;
    await ref.read(alertSettingsProvider.notifier).selectWorldAdhan(selected);
    await _refreshSelectedTitle();
  }

  Future<void> _sendTestNotification() async {
    await ref.read(notificationServiceProvider).showTestNotification();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Test bildirimi gönderildi.')));
  }

  Future<void> _runRealAlarmTest() async {
    await _stopPreview();
    await ref
        .read(prayerAlarmCoordinatorProvider)
        .triggerPrayerTime(prayerName: 'Öğle', isTest: true);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(alertSettingsProvider);
    final selectedType = settings.adhanSettings.type;
    final capabilities = NotificationCapabilities.current();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CapabilityBanner(capabilities: capabilities),
        const SizedBox(height: 12),
        _PermissionCard(
          granted: _notificationsGranted,
          exactAlarmsGranted: _exactAlarmsGranted,
          fullScreenIntentGranted: _fullScreenIntentGranted,
          onRequest: _requestPermissions,
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            'EZAN SESİ',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: Colors.grey),
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _AdhanChoiceTile(
                controls: _PreviewControls(
                  playing: _playingKey == 'makkah',
                  onListen:
                      () => _previewSource(
                        'makkah',
                        const AdhanSource.asset(
                          title: 'Mekke - Mescid-i Haram',
                          path: makkahNormalAdhanAsset,
                        ),
                      ),
                  onStop: _stopPreview,
                ),
                title: const Text('Mekke - Mescid-i Haram'),
                subtitle: const Text('Varsayılan ezan'),
                selected: selectedType == AdhanType.makkah,
                onSelect: () => _selectMakkah(),
              ),
              const Divider(height: 1),
              _AdhanChoiceTile(
                controls: _PreviewControls(
                  playing: _playingKey == 'madinah',
                  onListen:
                      () => _previewSource(
                        'madinah',
                        const AdhanSource.asset(
                          title: 'Medine - Mescid-i Nebevi',
                          path: madinahNormalAdhanAsset,
                        ),
                      ),
                  onStop: _stopPreview,
                ),
                title: const Text('Medine - Mescid-i Nebevi'),
                subtitle: const Text('Sabah için ayrı fecr kaydı kullanılır'),
                selected: selectedType == AdhanType.madinah,
                onSelect: () => _selectMadinah(),
              ),
              const Divider(height: 1),
              RadioListTile<AdhanType>(
                secondary: const Icon(Icons.chevron_right),
                title: const Text('Dünya Ezanları'),
                subtitle: Text(
                  selectedType == AdhanType.world && _selectedTitle != null
                      ? 'Seçili: $_selectedTitle'
                      : '200+ ezan arasından seç',
                ),
                value: AdhanType.world,
                groupValue: selectedType,
                onChanged: (_) => _openWorldAdhans(),
              ),
              const Divider(height: 1),
              RadioListTile<AdhanType>(
                secondary: const Icon(Icons.folder_open_outlined),
                title: const Text('Telefondan Ezan Seç'),
                subtitle: Text(
                  selectedType == AdhanType.custom && _selectedTitle != null
                      ? 'Seçili: $_selectedTitle'
                      : 'mp3, m4a, wav, ogg',
                ),
                value: AdhanType.custom,
                groupValue: selectedType,
                onChanged: (_) => _pickCustomAdhan(),
              ),
            ],
          ),
        ),
        if (_selectedTitle != null) ...[
          const SizedBox(height: 8),
          _AudioPreviewLayout(
            header: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Seçili: $_selectedTitle'),
            ),
            controls: _PreviewControls(
              playing: _playingKey == 'current',
              onListen: _previewCurrent,
              onStop: _stopPreview,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _sendTestNotification,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Bildirim Testi'),
              ),
            ),
            if (kDebugMode) ...[
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _runRealAlarmTest,
                  icon: const Icon(Icons.mosque_outlined),
                  label: const Text('Ezanı Şimdi Test Et'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class WorldAdhanPickerPage extends ConsumerStatefulWidget {
  const WorldAdhanPickerPage({super.key});

  @override
  ConsumerState<WorldAdhanPickerPage> createState() =>
      _WorldAdhanPickerPageState();
}

class _WorldAdhanPickerPageState extends ConsumerState<WorldAdhanPickerPage>
    with _PreviewRoute<WorldAdhanPickerPage> {
  final _library = AdhanLibraryService();
  final _searchController = TextEditingController();
  late Future<List<WorldAdhan>> _future;
  String _query = '';
  String? get _playingPath => audio.previewKey.value;

  @override
  void initState() {
    super.initState();
    _future = _library.loadWorldAdhans();
  }

  Future<void> _togglePreview(WorldAdhan item) async {
    try {
      await audio.playPreview(
        this,
        item.assetPath,
        AdhanSource.asset(title: item.title, path: item.assetPath),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ezan önizlemesi başlatılamadı.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedPath =
        ref.watch(alertSettingsProvider).adhanSettings.worldAssetPath;
    return Scaffold(
      appBar: AppBar(title: const Text('Dünya Ezanları')),
      body: FutureBuilder<List<WorldAdhan>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Ezan listesi okunamadı: ${snapshot.error}'),
            );
          }
          final allItems = snapshot.data ?? const <WorldAdhan>[];
          final query = _query.trim().toLowerCase();
          final items =
              query.isEmpty
                  ? allItems
                  : allItems
                      .where((item) => item.title.toLowerCase().contains(query))
                      .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Ezan ara',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final selected = selectedPath == item.assetPath;
                    final playing = _playingPath == item.assetPath;
                    return _AdhanChoiceTile(
                      title: Text(item.title),
                      selected: selected,
                      onSelect: () => Navigator.of(context).pop(item.assetPath),
                      controls: _PreviewControls(
                        playing: playing,
                        onListen: () => _togglePreview(item),
                        onStop: () => audio.stopPreview(this),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CapabilityBanner extends StatelessWidget {
  final NotificationCapabilities capabilities;
  const _CapabilityBanner({required this.capabilities});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${capabilities.platformLabel}: ${capabilities.note}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final bool? granted;
  final bool? exactAlarmsGranted;
  final bool? fullScreenIntentGranted;
  final VoidCallback onRequest;

  const _PermissionCard({
    required this.granted,
    required this.exactAlarmsGranted,
    required this.fullScreenIntentGranted,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    final statusText = switch (granted) {
      true => 'Bildirim izni verildi',
      false => 'Bildirim izni verilmedi',
      null => 'Bildirim izni durumu bilinmiyor',
    };
    final statusColor = switch (granted) {
      true => Colors.green,
      false => Colors.redAccent,
      null => Colors.grey,
    };

    return Card(
      child: ListTile(
        leading: Icon(Icons.notifications_outlined, color: statusColor),
        title: Text(statusText),
        subtitle: _permissionWarning(),
        trailing: TextButton(
          onPressed: onRequest,
          child: const Text('İzin İste'),
        ),
      ),
    );
  }

  Widget? _permissionWarning() {
    final warnings = <String>[
      if (exactAlarmsGranted == false)
        'Kesin alarm izni gerekli olabilir (Android 12+).',
      if (fullScreenIntentGranted == false)
        'Tam ekran bildirim izni kapalı görünüyor (Android 14+).',
    ];
    if (warnings.isEmpty) return null;
    return Text(
      '${warnings.join(' ')} Namaz vakti alarmı zamanında veya tam ekran açılmayabilir.',
    );
  }
}

/// Stop previews when a new route covers the settings as well as on removal.
mixin _PreviewRoute<T extends ConsumerStatefulWidget> on ConsumerState<T>
    implements RouteAware {
  late final AudioManager audio;
  ModalRoute<dynamic>? _route;
  @override
  void initState() {
    super.initState();
    audio = ref.read(audioManagerProvider);
    audio.previewKey.addListener(_previewChanged);
  }

  void _previewChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route == route) return;
    previewRouteObserver.unsubscribe(this);
    _route = route;
    if (route != null) previewRouteObserver.subscribe(this, route);
  }

  @override
  void didPushNext() {
    unawaited(audio.stopPreview(this));
  }

  @override
  void didPop() {
    unawaited(audio.stopPreview(this));
  }

  @override
  void didPush() {}
  @override
  void didPopNext() {}
  @override
  void dispose() {
    previewRouteObserver.unsubscribe(this);
    audio.previewKey.removeListener(_previewChanged);
    unawaited(audio.stopPreview(this));
    super.dispose();
  }
}

class _PreviewControls extends StatelessWidget {
  const _PreviewControls({
    required this.playing,
    required this.onListen,
    required this.onStop,
  });
  final bool playing;
  final VoidCallback onListen;
  final VoidCallback onStop;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      OutlinedButton.icon(
        onPressed: onListen,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Dinle'),
      ),
      OutlinedButton.icon(
        onPressed: playing ? onStop : null,
        icon: const Icon(Icons.stop),
        label: const Text('Durdur'),
      ),
    ],
  );
}

/// Controls are never placed in ListTile's height-constrained trailing slot.
class _AudioPreviewLayout extends StatelessWidget {
  const _AudioPreviewLayout({required this.header, required this.controls});
  final Widget header;
  final Widget controls;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final actions = Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: controls,
      );
      if (constraints.maxWidth >= 600 &&
          MediaQuery.textScalerOf(context).scale(14) <= 20) {
        return Row(children: [Expanded(child: header), actions]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Align(alignment: AlignmentDirectional.centerEnd, child: actions),
        ],
      );
    },
  );
}

class _AdhanChoiceTile extends StatelessWidget {
  const _AdhanChoiceTile({
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onSelect,
    required this.controls,
  });
  final Widget title;
  final Widget? subtitle;
  final bool selected;
  final VoidCallback onSelect;
  final Widget controls;

  @override
  Widget build(BuildContext context) => _AudioPreviewLayout(
    header: RadioListTile<bool>(
      title: title,
      subtitle: subtitle,
      value: true,
      groupValue: selected,
      onChanged: (_) => onSelect(),
    ),
    controls: controls,
  );
}
