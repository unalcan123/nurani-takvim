import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/locations/data/models.dart';
import '../features/settings/data/alert_settings.dart';
import '../features/settings/data/prefs_repository.dart';
import '../features/settings/presentation/alert_settings_controller.dart';
import '../features/times/presentation/alarm_page.dart';
import '../features/times/presentation/time_utils.dart';
import '../features/times/presentation/times_page.dart' show timesProvider;
import 'notification_service.dart';

const List<String> _alarmPrayerNames = ['İmsak', 'Öğle', 'İkindi', 'Akşam', 'Yatsı'];

// Bir vaktin tam saatinden itibaren ne kadar süre içinde hâlâ "yeni girdi"
// sayılıp ezan tetiklenebileceği. Timer her saniye çalıştığı için normalde
// bu pencereye saniyeler içinde girilir; web'de arka plan sekmesi kısılması
// (throttling) gibi durumlara karşı biraz pay bırakır.
const Duration _arrivalGraceWindow = Duration(seconds: 90);
const Duration _alarmCooldown = Duration(seconds: 20);
const String _triggeredEventsPrefsKey = 'prayer_alarm_triggered_events_v1';

/// Uygulama açıkken — hangi ekranda olursa olsun (Ana Sayfa, TV modu,
/// Ayarlar vb.) — namaz vakitlerinin gerçekten girip girmediğini saniyede
/// bir kontrol eder. Vakit girdiğinde, kullanıcı o vakit için alarmı açık
/// bırakmışsa tam ekran [AlarmPage]'i açıp seçili ezan sesini çalar; "N
/// dakika kaldı" hatırlatmalarını tetikler; ve arka plan (OS) bildirimlerini
/// planlar/yeniden planlar.
///
/// Önceden bu mantığın tamamı yalnızca TV modundaki `TimesPage` içinde
/// vardı — normal (varsayılan) uygulama modunda hiçbir yerde
/// çalıştırılmıyordu, bu yüzden ezan/bildirimler sadece TV modunda
/// çalışıyor, normal modda hiç tetiklenmiyordu. Bu widget artık uygulama
/// kökünde (`app.dart`), moddan bağımsız tek bir yerde çalışır; bu yüzden
/// `TimesPage` kendi tetikleme mantığını artık içermez (aksi halde TV
/// modunda ezan iki kez çalar).
///
/// Aynı vaktin aynı gün içinde iki kez tetiklenmemesi için (sayfa
/// yenilenmesi / Flutter Web'de tam sayfa refresh dahil) tetiklenen
/// olaylar `SharedPreferences`'a da yazılır — yalnızca bellekte tutulan bir
/// bayrak, web'de sayfa yenilendiğinde sıfırlanıp ezanın tekrar
/// başlamasına yol açardı.
class PrayerAlarmWatcher extends ConsumerStatefulWidget {
  final Widget child;
  const PrayerAlarmWatcher({super.key, required this.child});

  @override
  ConsumerState<PrayerAlarmWatcher> createState() => _PrayerAlarmWatcherState();
}

class _PrayerAlarmWatcherState extends ConsumerState<PrayerAlarmWatcher> {
  Timer? _timer;
  List<Vakit>? _list;
  String? _ilceId;
  bool _isCoolingDown = false;
  bool _triggeredLoaded = false;

  String _triggeredDayKey = '';
  final Set<String> _triggeredToday = {};

  @override
  void initState() {
    super.initState();
    _loadTriggeredState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _dayKeyFor(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadTriggeredState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_triggeredEventsPrefsKey);
    final todayKey = _dayKeyFor(phoneLocalNow());
    if (raw != null) {
      final parts = raw.split('|');
      if (parts.isNotEmpty && parts.first == todayKey) {
        _triggeredDayKey = todayKey;
        _triggeredToday
          ..clear()
          ..addAll(parts.skip(1).where((e) => e.isNotEmpty));
      }
    }
    _triggeredLoaded = true;
  }

  Future<void> _persistTriggeredState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_triggeredEventsPrefsKey, '$_triggeredDayKey|${_triggeredToday.join('|')}');
  }

  bool _wasTriggered(String dayKey, String key) {
    if (dayKey != _triggeredDayKey) return false;
    return _triggeredToday.contains(key);
  }

  void _markTriggered(String dayKey, String key) {
    if (dayKey != _triggeredDayKey) {
      _triggeredDayKey = dayKey;
      _triggeredToday.clear();
    }
    _triggeredToday.add(key);
    unawaited(_persistTriggeredState());
  }

  DateTime _parseTime(String timeStr, DateTime date) {
    final parts = timeStr.split(':');
    return DateTime(date.year, date.month, date.day, int.parse(parts[0]), int.parse(parts[1]));
  }

  String? _timeStrFor(Vakit v, String prayerName) {
    switch (prayerName) {
      case 'İmsak':
        return v.imsak;
      case 'Öğle':
        return v.ogle;
      case 'İkindi':
        return v.ikindi;
      case 'Akşam':
        return v.aksam;
      case 'Yatsı':
        return v.yatsi;
    }
    return null;
  }

  void _tick() {
    if (!_triggeredLoaded || !mounted) return;
    final list = _list;
    final ilceId = _ilceId;
    if (list == null || ilceId == null) return;

    // Cihaz saati değil, prayer-times servisinden gelen vakitlerle
    // karşılaştırılan yerel saat (bkz. `time_utils.dart` — konum/servisin
    // döndürdüğü "HH:mm" değerleri zaten cihazın yerel saat dilimine göre
    // yorumlanır; ekstra bir UTC dönüşümü yapılmaz, aksi halde vakitler
    // yanlış kayar).
    final now = phoneLocalNow();
    final dayKey = _dayKeyFor(now);
    final today = findVakitForDate(list, now);
    if (today == null) {
      // Elimizdeki liste bugünü kapsamıyor (ör. ay değişti) — yeniden çek.
      ref.invalidate(timesProvider(ilceId));
      return;
    }

    final settings = ref.read(alertSettingsProvider);
    final notificationService = ref.read(notificationServiceProvider);

    for (final name in _alarmPrayerNames) {
      final timeStr = _timeStrFor(today, name);
      if (timeStr == null) continue;
      final prayerTime = _parseTime(timeStr, now);
      final diff = now.difference(prayerTime);
      if (diff < Duration.zero || diff > _arrivalGraceWindow) continue;

      final key = 'alarm_$name';
      if (_wasTriggered(dayKey, key)) continue;
      if (!settings.isPrayerEnabled(name)) continue;
      if (_isCoolingDown) continue;

      _markTriggered(dayKey, key);
      _isCoolingDown = true;

      // Tam ekran alarm sayfası zaten sesi çalacak; aynı an için
      // zamanlanmış olan OS bildirimini iptal ederiz — yoksa kullanıcı hem
      // sistem bildirimi sesini hem uygulama içi sesi birlikte, çift olarak
      // duyar.
      notificationService.cancelPrayerNotification(now, name);

      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => AlarmPage(nextPrayerName: name)),
      );

      Future.delayed(_alarmCooldown, () {
        _isCoolingDown = false;
      });
      break; // aynı tick'te en fazla bir vakit tetiklenir
    }

    final tomorrow = findVakitForDate(list, now.add(const Duration(days: 1)));
    final next = nextPrayerInfo(today, now, tomorrow: tomorrow);
    if (next.name != 'İmsak') {
      final remaining = next.time.difference(now);
      for (final minute in preNotificationMinutes) {
        if (!settings.isPreNotificationEnabled(minute)) continue;
        if (remaining.inMinutes != minute) continue;
        if (remaining.inSeconds % 60 > 1) continue;

        final key = 'pre_${minute}_${next.name}';
        if (_wasTriggered(dayKey, key)) continue;
        _markTriggered(dayKey, key);
        notificationService.showPrePrayerNotification(next.name, minute, preNotificationAssets[minute]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final recentLocations = ref.watch(prefsRepositoryProvider).getRecentLocations();
    final lastLocation = recentLocations.isNotEmpty ? recentLocations.first : null;

    if (lastLocation == null) {
      _list = null;
      _ilceId = null;
    } else {
      _ilceId = lastLocation.ilce.ilceId;
      final asyncTimes = ref.watch(timesProvider(lastLocation.ilce.ilceId));
      asyncTimes.whenData((list) {
        final isNewList = !identical(_list, list);
        _list = list;
        if (isNewList) {
          // Yeni veri geldiğinde (ilk yükleme / gün-ay değişimi sonrası
          // yeniden çekme) arka plan (OS) alarmlarını da güncel listeyle
          // yeniden planla.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref.read(notificationServiceProvider).scheduleAlarms(list, ref.read(alertSettingsProvider));
          });
        }
      });
    }

    ref.listen<AlertSettings>(alertSettingsProvider, (previous, next) {
      if (previous != next && _list != null) {
        ref.read(notificationServiceProvider).scheduleAlarms(_list!, next);
      }
    });

    return widget.child;
  }
}
