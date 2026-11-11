import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/prefs_repository.dart';
import '../../times/presentation/times_page.dart';
import '../../times/presentation/time_utils.dart';
import 'alert_settings_controller.dart';

class FajrDelaySetting extends ConsumerWidget {
  const FajrDelaySetting({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(alertSettingsProvider);
    final locations = ref.watch(prefsRepositoryProvider).getRecentLocations();
    final days =
        locations.isEmpty
            ? null
            : ref.watch(timesProvider(locations.first.ilce.ilceId)).valueOrNull;
    final now = phoneLocalNow();
    final available = days != null && findVakitForDate(days, now) != null;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
      leading: const Icon(Icons.schedule_outlined),
      title: Text(
        available
            ? 'Sabah ezanı imsaktan ${settings.fajrDelayMinutes} dakika sonra okunur'
            : 'Sabah ezanı vakti',
      ),
      subtitle: Text(
        available
            ? 'İmsak saati ve geri sayım değişmez.'
            : 'Önce şehir seçin ve güncel vakitlerin yüklenmesini bekleyin.',
      ),
      trailing: available ? const _ChangeLabel() : null,
      onTap:
          !available
              ? null
              : () async {
                var input = '${settings.fajrDelayMinutes}';
                String? error;
                await showDialog<void>(
                  context: context,
                  builder:
                      (context) => StatefulBuilder(
                        builder:
                            (context, update) => AlertDialog(
                              title: const Text('Sabah ezanı gecikmesi'),
                              content: TextFormField(
                                initialValue: input,
                                onChanged: (value) => input = value,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Dakika (0 dahil)',
                                  errorText: error,
                                  errorMaxLines: 4,
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Vazgeç'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    final minutes = int.tryParse(input.trim());
                                    try {
                                      if (minutes == null) {
                                        throw ArgumentError('Tam sayı girin.');
                                      }
                                      final futureDays =
                                          days.where((day) {
                                            final parts = day
                                                .miladiTarihKisaIso8601
                                                .split('.');
                                            final date = DateTime(
                                              int.parse(parts[2]),
                                              int.parse(parts[1]),
                                              int.parse(parts[0]),
                                            );
                                            return !date.isBefore(
                                              DateTime(
                                                now.year,
                                                now.month,
                                                now.day,
                                              ),
                                            );
                                          }).toList();
                                      await ref
                                          .read(alertSettingsProvider.notifier)
                                          .setFajrDelayMinutes(
                                            minutes,
                                            futureDays,
                                          );
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                      }
                                    } on ArgumentError catch (e) {
                                      update(
                                        () => error = e.message.toString(),
                                      );
                                    }
                                  },
                                  child: const Text('Kaydet'),
                                ),
                              ],
                            ),
                      ),
                );
              },
    );
  }
}

/// Satırın tamamı dokunulabilir; bu yalnızca eylemi gösteren etiket.
class _ChangeLabel extends StatelessWidget {
  const _ChangeLabel();

  @override
  Widget build(BuildContext context) => Text(
    'Değiştir',
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Theme.of(context).colorScheme.primary,
    ),
  );
}
