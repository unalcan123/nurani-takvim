import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dashboard sayfaları (Ana Sayfa, Günlük İçerik) arasında paylaşılan, o an
/// gösterilen günü tutan state.
final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});
