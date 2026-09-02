import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../data/alert_settings.dart';
import '../data/custom_audio_store.dart';
import '../data/notification_capabilities.dart';
import '../data/prayer_sound_playback.dart';
import '../data/prayer_sound_settings.dart';
import '../../../core/notification_service.dart';
import 'alert_settings_controller.dart';

const Map<String, String> _prayerDisplayLabels = {
  'İmsak': 'Sabah / İmsak',
  'Öğle': 'Öğle',
  'İkindi': 'İkindi',
  'Akşam': 'Akşam',
  'Yatsı': 'Yatsı',
};

/// "Ayarlar > Bildirimler" içine gömülen, her vakit için bağımsız ses
/// ayarını, ortak ses seviyesini, izin durumunu ve test butonlarını
/// içeren bölüm. Ana ekranda gösterilmez — yalnızca burada.
class PrayerSoundSection extends ConsumerStatefulWidget {
  const PrayerSoundSection({super.key});

  @override
  ConsumerState<PrayerSoundSection> createState() => _PrayerSoundSectionState();
}

class _PrayerSoundSectionState extends ConsumerState<PrayerSoundSection> {
  final _previewPlayer = AudioPlayer();

  /// Şu an önizlemesi çalınan şeyin anahtarı (vakit adı ya da 'test').
  /// Aynı anda yalnızca tek bir önizleme çalınabilsin diye tutulur.
  String? _playingKey;

  bool? _notificationsGranted;
  bool? _exactAlarmsGranted;

  @override
  void initState() {
    super.initState();
    _refreshPermissionStatus();
    _previewPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && mounted) {
        setState(() => _playingKey = null);
      }
    });
  }

  Future<void> _refreshPermissionStatus() async {
    final granted = await ref.read(notificationServiceProvider).areNotificationsEnabled();
    if (mounted) setState(() => _notificationsGranted = granted);
  }

  Future<void> _requestPermissions() async {
    final result = await ref.read(notificationServiceProvider).requestPermissions();
    if (!mounted) return;
    setState(() {
      _notificationsGranted = result.notificationsGranted;
      _exactAlarmsGranted = result.exactAlarmsGranted;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.notificationsGranted ? 'Bildirim izni verildi.' : 'Bildirim izni verilmedi — namaz vakti bildirimleri gösterilemeyecek.',
        ),
      ),
    );
  }

  Future<void> _stopPreview() async {
    if (_playingKey != null) {
      await _previewPlayer.stop();
      if (mounted) setState(() => _playingKey = null);
    }
  }

  Future<void> _togglePreview(String key, Future<bool> Function() start) async {
    if (_playingKey == key) {
      await _stopPreview();
      return;
    }
    await _stopPreview();
    final ok = await start();
    if (!mounted) return;
    if (ok) {
      setState(() => _playingKey = key);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bu ses için çalınacak bir dosya bulunamadı.')));
    }
  }

  Future<void> _previewPrayerSound(String prayerName) async {
    final settings = ref.read(alertSettingsProvider);
    final sound = settings.soundFor(prayerName);
    await _togglePreview(
      prayerName,
      () => playPrayerSound(
        player: _previewPlayer,
        prayerName: prayerName,
        setting: sound,
        customAudioStore: ref.read(customAudioStoreProvider),
        volume: settings.ezanVolume,
      ),
    );
  }

  Future<void> _sendTestNotification() async {
    await ref.read(notificationServiceProvider).showTestNotification();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Test bildirimi gönderildi.')));
  }

  Future<void> _pickCustomAudioFor(String prayerName) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'wav', 'ogg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    if (picked.bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dosya okunamadı.')));
      return;
    }
    try {
      await ref.read(alertSettingsProvider.notifier).addAndAssignCustomAudio(prayerName, picked.name, picked.bytes!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _openSoundPicker(String prayerName) async {
    final settings = ref.read(alertSettingsProvider);
    final current = settings.soundFor(prayerName);
    final customStore = ref.read(customAudioStoreProvider);
    final existingCustomFiles = await customStore.all();

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _SoundTypeSheet(
          prayerName: prayerName,
          displayLabel: _prayerDisplayLabels[prayerName] ?? prayerName,
          current: current,
          existingCustomFiles: existingCustomFiles,
          onSelectType: (type) async {
            await ref.read(alertSettingsProvider.notifier).setPrayerSoundType(prayerName, type);
          },
          onSelectExistingCustom: (id) async {
            await ref.read(alertSettingsProvider.notifier).assignCustomAudio(prayerName, id);
          },
          onPickNewFile: () async {
            Navigator.pop(sheetContext);
            await _pickCustomAudioFor(prayerName);
          },
          onDeleteCustomFile: (id) async {
            Navigator.pop(sheetContext);
            await ref.read(alertSettingsProvider.notifier).deleteCustomAudio(id);
            // Silme sonrası listeyi güncel haliyle tekrar açmak için sayfayı yeniden aç.
            await _openSoundPicker(prayerName);
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _previewPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(alertSettingsProvider);
    final capabilities = NotificationCapabilities.current();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CapabilityBanner(capabilities: capabilities),
        const SizedBox(height: 12),
        _PermissionCard(
          granted: _notificationsGranted,
          exactAlarmsGranted: _exactAlarmsGranted,
          onRequest: _requestPermissions,
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text('NAMAZ SESLERİ', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey)),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final prayerName in prayerNames) ...[
                _PrayerSoundTile(
                  prayerName: prayerName,
                  displayLabel: _prayerDisplayLabels[prayerName] ?? prayerName,
                  alarmEnabled: settings.isPrayerEnabled(prayerName),
                  sound: settings.soundFor(prayerName),
                  isPlaying: _playingKey == prayerName,
                  onTapSound: () => _openSoundPicker(prayerName),
                  onTogglePreview: () => _previewPrayerSound(prayerName),
                ),
                if (prayerName != prayerNames.last) const Divider(height: 1),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text('EZAN / BİLDİRİM SES SEVİYESİ', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey)),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.volume_down),
                Expanded(
                  child: Slider(
                    value: settings.ezanVolume,
                    onChanged: (v) => ref.read(alertSettingsProvider.notifier).setEzanVolume(v),
                  ),
                ),
                const Icon(Icons.volume_up),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _sendTestNotification,
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Test Bildirimi Gönder'),
          ),
        ),
      ],
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
        color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.5),
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
  final VoidCallback onRequest;

  const _PermissionCard({required this.granted, required this.exactAlarmsGranted, required this.onRequest});

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
        subtitle: exactAlarmsGranted == false
            ? const Text('Kesin alarm izni de gerekli olabilir (Android 12+) — bildirimler zamanında gelmeyebilir.')
            : null,
        trailing: TextButton(onPressed: onRequest, child: const Text('İzin İste')),
      ),
    );
  }
}

class _PrayerSoundTile extends StatelessWidget {
  final String prayerName;
  final String displayLabel;
  final bool alarmEnabled;
  final PrayerSoundSetting sound;
  final bool isPlaying;
  final VoidCallback onTapSound;
  final VoidCallback onTogglePreview;

  const _PrayerSoundTile({
    required this.prayerName,
    required this.displayLabel,
    required this.alarmEnabled,
    required this.sound,
    required this.isPlaying,
    required this.onTapSound,
    required this.onTogglePreview,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: alarmEnabled,
      leading: const Icon(Icons.mosque_outlined),
      title: Text(displayLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(alarmEnabled ? sound.type.displayName : 'Bu vakit için alarm kapalı'),
      onTap: alarmEnabled ? onTapSound : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (alarmEnabled && sound.type != PrayerSoundType.silent)
            IconButton(
              icon: Icon(isPlaying ? Icons.stop_circle_outlined : Icons.play_circle_outline),
              tooltip: isPlaying ? 'Durdur' : 'Sesi Test Et',
              onPressed: onTogglePreview,
            ),
          if (alarmEnabled) const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _SoundTypeSheet extends StatelessWidget {
  final String prayerName;
  final String displayLabel;
  final PrayerSoundSetting current;
  final List<CustomAudioFile> existingCustomFiles;
  final ValueChanged<PrayerSoundType> onSelectType;
  final ValueChanged<String> onSelectExistingCustom;
  final VoidCallback onPickNewFile;
  final ValueChanged<String> onDeleteCustomFile;

  const _SoundTypeSheet({
    required this.prayerName,
    required this.displayLabel,
    required this.current,
    required this.existingCustomFiles,
    required this.onSelectType,
    required this.onSelectExistingCustom,
    required this.onPickNewFile,
    required this.onDeleteCustomFile,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('$displayLabel — Ses Seç', style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            for (final type in [PrayerSoundType.adhan, PrayerSoundType.notification, PrayerSoundType.silent])
              RadioListTile<PrayerSoundType>(
                title: Text(type.displayName),
                value: type,
                groupValue: current.type,
                onChanged: (v) {
                  if (v == null) return;
                  onSelectType(v);
                  Navigator.pop(context);
                },
              ),
            RadioListTile<PrayerSoundType>(
              title: const Text('Kendi Sesim'),
              subtitle: Text(
                current.type == PrayerSoundType.custom
                    ? (existingCustomFiles.where((f) => f.id == current.customAudioId).map((f) => f.fileName).firstOrNull ?? 'Dosya seçilmedi')
                    : (existingCustomFiles.isEmpty ? 'Aşağıdan cihazınızdan bir dosya seçin' : 'Aşağıdan bir dosya seçin'),
              ),
              value: PrayerSoundType.custom,
              groupValue: current.type,
              onChanged: (v) {
                // Asıl seçim aşağıdaki dosya listesi / "Dosya Seç..." satırıyla
                // tamamlanır (hangi dosyanın kullanılacağı belirtilmeden yalnızca
                // türü 'custom' yapmanın bir anlamı yok); zaten kayıtlı dosya
                // varsa kolaylık olsun diye ilkini seçilmiş kabul ederiz.
                if (existingCustomFiles.isNotEmpty) {
                  onSelectExistingCustom(existingCustomFiles.first.id);
                  Navigator.pop(context);
                }
              },
            ),
            if (existingCustomFiles.isNotEmpty)
              ...existingCustomFiles.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.music_note, size: 20),
                    title: Text(f.fileName, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${(f.sizeBytes / 1024).toStringAsFixed(0)} KB'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (current.type == PrayerSoundType.custom && current.customAudioId == f.id)
                          const Icon(Icons.check, color: Colors.green),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                          tooltip: 'Bu dosyayı kaldır',
                          onPressed: () => onDeleteCustomFile(f.id),
                        ),
                      ],
                    ),
                    onTap: () {
                      onSelectExistingCustom(f.id);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.upload_file_outlined, size: 20),
                title: const Text('Cihazdan ses dosyası seç...'),
                subtitle: const Text('mp3, m4a, wav, ogg'),
                onTap: onPickNewFile,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
