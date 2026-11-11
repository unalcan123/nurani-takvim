import 'package:flutter/material.dart';

import 'prayer_sound_section.dart';

/// Namaz bildirimleri ve ezan ayarları. Sıra, kullanıcının asıl işine göre:
/// önce hangi vakit hangi ezanla okunsun, sonra ses ve hatırlatmalar, en
/// sonda izinler ve deneme.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ezan ve Bildirimler')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
            children: const [
              SettingsSectionHeader(
                'Vakitler',
                caption:
                    'Açık olan vakitte ezan okunur. Her vaktin ezanını ayrı '
                    'seçebilirsiniz.',
              ),
              PrayerSoundSection(),
              SettingsSectionHeader('Ses ve hatırlatmalar'),
              ReminderAndVolumeCard(),
              SettingsSectionHeader('İzinler ve deneme'),
              AlarmDiagnosticsCard(),
            ],
          ),
        ),
      ),
    );
  }
}
