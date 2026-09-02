import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/alert_settings.dart';
import 'alert_settings_controller.dart';
import 'prayer_sound_section.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(alertSettingsProvider);
    final alertController = ref.read(alertSettingsProvider.notifier);
    final textTheme = Theme.of(context).textTheme;

    final anyAlarmEnabled = settings.prayerAlarms.values.any((isEnabled) => isEnabled);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Uygulama Ayarları'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Prayer Time Alarms ---
          Padding(
            padding: const EdgeInsets.only(left: 16.0, bottom: 8),
            child: Text('VAKİT GİRİNCE ALARMLAR', style: textTheme.titleSmall?.copyWith(color: Colors.grey)),
          ),
          Card(
            child: Column(
              children: prayerNames
                  .map((name) => SwitchListTile(
                        title: Text('$name Vakti Alarmı'),
                        value: settings.isPrayerEnabled(name),
                        onChanged: (value) => alertController.togglePrayerAlarm(name, value),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 24),

          // --- Pre-Notification Alarms ---
          Padding(
            padding: const EdgeInsets.only(left: 16.0, bottom: 8),
            child: Text('SON YARIM SAAT UYARILARI', style: textTheme.titleSmall?.copyWith(color: Colors.grey)),
          ),
          Card(
            child: Column(
              children: preNotificationMinutes
                  .map((minute) => SwitchListTile(
                        title: Text('$minute Dakika Kala Uyar'),
                        subtitle: const Text('İmsak hariç tüm vakitler için'),
                        value: settings.isPreNotificationEnabled(minute),
                        onChanged: (value) => alertController.togglePreNotification(minute, value),
                      ))
                  .toList(),
            ),
          ),

          // --- Namaz Sesleri (vakit başına bağımsız ses ayarı) ---
          if (anyAlarmEnabled) ...[
            const SizedBox(height: 24),
            const PrayerSoundSection(),
          ],
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
