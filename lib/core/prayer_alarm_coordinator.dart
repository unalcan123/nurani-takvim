import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/settings/data/prefs_repository.dart';
import '../features/settings/presentation/alert_settings_controller.dart';
import '../features/times/presentation/alarm_page.dart';
import 'audio_manager.dart';
import 'notification_service.dart';
import 'prayer_event_store.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final previewRouteObserver = RouteObserver<ModalRoute<dynamic>>();
final prayerAlarmCoordinatorProvider = Provider<PrayerAlarmCoordinator>((ref) {
  final coordinator = PrayerAlarmCoordinator(ref);
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

class PrayerAlarmCoordinator {
  final Ref _ref;
  StreamSubscription<String>? _notificationSubscription;
  bool _isShowingAlarm = false;
  PrayerAlarmCoordinator(this._ref) {
    _notificationSubscription = _ref
        .read(notificationServiceProvider)
        .prayerNotificationStream
        .listen(_fromNotification);
  }

  Future<void> _fromNotification(String payload) async {
    final parts = payload.split('|');
    final date = parts.length == 2 ? DateTime.tryParse(parts[1]) : null;
    // Old notifications without a date must not replay an already handled day.
    await triggerPrayerTime(
      prayerName: parts.first,
      scheduledDate: date ?? DateTime.now(),
      showNotification: false,
    );
  }

  Future<void> handleInitialNotificationLaunch() async {
    final payload =
        _ref.read(notificationServiceProvider).takeInitialPrayerNotification();
    if (payload != null) await _fromNotification(payload);
  }

  Future<void> triggerPrayerTime({
    required String prayerName,
    bool showNotification = true,
    DateTime? scheduledDate,
    bool isTest = false,
  }) async {
    if (_isShowingAlarm) return;
    if (!isTest &&
        !_ref.read(alertSettingsProvider).isPrayerEnabled(prayerName)) {
      return;
    }
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    final date = scheduledDate ?? DateTime.now();
    final now = DateTime.now();
    if (!isTest &&
        (date.year != now.year ||
            date.month != now.month ||
            date.day != now.day)) {
      return;
    }
    _isShowingAlarm = true;
    final audio = _ref.read(audioManagerProvider);
    bool started = false;
    try {
      if (!isTest &&
          !await PrayerEventStore(
            _ref.read(sharedPrefsProvider),
          ).claim(date, prayerName)) {
        return;
      }
      started = true;
      await audio.stopAllForAdhan();
      try {
        await _ref
            .read(notificationServiceProvider)
            .cancelPrayerNotification(date, prayerName);
      } catch (e) {
        debugPrint('Vakit bildirimi iptal edilemedi: $e');
      }
      if (!navigator.mounted) return;
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => AlarmPage(nextPrayerName: prayerName),
        ),
      );
    } catch (e, stack) {
      debugPrint('Ezan başlatılamadı: $e\n$stack');
    } finally {
      try {
        if (started) {
          try {
            await audio.stopAdhan();
          } finally {
            await audio.resumeAfterAdhan();
          }
        }
      } finally {
        _isShowingAlarm = false;
      }
    }
  }

  void dispose() {
    _notificationSubscription?.cancel();
  }
}
