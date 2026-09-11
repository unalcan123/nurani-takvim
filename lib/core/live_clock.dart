import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/times/presentation/time_utils.dart';

final clockSourceProvider = Provider<DateTime Function()>(
  (ref) => phoneLocalNow,
);
final liveClockProvider =
    StateNotifierProvider.autoDispose<LiveClockNotifier, DateTime>((ref) {
      final clock = LiveClockNotifier(ref.watch(clockSourceProvider));
      ref.onCancel(clock.pause);
      ref.onResume(clock.start);
      return clock;
    });

class LiveClockNotifier extends StateNotifier<DateTime>
    with WidgetsBindingObserver {
  LiveClockNotifier(this.now) : super(now()) {
    WidgetsBinding.instance.addObserver(this);
    start();
  }
  final DateTime Function() now;
  Timer? _timer;
  void pause() => _timer?.cancel();
  void start() {
    pause();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
  }

  void refresh() => state = now();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    pause();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
