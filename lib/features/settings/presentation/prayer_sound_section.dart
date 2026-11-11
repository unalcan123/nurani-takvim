import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio_manager.dart';
import '../../../core/notification_service.dart';
import '../../../core/prayer_alarm_coordinator.dart';
import '../../../theme.dart';
import '../data/adhan_settings.dart';
import '../data/alert_settings.dart';
import '../data/custom_audio_store.dart';
import '../data/ezan_library.dart';
import '../data/notification_capabilities.dart';
import 'alert_settings_controller.dart';
import 'fajr_delay_setting.dart';

/// Bir vaktin şu an çalacağı ezanın adı (önizlemede ve alarmda duyulanla aynı
/// çözümleme kullanılır, böylece ekranda yazan ile çalan hiç ayrışmaz).
final prayerAdhanTitleProvider =
    FutureProvider.autoDispose.family<String, PrayerType>((ref, prayer) async {
      final settings = ref.watch(
        alertSettingsProvider.select((s) => s.adhanSettings),
      );
      final source = await resolveSelectedAdhan(
        prayer: prayer,
        settings: settings,
        customAudioStore: ref.read(customAudioStoreProvider),
      );
      return source.title;
    });

String _prayerLabel(PrayerType prayer) => switch (prayer) {
  PrayerType.fajr => 'İmsak',
  PrayerType.dhuhr => 'Öğle',
  PrayerType.asr => 'İkindi',
  PrayerType.maghrib => 'Akşam',
  PrayerType.isha => 'Yatsı',
};

AdhanSource _defaultSource(PrayerType prayer) => AdhanSource.asset(
  title: prayer.isFajr ? 'Mekke - Sabah Ezanı' : 'Mekke - Mescid-i Haram',
  path: prayer.isFajr ? makkahFajrAdhanAsset : makkahNormalAdhanAsset,
);

/// Ayarlar sayfasındaki bölüm başlığı: düz cümle başlığı ve isteğe bağlı
/// kısa açıklama.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.title, {super.key, this.caption});
  final String title;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 28, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              style: text.bodyMedium?.copyWith(color: dashboardMuted(b)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Vakit başına alarm anahtarı + o vaktin kendi ezanı + dinleme düğmesi.
class PrayerSoundSection extends ConsumerStatefulWidget {
  const PrayerSoundSection({super.key});

  @override
  ConsumerState<PrayerSoundSection> createState() => _PrayerSoundSectionState();
}

class _PrayerSoundSectionState extends ConsumerState<PrayerSoundSection>
    with _PreviewRoute<PrayerSoundSection> {
  Future<void> _preview(PrayerType prayer) async {
    final settings = ref.read(alertSettingsProvider);
    try {
      await audio.playPreview(
        this,
        'prayer:${prayer.name}',
        resolveSelectedAdhan(
          prayer: prayer,
          settings: settings.adhanSettings,
          customAudioStore: ref.read(customAudioStoreProvider),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ezan önizlemesi başlatılamadı.')),
      );
    }
  }

  Future<void> _openPicker(PrayerType prayer) async {
    await audio.stopPreview();
    if (!mounted) return;
    await showAdhanPicker(context, prayer);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(alertSettingsProvider);
    final controller = ref.read(alertSettingsProvider.notifier);
    final playing = audio.previewKey.value;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final prayer in PrayerType.values) ...[
            if (prayer != PrayerType.fajr) const Divider(height: 1),
            _PrayerRow(
              key: ValueKey('prayer-row-${prayer.name}'),
              prayer: prayer,
              enabled: settings.isPrayerEnabled(_prayerLabel(prayer)),
              isDefault: !settings.adhanSettings.perPrayer.containsKey(prayer),
              playing: playing == 'prayer:${prayer.name}',
              onToggle:
                  (v) => controller.togglePrayerAlarm(_prayerLabel(prayer), v),
              onChoose: () => _openPicker(prayer),
              onPlay: () => _preview(prayer),
              onStop: () => audio.stopPreview(this),
            ),
            if (prayer.isFajr) const FajrDelaySetting(),
          ],
        ],
      ),
    );
  }
}

class _PrayerRow extends ConsumerWidget {
  const _PrayerRow({
    super.key,
    required this.prayer,
    required this.enabled,
    required this.isDefault,
    required this.playing,
    required this.onToggle,
    required this.onChoose,
    required this.onPlay,
    required this.onStop,
  });

  final PrayerType prayer;
  final bool enabled;
  final bool isDefault;
  final bool playing;
  final ValueChanged<bool> onToggle;
  final VoidCallback onChoose;
  final VoidCallback onPlay;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final title = ref.watch(prayerAdhanTitleProvider(prayer)).valueOrNull;
    final label = _prayerLabel(prayer);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: enabled ? 1 : 0.6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _AdhanPill(
                    title: title ?? '…',
                    isDefault: isDefault,
                    semanticLabel: '$label ezanını değiştir',
                    onTap: onChoose,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          PlayToggleButton(playing: playing, onPlay: onPlay, onStop: onStop),
          const SizedBox(width: 4),
          Semantics(
            label: '$label alarmı',
            child: Switch(
              value: enabled,
              activeTrackColor: dashboardAccentGold,
              onChanged: onToggle,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdhanPill extends StatelessWidget {
  const _AdhanPill({
    required this.title,
    required this.isDefault,
    required this.semanticLabel,
    required this.onTap,
  });
  final String title;
  final bool isDefault;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final muted = dashboardMuted(b);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: dashboardActiveCell(b).withValues(alpha: 0.55),
        shape: StadiumBorder(side: BorderSide(color: dashboardBorder(b))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.graphic_eq, size: 18, color: dashboardAccentGold),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        text: title,
                        children: [
                          if (isDefault)
                            TextSpan(
                              text: '  ·  varsayılan',
                              style: TextStyle(color: muted),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, color: muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tek düğme: çalmıyorsa "Dinle", çalıyorsa "Durdur".
class PlayToggleButton extends StatelessWidget {
  const PlayToggleButton({
    super.key,
    required this.playing,
    required this.onPlay,
    required this.onStop,
  });
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return IconButton(
      tooltip: playing ? 'Durdur' : 'Dinle',
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      style: IconButton.styleFrom(
        backgroundColor:
            playing
                ? dashboardAccentGold
                : dashboardBorder(b).withValues(alpha: 0.6),
        foregroundColor: playing ? Colors.black : null,
      ),
      onPressed: playing ? onStop : onPlay,
      icon: Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
    );
  }
}

/// Vakit girmeden önce uyarı seçimleri ve ezan ses düzeyi.
class ReminderAndVolumeCard extends ConsumerStatefulWidget {
  const ReminderAndVolumeCard({super.key});

  @override
  ConsumerState<ReminderAndVolumeCard> createState() =>
      _ReminderAndVolumeCardState();
}

class _ReminderAndVolumeCardState extends ConsumerState<ReminderAndVolumeCard> {
  double? _dragVolume;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(alertSettingsProvider);
    final controller = ref.read(alertSettingsProvider.notifier);
    final theme = Theme.of(context);
    final muted = dashboardMuted(theme.brightness);
    final volume = _dragVolume ?? settings.ezanVolume;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ezan ses düzeyi', style: theme.textTheme.titleMedium),
            Row(
              children: [
                Icon(Icons.volume_down_rounded, color: muted),
                Expanded(
                  child: Slider(
                    value: volume,
                    activeColor: dashboardAccentGold,
                    label: '%${(volume * 100).round()}',
                    divisions: 20,
                    onChanged: (v) => setState(() => _dragVolume = v),
                    onChangeEnd: (v) async {
                      await controller.setEzanVolume(v);
                      if (mounted) setState(() => _dragVolume = null);
                    },
                  ),
                ),
                Icon(Icons.volume_up_rounded, color: muted),
              ],
            ),
            const Divider(height: 32),
            Text('Vakit girmeden önce uyar', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              'Kısa bir uyarı sesi çalar. İmsak vaktinde uyarı yapılmaz.',
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final minute in preNotificationMinutes)
                  FilterChip(
                    label: Text('$minute dakika kala'),
                    selected: settings.isPreNotificationEnabled(minute),
                    selectedColor: dashboardAccentGold.withValues(alpha: 0.3),
                    onSelected:
                        (v) => controller.togglePreNotification(minute, v),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bildirim izinleri, platform notu ve deneme düğmeleri.
class AlarmDiagnosticsCard extends ConsumerStatefulWidget {
  const AlarmDiagnosticsCard({super.key});

  @override
  ConsumerState<AlarmDiagnosticsCard> createState() =>
      _AlarmDiagnosticsCardState();
}

class _AlarmDiagnosticsCardState extends ConsumerState<AlarmDiagnosticsCard> {
  bool? _notificationsGranted;
  bool? _exactAlarmsGranted;
  bool? _fullScreenIntentGranted;

  @override
  void initState() {
    super.initState();
    _refreshPermissionStatus();
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
    final service = ref.read(notificationServiceProvider);
    final result = await service.requestPermissions();
    if (!mounted) return;
    setState(() {
      _notificationsGranted = result.notificationsGranted;
      _exactAlarmsGranted = result.exactAlarmsGranted;
      _fullScreenIntentGranted = result.fullScreenIntentGranted;
    });
    if (result.fullScreenIntentGranted == false) {
      await service.openFullScreenIntentSettings();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.notificationsGranted
              ? 'Bildirim izni verildi.'
              : 'Bildirim izni verilmedi. Telefon ayarlarından açabilirsiniz.',
        ),
      ),
    );
  }

  Future<void> _sendTestNotification() async {
    await ref.read(notificationServiceProvider).showTestNotification();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Test bildirimi gönderildi.')));
  }

  Future<void> _runRealAlarmTest() async {
    await ref.read(audioManagerProvider).stopPreview();
    await ref
        .read(prayerAlarmCoordinatorProvider)
        .triggerPrayerTime(prayerName: 'Öğle', isTest: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = dashboardMuted(theme.brightness);
    final capabilities = NotificationCapabilities.current();
    final granted = _notificationsGranted;
    final warnings = <String>[
      if (_exactAlarmsGranted == false)
        'Kesin alarm izni kapalı (Android 12+).',
      if (_fullScreenIntentGranted == false)
        'Tam ekran bildirim izni kapalı (Android 14+).',
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(
                granted == true
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                color:
                    granted == true
                        ? dashboardAccentGold
                        : granted == false
                        ? theme.colorScheme.error
                        : muted,
              ),
              title: Text(switch (granted) {
                true => 'Bildirimlere izin verildi',
                false => 'Bildirimlere izin verilmedi',
                null => 'Bildirim izni denetleniyor',
              }),
              subtitle:
                  warnings.isEmpty
                      ? null
                      : Text(
                        '${warnings.join(' ')} Ezan zamanında veya tam ekran '
                        'açılmayabilir.',
                      ),
              trailing:
                  granted == true && warnings.isEmpty
                      ? null
                      : FilledButton.tonal(
                        onPressed: _requestPermissions,
                        child: const Text('İzin ver'),
                      ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '${capabilities.platformLabel}: ${capabilities.note}',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _sendTestNotification,
                    icon: const Icon(Icons.notifications_outlined),
                    label: const Text('Bildirim gönder'),
                  ),
                  if (kDebugMode)
                    OutlinedButton.icon(
                      onPressed: _runRealAlarmTest,
                      icon: const Icon(Icons.mosque_outlined),
                      label: const Text('Ezanı şimdi dene'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bir vaktin ezanını seçtiren alt sayfa. İmsak için yalnızca sabah (fecr)
/// kayıtları, diğer vakitler için yalnızca normal kayıtlar listelenir.
Future<void> showAdhanPicker(BuildContext context, PrayerType prayer) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder:
        (_) => FractionallySizedBox(
          heightFactor: 0.92,
          child: AdhanPickerSheet(prayer: prayer),
        ),
  );
}

class AdhanPickerSheet extends ConsumerStatefulWidget {
  const AdhanPickerSheet({super.key, required this.prayer});
  final PrayerType prayer;

  @override
  ConsumerState<AdhanPickerSheet> createState() => _AdhanPickerSheetState();
}

class _AdhanPickerSheetState extends ConsumerState<AdhanPickerSheet>
    with _PreviewRoute<AdhanPickerSheet> {
  final _libraryService = EzanLibraryService();
  final _downloadCache = EzanDownloadCache();
  late final Future<EzanLibraryManifest> _future = _load();
  final Map<String, double> _progress = {};
  final Set<String> _cached = {};
  String _query = '';
  bool _applyToAll = false;

  PrayerType get prayer => widget.prayer;

  Future<EzanLibraryManifest> _load() async {
    final manifest = await _libraryService.loadManifest();
    final checks = await Future.wait(
      manifest.entries.map(
        (e) async {
          // Önbellek okunamazsa liste yine gösterilir; kayıt "indirilir" görünür.
          try {
            return MapEntry(e.id, await _downloadCache.isCached(e));
          } catch (_) {
            return MapEntry(e.id, e.source == EzanLibrarySource.asset);
          }
        },
      ),
    );
    if (mounted) {
      setState(() {
        _cached.addAll(checks.where((c) => c.value).map((c) => c.key));
      });
    }
    return manifest;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _close() async {
    await audio.stopPreview();
    if (mounted) Navigator.of(context).pop();
  }

  Future<AdhanSource?> _sourceFor(
    EzanLibraryManifest manifest,
    EzanLibraryEntry entry,
  ) async {
    if (entry.source == EzanLibrarySource.asset) {
      return AdhanSource.asset(title: entry.title, path: entry.assetPath!);
    }
    setState(() => _progress[entry.id] = 0);
    try {
      final bytes = await _downloadCache.ensureDownloaded(
        entry,
        baseUrl: manifest.baseUrl,
        onProgress: (p) {
          if (mounted) setState(() => _progress[entry.id] = p);
        },
      );
      if (mounted) setState(() => _cached.add(entry.id));
      return AdhanSource.custom(
        title: entry.title,
        file: CustomAudioFile(
          id: entry.id,
          fileName: '${entry.title}.mp3',
          bytes: bytes,
          addedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      _showError('İndirilemedi. İnternet bağlantınızı kontrol edip yeniden deneyin.');
      return null;
    } finally {
      if (mounted) setState(() => _progress.remove(entry.id));
    }
  }

  Future<void> _preview(String key, FutureOr<AdhanSource?> source) async {
    final resolved = await source;
    if (resolved == null || !mounted) return;
    try {
      await audio.playPreview(this, key, resolved);
    } catch (_) {
      _showError('Ezan önizlemesi başlatılamadı.');
    }
  }

  Future<void> _selectEntry(
    EzanLibraryManifest manifest,
    EzanLibraryEntry entry,
  ) async {
    final needsDownload =
        entry.source == EzanLibrarySource.remote && !_cached.contains(entry.id);
    if (needsDownload) setState(() => _progress[entry.id] = 0);
    try {
      await ref
          .read(alertSettingsProvider.notifier)
          .setPrayerAdhan(
            prayer,
            entry,
            baseUrl: manifest.baseUrl,
            downloadCache: _downloadCache,
            applyToAllNormal: _applyToAll,
            onProgress:
                needsDownload
                    ? (p) {
                      if (mounted) setState(() => _progress[entry.id] = p);
                    }
                    : null,
          );
      await _close();
    } on ArgumentError catch (e) {
      _showError('${e.message}');
    } catch (_) {
      _showError('İndirilemedi. İnternet bağlantınızı kontrol edip yeniden deneyin.');
    } finally {
      if (mounted) setState(() => _progress.remove(entry.id));
    }
  }

  Future<void> _selectDefault() async {
    final controller = ref.read(alertSettingsProvider.notifier);
    final targets =
        _applyToAll && !prayer.isFajr
            ? PrayerType.values.where((p) => !p.isFajr)
            : [prayer];
    for (final p in targets) {
      await controller.resetPrayerAdhan(p);
    }
    await _close();
  }

  Future<void> _pickFromPhone() async {
    await audio.stopPreview();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    if (picked.bytes == null) {
      _showError('Dosya okunamadı.');
      return;
    }
    try {
      await ref
          .read(alertSettingsProvider.notifier)
          .setPrayerCustomAdhan(prayer, picked.name, picked.bytes!);
      await _close();
    } catch (e) {
      _showError('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = dashboardMuted(theme.brightness);
    final token = ref.watch(
      alertSettingsProvider.select((s) => s.adhanSettings.perPrayer[prayer]),
    );
    final playing = audio.previewKey.value;
    final label = _prayerLabel(prayer);
    final otherNormals = PrayerType.values
        .where((p) => !p.isFajr)
        .map(_prayerLabel)
        .join(', ');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<EzanLibraryManifest>(
        future: _future,
        builder: (context, snapshot) {
          final manifest = snapshot.data;
          final query = _query.trim().toLowerCase();
          final entries =
              manifest == null
                  ? const <EzanLibraryEntry>[]
                  : (prayer.isFajr
                          ? manifest.fajrEntries
                          : manifest.normalEntries)
                      // Mekke kayıtları zaten en üstteki "varsayılan" satırı.
                      .where(
                        (e) =>
                            e.assetPath != makkahNormalAdhanAsset &&
                            e.assetPath != makkahFajrAdhanAsset &&
                            (query.isEmpty ||
                                e.title.toLowerCase().contains(query)),
                      )
                      .toList();
          final onDevice =
              entries
                  .where((e) => e.source == EzanLibrarySource.asset)
                  .toList();
          final downloadable =
              entries
                  .where((e) => e.source == EzanLibrarySource.remote)
                  .toList();

          Widget entryTile(EzanLibraryEntry e) {
            final progress = _progress[e.id];
            final cached = _cached.contains(e.id);
            return _PickerTile(
              key: ValueKey(e.id),
              title: e.title,
              subtitle:
                  e.source == EzanLibrarySource.remote && !cached
                      ? 'İnternetten indirilir'
                      : null,
              selected: token == e.id,
              progress: progress,
              playing: playing == e.id,
              onSelect: () => _selectEntry(manifest!, e),
              onPlay: () => _preview(e.id, _sourceFor(manifest!, e)),
              onStop: () => audio.stopPreview(this),
            );
          }

          final children = <Widget>[
            _PickerTile(
              key: const ValueKey('default'),
              title: _defaultSource(prayer).title,
              subtitle: 'Varsayılan ezan',
              selected: token == null,
              playing: playing == 'default',
              onSelect: _selectDefault,
              onPlay: () => _preview('default', _defaultSource(prayer)),
              onStop: () => audio.stopPreview(this),
            ),
            _PickerTile(
              key: const ValueKey('phone'),
              title: 'Telefondan dosya seç',
              subtitle:
                  token != null && token.startsWith(customTokenPrefix)
                      ? 'Seçili: ${ref.watch(prayerAdhanTitleProvider(prayer)).valueOrNull ?? ''}'
                      : 'mp3, m4a, wav veya ogg',
              icon: Icons.folder_open_outlined,
              selected: token != null && token.startsWith(customTokenPrefix),
              onSelect: _pickFromPhone,
            ),
            if (snapshot.hasError)
              _EmptyNote('Ezan listesi okunamadı: ${snapshot.error}')
            else if (manifest == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (entries.isEmpty)
              _EmptyNote('“$_query” ile eşleşen ezan bulunamadı.')
            else ...[
              if (onDevice.isNotEmpty) const _PickerGroup('Cihazda'),
              ...onDevice.map(entryTile),
              if (downloadable.isNotEmpty)
                const _PickerGroup('İnternetten indirilebilir'),
              ...downloadable.map(entryTile),
            ],
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text(
                  '$label ezanı',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  prayer.isFajr
                      ? 'Bu listede yalnızca sabah (fecr) ezanları var. '
                          'Sabah ezanı başka vakitte okunmaz.'
                      : 'Sabah (fecr) ezanları bu listede yok, çünkü onlar '
                          'yalnızca sabah okunur.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ),
              if (!prayer.isFajr)
                CheckboxListTile(
                  value: _applyToAll,
                  onChanged: (v) => setState(() => _applyToAll = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text('Seçimi $otherNormals vakitlerine de uygula'),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Ezan veya müezzin ara',
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: children.length,
                  itemBuilder: (_, i) => children[i],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PickerGroup extends StatelessWidget {
  const _PickerGroup(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 6),
    child: Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: dashboardMuted(Theme.of(context).brightness),
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: dashboardMuted(Theme.of(context).brightness),
      ),
    ),
  );
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.selected,
    required this.onSelect,
    this.progress,
    this.playing = false,
    this.onPlay,
    this.onStop,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback onSelect;
  final double? progress;
  final bool playing;
  final VoidCallback? onPlay;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return ListTile(
      minTileHeight: 64,
      selected: selected,
      selectedColor: dashboardInk(b),
      selectedTileColor: dashboardActiveCell(b).withValues(alpha: 0.6),
      leading: Icon(
        selected
            ? Icons.check_circle_rounded
            : (icon ?? Icons.radio_button_unchecked),
        color: selected ? dashboardAccentGold : dashboardMuted(b),
      ),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null ? null : Text(subtitle!),
      onTap: progress == null ? onSelect : null,
      trailing:
          progress != null
              ? SizedBox(
                width: 48,
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: CircularProgressIndicator(
                    value: progress == 0 ? null : progress,
                    strokeWidth: 3,
                  ),
                ),
              )
              : onPlay == null
              ? null
              : PlayToggleButton(
                playing: playing,
                onPlay: onPlay!,
                onStop: onStop!,
              ),
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
