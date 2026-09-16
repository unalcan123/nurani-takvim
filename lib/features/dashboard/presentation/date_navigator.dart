import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'date_format.dart';
import 'selected_date_provider.dart';

/// Ana Sayfa ve Günlük İçerik sayfaları arasında ortak kullanılan gün gezinme
/// çubuğu (‹ Önceki Gün | tarih | Sonraki Gün ›).
/// `selectedDateProvider`'ı doğrudan okuyup yazar, böylece tüm sayfalar aynı
/// günü senkron gösterir.
class DateNavigatorBar extends ConsumerWidget {
  const DateNavigatorBar({super.key});

  Future<void> _pickDate(BuildContext context, WidgetRef ref, DateTime current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 5),
      lastDate: DateTime(current.year + 5),
      helpText: 'Bir tarih seçin',
      cancelText: 'Vazgeç',
      confirmText: 'Seç',
    );
    if (picked != null) {
      ref.read(selectedDateProvider.notifier).state = DateTime(picked.year, picked.month, picked.day);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final isToday = isSameDay(selectedDate, todayDateOnly());

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Önceki Gün',
              onPressed: () => ref.read(selectedDateProvider.notifier).state = selectedDate.subtract(const Duration(days: 1)),
            ),
            Expanded(
              child: InkWell(
                onTap: () => _pickDate(context, ref, selectedDate),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Text(
                        formatMiladiDate(selectedDate),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (!isToday)
                        TextButton(
                          onPressed: () => ref.read(selectedDateProvider.notifier).state = todayDateOnly(),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: const Size(64, 48),
                          ),
                          child: const Text('Bugüne dön'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Sonraki Gün',
              onPressed: () => ref.read(selectedDateProvider.notifier).state = selectedDate.add(const Duration(days: 1)),
            ),
          ],
        ),
      ),
    );
  }
}
