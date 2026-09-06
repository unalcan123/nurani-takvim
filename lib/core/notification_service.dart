import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:just_audio/just_audio.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../features/locations/data/models.dart';
import '../features/settings/data/alert_settings.dart';

/// Bildirim izinlerinin gerçek durumu (kullanıcı hiç sorulmadıysa, izin
/// verdiyse ya da reddettiyse Ayarlar ekranında dürüstçe gösterilebilsin diye).
class NotificationPermissionResult {
  final bool notificationsGranted;
  final bool? exactAlarmsGranted; // Android 12 öncesi/iOS'ta anlamsız -> null
  final bool?
  fullScreenIntentGranted; // Android 14 öncesi/iOS'ta anlamsız -> null
  const NotificationPermissionResult({
    required this.notificationsGranted,
    this.exactAlarmsGranted,
    this.fullScreenIntentGranted,
  });
}

class NotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  final AudioPlayer _audioPlayer;
  bool adhanActive = false;
  final StreamController<String> _prayerNotificationController =
      StreamController<String>.broadcast();
  String? _initialPrayerNotification;
  static const MethodChannel _androidNotificationChannel = MethodChannel(
    'com.tvaap/notifications',
  );

  NotificationService(this._notificationsPlugin, {AudioPlayer? audioPlayer})
    : _audioPlayer = audioPlayer ?? AudioPlayer();

  Stream<String> get prayerNotificationStream =>
      _prayerNotificationController.stream;

  String? takeInitialPrayerNotification() {
    final value = _initialPrayerNotification;
    _initialPrayerNotification = null;
    return value;
  }

  Future<void> init() async {
    tz.initializeTimeZones();
    await _configureLocalTimezone();

    const initializationSettingsAndroid = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    // iOS'ta izin isteme işlemini kendimiz `requestPermissions()` ile ayrı
    // yapıyoruz (uygulama açılışında sessizce sormak yerine, kullanıcıya bunu
    // ne için istediğimizi anlatabileceğimiz bir noktada). Bu yüzden burada
    // otomatik istek göndermiyoruz.
    const initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        _handleNotificationPayload(details.payload);
      },
    );

    final launchDetails =
        await _notificationsPlugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _initialPrayerNotification = _prayerNameFromPayload(
        launchDetails?.notificationResponse?.payload,
      );
    }

    await _createNotificationChannels();
  }

  /// Cihazın gerçek IANA saat dilimini (ör. `Europe/Istanbul`) bulup
  /// `timezone` paketine tanıtır. Bu çağrılmazsa `tz.local` sessizce UTC'ye
  /// düşer ve TÜM zamanlanmış namaz bildirimleri, cihazın UTC farkı kadar
  /// (Türkiye'de 3 saat) YANLIŞ saatte tetiklenir.
  Future<void> _configureLocalTimezone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      // Saat dilimi tespit edilemezse UTC'de kalır; en azından sessizce
      // yanlış davranmak yerine hata ayıklama günlüğüne düşer.
      debugPrint('Saat dilimi tespit edilemedi, UTC kullanılacak: $e');
    }
  }

  /// Bildirim (ve Android 12+ için kesin alarm) izinlerini kullanıcıya sorar.
  /// Web'de bu API'ler yoktur (flutter_local_notifications web'i desteklemez),
  /// bu yüzden web'de her zaman `notificationsGranted: false` döner — ayarlar
  /// ekranı bunu görüp gerçek durumu gösterebilsin diye.
  Future<NotificationPermissionResult> requestPermissions() async {
    if (kIsWeb) {
      return const NotificationPermissionResult(
        notificationsGranted: false,
        exactAlarmsGranted: null,
      );
    }

    final androidPlugin =
        _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    if (androidPlugin != null) {
      final notifGranted =
          await androidPlugin.requestNotificationsPermission() ?? false;
      final exactGranted = await androidPlugin.requestExactAlarmsPermission();
      final fullScreenGranted = await canUseFullScreenIntent();
      return NotificationPermissionResult(
        notificationsGranted: notifGranted,
        exactAlarmsGranted: exactGranted,
        fullScreenIntentGranted: fullScreenGranted,
      );
    }

    final iosPlugin =
        _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
    if (iosPlugin != null) {
      final granted =
          await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      return NotificationPermissionResult(
        notificationsGranted: granted,
        exactAlarmsGranted: null,
      );
    }

    return const NotificationPermissionResult(
      notificationsGranted: false,
      exactAlarmsGranted: null,
    );
  }

  /// Mevcut izin durumunu (yeniden istemeden) okur — Ayarlar ekranında
  /// "İzin verildi / reddedildi / henüz sorulmadı" göstermek için.
  Future<bool?> areNotificationsEnabled() async {
    if (kIsWeb) return false;
    final androidPlugin =
        _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    if (androidPlugin != null) return androidPlugin.areNotificationsEnabled();
    return null; // iOS'ta senkron bir "durumu oku" API'si yok; yalnızca istek sonucu bilinir.
  }

  Future<bool?> canUseFullScreenIntent() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _androidNotificationChannel.invokeMethod<bool>(
        'canUseFullScreenIntent',
      );
    } catch (e) {
      debugPrint('Tam ekran bildirim izni okunamadı: $e');
      return null;
    }
  }

  Future<void> openFullScreenIntentSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _androidNotificationChannel.invokeMethod<void>(
        'openFullScreenIntentSettings',
      );
    } catch (e) {
      debugPrint('Tam ekran bildirim ayarı açılamadı: $e');
    }
  }

  Future<void> _createNotificationChannels() async {
    final androidPlugin =
        _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    if (androidPlugin != null) {
      // Ezan Kanalı
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'ezan_vakti_v6',
          'Ezan Vakti Uyarıları',
          description: 'Namaz vakitlerinde ezan okur.',
          importance: Importance.max,
          playSound: false,
          enableVibration: true,
          showBadge: true,
        ),
      );
      // Hatırlatıcı Kanalları
      for (final minute in preNotificationMinutes) {
        final soundFileName = _getPreNotificationSoundFileName(minute);
        await androidPlugin.createNotificationChannel(
          AndroidNotificationChannel(
            _preNotificationChannelId(minute),
            'Vakit Yaklaşıyor ($minute dk)',
            description: 'Vakte $minute dakika kaldığını bildirir.',
            importance: Importance.max,
            playSound: soundFileName != null,
            sound:
                soundFileName == null
                    ? null
                    : RawResourceAndroidNotificationSound(soundFileName),
          ),
        );
      }
      // Test bildirimi kanalı
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'test_bildirimi_v1',
          'Test Bildirimi',
          description: 'Ayarlar ekranından gönderilen deneme bildirimi.',
          importance: Importance.max,
          playSound: true,
        ),
      );
    }
  }

  Future<void> showPrayerTimeNotification(String prayerName) async {
    const androidDetails = AndroidNotificationDetails(
      'ezan_vakti_v6',
      'Ezan Vakti Uyarıları',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      playSound: false,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
    );
    await _notificationsPlugin.show(
      0,
      'Vakit Girdi: $prayerName',
      'Ezan okunuyor...',
      const NotificationDetails(android: androidDetails),
      payload: _prayerPayload(prayerName),
    );
  }

  /// Ayarlar ekranındaki "Test Bildirimi Gönder" butonu için: gerçek
  /// planlama/izin/ses altyapısını kullanarak anında bir bildirim gösterir.
  Future<void> showTestNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'test_bildirimi_v1',
      'Test Bildirimi',
      importance: Importance.max,
      priority: Priority.high,
      visibility: NotificationVisibility.public,
    );
    await _notificationsPlugin.show(
      999999,
      'Test Bildirimi',
      'Bildirim sistemi çalışıyor. Bu bir deneme bildirimidir.',
      const NotificationDetails(android: androidDetails),
    );
  }

  Future<void> showPrePrayerNotification(
    String prayerName,
    int minute,
    String? assetPath,
  ) async {
    // Uygulama içindeyken ses çal
    if (assetPath != null && !adhanActive) {
      try {
        await _audioPlayer.setAsset(assetPath);
        if (!adhanActive) _audioPlayer.play();
      } catch (e) {
        debugPrint("Pre-notification audio error: $e");
      }
    }

    final soundFileName = _getPreNotificationSoundFileName(minute);
    final androidDetails = AndroidNotificationDetails(
      _preNotificationChannelId(minute),
      'Vakit Yaklaşıyor ($minute dk)',
      importance: Importance.max,
      priority: Priority.high,
      sound:
          soundFileName == null
              ? null
              : RawResourceAndroidNotificationSound(soundFileName),
      playSound: soundFileName != null,
      visibility: NotificationVisibility.public,
    );
    await _notificationsPlugin.show(
      minute,
      'Vakit Yaklaşıyor',
      '$prayerName vaktine $minute dk kaldı.',
      NotificationDetails(android: androidDetails),
    );
  }

  Future<void> _scheduleQueue = Future.value();

  Future<void> scheduleAlarms(List<Vakit> vakitler, AlertSettings settings) {
    if (kIsWeb) return Future.value();
    final next = _scheduleQueue.then(
      (_) => _scheduleAlarms(vakitler, settings),
    );
    _scheduleQueue = next.catchError(
      (Object e) => debugPrint('Alarm planlama: $e'),
    );
    return next;
  }

  Future<void> _scheduleAlarms(
    List<Vakit> vakitler,
    AlertSettings settings,
  ) async {
    try {
      await _notificationsPlugin.cancelAll();
    } catch (e) {
      // Cihazda daha önce (eski bir sürümden kalma) bozuk/uyumsuz kayıtlı bir
      // planlama varsa `cancelAll` bile istisna fırlatabilir (gerçek cihazda
      // gözlemlendi: flutter_local_notifications'ın eski planlamaları
      // yeniden yüklemeye çalışırken attığı bir istisna). Bunu yutmazsak bu
      // fonksiyon hiçbir zaman hiçbir bildirim planlayamaz hale gelir.
      debugPrint(
        'scheduleAlarms: cancelAll başarısız oldu, yine de devam ediliyor: $e',
      );
    }
    final now = DateTime.now();

    for (final vakit in vakitler) {
      final prayers = [
        MapEntry('İmsak', vakit.imsak),
        MapEntry('Öğle', vakit.ogle),
        MapEntry('İkindi', vakit.ikindi),
        MapEntry('Akşam', vakit.aksam),
        MapEntry('Yatsı', vakit.yatsi),
      ];

      final prayerDate = _parseVakitDate(vakit.miladiTarihKisaIso8601);

      for (var i = 0; i < prayers.length; i++) {
        final prayer = prayers[i];
        final prayerTime = _parseDateTime(
          vakit.miladiTarihKisaIso8601,
          prayer.value,
        );
        if (prayerTime.isBefore(now)) continue;

        if (settings.isPrayerEnabled(prayer.key)) {
          final androidDetails = AndroidNotificationDetails(
            'ezan_vakti_v6',
            'Ezan Vakti Uyarıları',
            importance: Importance.max,
            priority: Priority.high,
            playSound: false,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
          );

          try {
            await _notificationsPlugin.zonedSchedule(
              prayerNotificationId(prayerDate, i),
              'Vakit Girdi: ${prayer.key}',
              'Ezan ekranını açmak için dokunun.',
              tz.TZDateTime.from(prayerTime, tz.local),
              NotificationDetails(android: androidDetails),
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
              payload: _prayerPayload(prayer.key, prayerTime),
            );
          } catch (e) {
            // Tek bir gün/vaktin planlanması (ör. geçersiz/bulunamayan bir
            // ses kaynağı yüzünden) başarısız olursa, bu diğer tüm
            // gün/vakitlerin planlanmasını engellememeli.
            debugPrint(
              'scheduleAlarms: ${prayer.key} (${vakit.miladiTarihKisaIso8601}) planlanamadı: $e',
            );
          }
        }

        if (prayer.key == 'İmsak') continue;

        for (var m = 0; m < preNotificationMinutes.length; m++) {
          final minute = preNotificationMinutes[m];
          if (!settings.isPreNotificationEnabled(minute)) continue;

          final preNotificationTime = prayerTime.subtract(
            Duration(minutes: minute),
          );
          if (preNotificationTime.isBefore(now)) continue;

          final preSound = _getPreNotificationSoundFileName(minute);
          final preSoundResource =
              preSound == null
                  ? null
                  : RawResourceAndroidNotificationSound(preSound);

          final preAndroidDetails = AndroidNotificationDetails(
            _preNotificationChannelId(minute),
            'Vakit Yaklaşıyor ($minute dk)',
            importance: Importance.max,
            priority: Priority.high,
            sound: preSoundResource,
            playSound: preSoundResource != null,
            visibility: NotificationVisibility.public,
          );

          try {
            await _notificationsPlugin.zonedSchedule(
              preNotificationId(prayerDate, i, m),
              'Vakit Yaklaşıyor',
              '${prayer.key} vaktine $minute dk kaldı.',
              tz.TZDateTime.from(preNotificationTime, tz.local),
              NotificationDetails(android: preAndroidDetails),
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
          } catch (e) {
            debugPrint(
              'scheduleAlarms: ${prayer.key} için $minute dk hatırlatması planlanamadı: $e',
            );
          }
        }
      }
    }
  }

  /// Uygulama önplandayken tam ekran alarm sayfası ([AlarmPage]) gösterilip
  /// ses orada çalınacaksa, aynı an için zaten planlanmış olan OS bildirimi
  /// iptal edilir — aksi halde kullanıcı hem sistem bildirimini/sesini hem
  /// de uygulama içi sesi aynı anda duyar (çift ses/bildirim).
  Future<void> cancelPrayerNotification(
    DateTime date,
    String prayerName,
  ) async {
    if (kIsWeb) return;
    final index = prayerNames.indexOf(prayerName);
    if (index == -1) return;
    await _notificationsPlugin.cancel(prayerNotificationId(date, index));
  }

  String? _getPreNotificationSoundFileName(int minute) {
    switch (minute) {
      case 30:
        return 'dakikakivaruyarisisesi_30';
      case 20:
        return 'dakikakivaruyarisisesi_20';
      case 10:
        return 'dakikakivaruyarisisesi_10';
    }
    return null;
  }

  String _preNotificationChannelId(int minute) => 'pre_prayer_${minute}_v6';

  DateTime _parseDateTime(String dateStr, String timeStr) {
    final d = dateStr.split('.');
    final t = timeStr.split(':');
    return DateTime(
      int.parse(d[2]),
      int.parse(d[1]),
      int.parse(d[0]),
      int.parse(t[0]),
      int.parse(t[1]),
    );
  }

  DateTime _parseVakitDate(String dateStr) {
    final d = dateStr.split('.');
    return DateTime(int.parse(d[2]), int.parse(d[1]), int.parse(d[0]));
  }

  Future<void> setAdhanPlaybackActive(bool active) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _androidNotificationChannel.invokeMethod<void>(
        active ? 'startAdhanPlayback' : 'stopAdhanPlayback',
      );
    } catch (e) {
      debugPrint('Ezan arka plan servisi: $e');
    }
  }

  Future<void> stopTransientAudio() async {
    try {
      await _audioPlayer.stop();
    } catch (e) {
      debugPrint('Geçici bildirim sesi durdurulamadı: $e');
    }
  }

  void dispose() {
    _prayerNotificationController.close();
    _audioPlayer.dispose();
  }

  void _handleNotificationPayload(String? payload) {
    final prayerName = _prayerNameFromPayload(payload);
    if (prayerName == null) return;
    _prayerNotificationController.add(prayerName);
  }

  String _prayerPayload(String prayerName, [DateTime? date]) =>
      'prayer:$prayerName|${(date ?? DateTime.now()).toIso8601String()}';

  String? _prayerNameFromPayload(String? payload) {
    if (payload == null || !payload.startsWith('prayer:')) return null;
    final prayerName = payload.substring('prayer:'.length);
    return prayerNames.contains(prayerName.split('|').first)
        ? prayerName
        : null;
  }
}

/// Belirli bir gün + vakit için kararlı (deterministik) bildirim id'si.
/// Aynı gün/vakit için her zaman aynı id üretir; böylece hem yeniden
/// planlamalarda çakışma olmaz hem de tek bir bildirim iptal edilebilir
/// (bkz. [NotificationService.cancelPrayerNotification]).
int prayerNotificationId(DateTime date, int prayerIndex) {
  final daysSinceEpoch = date.difference(DateTime(2020, 1, 1)).inDays;
  return daysSinceEpoch * 10 + prayerIndex; // prayerIndex: 0..4
}

int preNotificationId(DateTime date, int prayerIndex, int minuteIndex) {
  final daysSinceEpoch = date.difference(DateTime(2020, 1, 1)).inDays;
  return 1000000 + daysSinceEpoch * 100 + prayerIndex * 10 + minuteIndex;
}

final flutterLocalNotificationsProvider =
    Provider<FlutterLocalNotificationsPlugin>(
      (ref) => FlutterLocalNotificationsPlugin(),
    );
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService(
    ref.watch(flutterLocalNotificationsProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
